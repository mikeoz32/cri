module Cri
  module Wasm
    class ConformanceResult
      getter errors : Array(String)
      getter exports : Array(String)
      getter imports : Array(String)
      getter has_memory : Bool

      def initialize(@errors = [] of String, @exports = [] of String, @imports = [] of String, @has_memory = false)
      end

      def valid? : Bool
        errors.empty?
      end
    end

    class ConformanceChecker
      MAGIC = Bytes[0x00, 0x61, 0x73, 0x6d]
      VERSION = Bytes[0x01, 0x00, 0x00, 0x00]

      def check(path : String) : ConformanceResult
        bytes = File.read(path).to_slice
        parser = Parser.new(bytes)
        parser.parse

        errors = [] of String
        errors << "invalid WASM magic" unless parser.magic?
        errors << "unsupported WASM version" unless parser.version?
        errors << "WASM modules must not import host/WASI capabilities" unless parser.imports.empty?
        errors << "module must export memory" unless parser.has_memory
        ["alloc", "cri_call", "cri_result_len"].each do |required|
          errors << "missing required export: #{required}" unless parser.exports.includes?(required)
        end

        ConformanceResult.new(errors, parser.exports, parser.imports, parser.has_memory)
      rescue ex
        ConformanceResult.new(["could not parse WASM: #{ex.message || ex.class.name}"])
      end

      private class Parser
        getter exports = [] of String
        getter imports = [] of String
        getter has_memory = false

        def initialize(@bytes : Bytes)
          @offset = 0
          @magic = false
          @version = false
        end

        def parse
          @magic = read_bytes(4) == MAGIC
          @version = read_bytes(4) == VERSION
          return unless @magic && @version

          while @offset < @bytes.size
            section_id = read_u8
            section_size = read_uleb
            section_end = @offset + section_size
            raise "section exceeds module size" if section_end > @bytes.size

            case section_id
            when 2 then parse_imports(section_end)
            when 5 then parse_memory(section_end)
            when 7 then parse_exports(section_end)
            end
            @offset = section_end
          end
        end

        def magic? : Bool
          @magic
        end

        def version? : Bool
          @version
        end

        private def parse_imports(section_end : Int32)
          count = read_uleb
          count.times do
            module_name = read_name
            name = read_name
            kind = read_u8
            imports << "#{module_name}.#{name}"
            skip_import_description(kind)
          end
          raise "invalid import section" if @offset > section_end
        end

        private def skip_import_description(kind : Int32)
          case kind
          when 0 then read_uleb # function type index
          when 1
            read_u8 # element type
            skip_limits
          when 2
            skip_limits
          when 3
            read_u8 # value type
            read_u8 # mutability
          when 4
            read_uleb # attribute
            read_uleb # type index
          else
            raise "unknown import kind: #{kind}"
          end
        end

        private def parse_memory(section_end : Int32)
          count = read_uleb
          @has_memory = count > 0
          count.times { skip_limits }
          raise "invalid memory section" if @offset > section_end
        end

        private def skip_limits
          flags = read_uleb
          read_uleb # minimum
          read_uleb if (flags & 0x01) != 0
        end

        private def parse_exports(section_end : Int32)
          count = read_uleb
          count.times do
            name = read_name
            kind = read_u8
            read_uleb # index
            exports << name if kind == 0
            @has_memory = true if kind == 2 && name == "memory"
          end
          raise "invalid export section" if @offset > section_end
        end

        private def read_u8 : Int32
          raise "unexpected end of WASM" if @offset >= @bytes.size
          value = @bytes[@offset].to_i
          @offset += 1
          value
        end

        private def read_uleb : Int32
          value = 0
          shift = 0
          loop do
            byte = read_u8
            value |= (byte & 0x7f) << shift
            return value if (byte & 0x80) == 0
            shift += 7
            raise "invalid LEB128 integer" if shift > 35
          end
        end

        private def read_bytes(size : Int32) : Bytes
          raise "unexpected end of WASM" if @offset + size > @bytes.size
          result = @bytes[@offset, size]
          @offset += size
          result
        end

        private def read_name : String
          size = read_uleb
          String.new(read_bytes(size))
        end
      end
    end
  end
end

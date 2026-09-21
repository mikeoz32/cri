{% if flag?(:wasm3) %}
  module Cri
    module Wasm
      # Minimal wasm3 adapter for the current JSON ABI and effect loop.
      # The module receives no imports: capabilities are returned as effects
      # and executed by the Crystal host between call/resume invocations.
      class Wasm3Runtime < Runtime
        DEFAULT_STACK_SIZE = 64_u32 * 1024
        DEFAULT_GAS_LIMIT  = 10_000_000.0
        MAX_EFFECT_ROUNDS  =           32

        getter stack_size : UInt32
        getter gas_limit : Float64

        def initialize(@stack_size : UInt32 = DEFAULT_STACK_SIZE, @gas_limit : Float64 = DEFAULT_GAS_LIMIT)
        end

        def call(manifest : Extensions::Manifest, request : RequestEnvelope) : ResponseEnvelope
          invocation = Invocation.new(manifest, stack_size, gas_limit)
          invocation.call(request)
        rescue ex
          failure("wasm3 invocation failed: #{ex.message || ex.class.name}")
        ensure
          invocation.try(&.close)
        end

        def run(manifest : Extensions::Manifest, request : RequestEnvelope, handler : Effects::Handler) : ResponseEnvelope
          invocation = Invocation.new(manifest, stack_size, gas_limit)
          response = invocation.call(request)
          rounds = 0

          while response.ok && !response.effects.empty?
            rounds += 1
            return failure("effect loop exceeded #{MAX_EFFECT_ROUNDS} rounds") if rounds > MAX_EFFECT_ROUNDS

            results = response.effects.map do |effect|
              JSON.parse(handler.handle(effect).to_json)
            end
            response = invocation.resume(request, results)
          end

          response
        rescue ex
          failure("wasm3 effect loop failed: #{ex.message || ex.class.name}")
        ensure
          invocation.try(&.close)
        end

        private def failure(message : String) : ResponseEnvelope
          ResponseEnvelope.new(false, nil, [] of JSON::Any, message)
        end

        private class Invocation
          DEFAULT_MEMORY_INDEX = 0_u32

          getter manifest : Extensions::Manifest
          getter environment : Pointer(Void)
          getter runtime : Pointer(Void)

          @module_handle : Pointer(Void)
          @memory : Pointer(UInt8)
          @memory_size : UInt64
          @alloc : Pointer(Void)
          @call_function : Pointer(Void)
          @result_len : Pointer(Void)
          @resume_function : Pointer(Void)?
          @init_function : Pointer(Void)?
          @free : Pointer(Void)?
          @free_result : Pointer(Void)?
          @closed = false

          def initialize(@manifest : Extensions::Manifest, stack_size : UInt32, gas_limit : Float64)
            path = manifest.wasm_path
            raise "extension has no wasm module" unless path
            raise "wasm module not found: #{path}" unless File.file?(path)

            # wasm3 requires source bytes to remain alive while the module is loaded.
            @wasm_bytes = File.read(path).to_slice
            @environment = LibWasm3.m3_NewEnvironment
            raise "wasm3 could not create environment" if environment.null?

            @runtime = LibWasm3.m3_NewRuntime(environment, stack_size, Pointer(Void).null)
            raise "wasm3 could not create runtime" if runtime.null?

            LibWasm3.m3_SetGasLimit(runtime, gas_limit)
            @module_handle = Pointer(Void).null
            check!(LibWasm3.m3_ParseModule(environment, pointerof(@module_handle), @wasm_bytes.to_unsafe, @wasm_bytes.size.to_u32), "parse module")
            check!(LibWasm3.m3_LoadModule(runtime, @module_handle), "load module")

            @memory_size = 0_u64
            @memory = LibWasm3.m3_GetMemory(@module_handle, pointerof(@memory_size), DEFAULT_MEMORY_INDEX)
            raise "WASM module must declare memory" if @memory.null?

            @alloc = require_function("alloc")
            @call_function = require_function("cri_call")
            @result_len = require_function("cri_result_len")
            @resume_function = find_function("cri_resume")
            @init_function = find_function("cri_init")
            @free = find_function("free") || find_function("cri_free")
            @free_result = find_function("cri_free_result")
            call_void(@init_function.not_nil!, [] of Int32, "cri_init") if @init_function
          end

          def call(request : RequestEnvelope) : ResponseEnvelope
            invoke(@call_function, request)
          end

          def resume(original : RequestEnvelope, results : Array(JSON::Any)) : ResponseEnvelope
            function = @resume_function
            raise "WASM module has effects but does not export cri_resume" unless function

            input = JSON.parse({
              "results" => results,
            }.to_json)
            request = RequestEnvelope.new("resume", original.name, input, original.context)
            invoke(function, request)
          end

          def close
            return if @closed
            @closed = true
            LibWasm3.m3_FreeRuntime(runtime) unless runtime.null?
            LibWasm3.m3_FreeEnvironment(environment) unless environment.null?
          end

          private def invoke(function : Pointer(Void), request : RequestEnvelope) : ResponseEnvelope
            input = request.to_json
            input_ptr = call_i32(@alloc, [input.bytesize.to_i32], "alloc")
            ensure_memory_range!(input_ptr, input.bytesize)
            write_memory(input_ptr, input.to_slice)

            result_ptr = call_i32(function, [input_ptr, input.bytesize.to_i32], request.kind == "resume" ? "cri_resume" : "cri_call")
            output_size = call_i32(@result_len, [] of Int32, "cri_result_len")
            ensure_memory_range!(result_ptr, output_size)
            output = String.new(@memory + result_ptr, output_size)

            call_void(@free.not_nil!, [input_ptr, input.bytesize.to_i32], "free") if @free
            call_void(@free_result.not_nil!, [result_ptr, output_size], "cri_free_result") if @free_result

            ResponseEnvelope.from_json(output)
          end

          private def require_function(name : String) : Pointer(Void)
            find_function(name) || raise "WASM module is missing required export: #{name}"
          end

          private def find_function(name : String) : Pointer(Void)?
            function = Pointer(Void).null
            result = LibWasm3.m3_FindFunctionIn(pointerof(function), @module_handle, name.to_unsafe)
            return nil unless result.null?
            function
          end

          private def call_i32(function : Pointer(Void), values : Array(Int32), label : String) : Int32
            arguments = Pointer(Pointer(Void)).null
            storage = Pointer(Int32).null

            unless values.empty?
              arguments = Pointer(Pointer(Void)).malloc(values.size)
              storage = Pointer(Int32).malloc(values.size)
              values.each_with_index do |value, index|
                storage[index] = value
                arguments[index] = (storage + index).as(Pointer(Void))
              end
            end

            check!(LibWasm3.m3_Call(function, values.size.to_u32, arguments), label)
            # Guest allocators and ABI functions may execute memory.grow. wasm3
            # can replace the backing allocation, so never retain the pointer
            # obtained before the guest call.
            refresh_memory!
            result = 0_i32
            result_pointers = Pointer(Pointer(Void)).malloc(1)
            result_pointers[0] = pointerof(result).as(Pointer(Void))
            check!(LibWasm3.m3_GetResults(function, 1_u32, result_pointers), "#{label} results")
            result
          end

          private def call_void(function : Pointer(Void), values : Array(Int32), label : String)
            arguments = Pointer(Pointer(Void)).null
            storage = Pointer(Int32).null

            unless values.empty?
              arguments = Pointer(Pointer(Void)).malloc(values.size)
              storage = Pointer(Int32).malloc(values.size)
              values.each_with_index do |value, index|
                storage[index] = value
                arguments[index] = (storage + index).as(Pointer(Void))
              end
            end

            check!(LibWasm3.m3_Call(function, values.size.to_u32, arguments), label)
          end

          private def refresh_memory!
            @memory_size = 0_u64
            @memory = LibWasm3.m3_GetMemory(@module_handle, pointerof(@memory_size), DEFAULT_MEMORY_INDEX)
            raise "WASM module memory is unavailable" if @memory.null?
          end

          private def write_memory(offset : Int32, bytes : Bytes)
            bytes.each_with_index { |byte, index| (@memory + offset + index)[0] = byte }
          end

          private def ensure_memory_range!(offset : Int32, length : Int32)
            raise "invalid guest memory range" if offset < 0 || length < 0
            raise "guest memory access out of bounds" if offset.to_u64 > @memory_size || length.to_u64 > @memory_size - offset.to_u64
          end

          private def check!(result : Pointer(UInt8), operation : String)
            return if result.null?
            raise "#{operation}: #{String.new(result)}"
          end
        end
      end
    end
  end
{% end %}

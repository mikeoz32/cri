module Cri
  module Tui
    class KeyDecoder
      @pending : UInt8? = nil

      def initialize(@input : IO)
      end

      def next_event : KeyEvent?
        byte = @pending
        @pending = nil
        byte ||= @input.read_byte
        byte ? decode(byte) : nil
      end

      def decode(byte : UInt8) : KeyEvent?
        case byte
        when 3      then KeyEvent.new(Key::CtrlC)
        when 4      then KeyEvent.new(Key::CtrlD)
        when 5      then KeyEvent.new(Key::CtrlE)
        when 21     then KeyEvent.new(Key::CtrlU)
        when 23     then KeyEvent.new(Key::CtrlW)
        when 25     then KeyEvent.new(Key::CtrlY)
        when 8, 127 then KeyEvent.new(Key::Backspace)
        when 9      then KeyEvent.new(Key::Tab)
        when 10, 13 then KeyEvent.new(Key::Enter)
        when 27     then decode_escape
        else
          return nil if byte < 32
          size = case byte
                 when 0..127   then 1
                 when 194..223 then 2
                 when 224..239 then 3
                 when 240..244 then 4
                 else               return nil
                 end
          bytes = Bytes.new(size)
          bytes[0] = byte
          (1...size).each do |index|
            following = @input.read_byte
            return nil unless following
            bytes[index] = following
          end
          text = String.new(bytes)
          text.valid_encoding? ? KeyEvent.character(text) : nil
        end
      end

      private def escape_byte : UInt8?
        if input = @input.as?(IO::FileDescriptor)
          previous = input.read_timeout
          begin
            input.read_timeout = 30.milliseconds
            input.read_byte
          rescue IO::TimeoutError
            nil
          ensure
            input.read_timeout = previous
          end
        else
          @input.read_byte
        end
      end

      private def decode_escape : KeyEvent
        first = escape_byte
        unless first == 91_u8
          @pending = first
          return KeyEvent.new(Key::Escape)
        end
        case escape_byte
        when 65 then KeyEvent.new(Key::Up)
        when 66 then KeyEvent.new(Key::Down)
        when 67 then KeyEvent.new(Key::Right)
        when 68 then KeyEvent.new(Key::Left)
        else         KeyEvent.new(Key::Escape)
        end
      end
    end
  end
end

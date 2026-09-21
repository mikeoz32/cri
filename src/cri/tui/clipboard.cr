require "base64"

module Cri
  module Tui
    # Clipboard is a host capability. Extensions can request copy through the
    # public UI API without writing terminal escape sequences themselves.
    abstract class Clipboard
      abstract def copy(text : String)
    end

    class MemoryClipboard < Clipboard
      getter content : String = ""

      def copy(text : String)
        @content = text
      end
    end

    # OSC 52 lets a terminal provide the system clipboard without a native
    # platform dependency. The in-memory value remains available for tests and
    # hosts that do not support OSC 52.
    class TerminalClipboard < MemoryClipboard
      def initialize(@output : IO = STDOUT)
      end

      def copy(text : String)
        super(text)
        encoded = Base64.strict_encode(text)
        @output.print("\e]52;c;#{encoded}\a")
        @output.flush
      end
    end
  end
end

module Cri
  module Tui
    # Interactive entry point. TTYs use the fullscreen renderer; pipes use the
    # deterministic line renderer for scripts and tests.
    class Shell
      getter controller : Controller

      def initialize(host : Host, provider : Provider = Providers::OpenAICompatible.new)
        @controller = Controller.new(host, provider)
      end

      def run
        if STDIN.tty? && STDOUT.tty?
          Application.new(controller).run
        else
          run_lines
        end
      end

      private def run_lines
        puts "cri — type /help for commands, /exit to quit"
        prompt

        while line = STDIN.gets
          input = line.strip
          if input.empty?
            prompt
            next
          end

          begin
            keep_running, output = controller.submit(input)
            puts output unless output.empty?
            break unless keep_running
          rescue ex
            STDERR.puts "error: #{ex.message || ex.class.name}"
          end
          prompt
        end
      end

      private def prompt
        print "> "
        STDOUT.flush
      end
    end
  end
end

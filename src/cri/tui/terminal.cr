module Cri
  module Tui
    class Terminal
      def self.dimensions : Tuple(Int32, Int32)
        output = IO::Memory.new
        status = Process.run("stty", args: ["size"], input: Process::Redirect::Inherit, output: output, error: Process::Redirect::Close)
        if status.success?
          parts = output.to_s.split.map(&.to_i)
          return {parts[1], parts[0]} if parts.size == 2 && parts.all?(&.positive?)
        end
        {(ENV["COLUMNS"]? || "80").to_i, (ENV["LINES"]? || "24").to_i}
      rescue
        {(ENV["COLUMNS"]? || "80").to_i, (ENV["LINES"]? || "24").to_i}
      end

      def initialize
        @saved_state = nil.as(String?)
      end

      def enter_raw_mode
        output = IO::Memory.new
        status = Process.run("stty", args: ["-g"], input: Process::Redirect::Inherit, output: output)
        raise "cannot read terminal settings" unless status.success?
        @saved_state = output.to_s.strip
        status = Process.run("stty", args: ["raw", "-echo"], input: Process::Redirect::Inherit)
        unless status.success?
          restore
          raise "cannot enable raw terminal mode"
        end
        print "\e[?1049h"
      end

      def restore
        state = @saved_state
        return unless state && !state.empty?
        Process.run("stty", args: [state], input: Process::Redirect::Inherit)
        @saved_state = nil
      end
    end
  end
end

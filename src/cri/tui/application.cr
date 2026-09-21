module Cri
  module Tui
    class Application
      getter controller : Controller
      getter ui : UiRuntime
      getter handler : EventHandler
      @running : Bool = true
      @dirty : Bool = true
      @render_ticks : Int32 = 0
      @last_dimensions : Tuple(Int32, Int32)? = nil
      @renderer : Renderer

      def initialize(@controller : Controller)
        @ui = UiRuntime.new(clipboard: TerminalClipboard.new)
        enabled = controller.host.extensions.enabled(controller.host.config.grants)
        Extensions::UiActionBridge.new(@ui, controller.host.invoker, enabled).register_all
        @handler = EventHandler.new(ui, controller)
        @renderer = Renderer.new(ui.workspace, ui.buffers, theme: ui.theme)
        @dirty = true
        subscribe_to_ui_events
        subscribe_to_host_events
      end

      def workspace : Workspace
        ui.workspace
      end

      def run
        terminal = Terminal.new
        decoder = KeyDecoder.new(STDIN)
        terminal.enter_raw_mode
        begin
          render_if_dirty
          finished = Channel(Nil).new
          spawn do
            begin
              while @running
                watch_resize
                render_if_dirty
                sleep 16.milliseconds
              end
            ensure
              finished.send(nil)
            end
          end
          begin
            while @running
              event = decoder.next_event
              break unless event
              @running = handler.handle(event) { }
            end
          ensure
            @running = false
            finished.receive
          end
        ensure
          terminal.restore
          print "\e[?25h\e[?1049l"
          STDOUT.flush
        end
      end

      private def subscribe_to_ui_events
        # Extensions may add event names later. Any UiRuntime event invalidates
        # this application, so render scheduling is not coupled to a fixed list.
        ui.subscribe_all { |_event| @dirty = true }
      end

      private def subscribe_to_host_events
        controller.host.events.subscribe("tool.completed") do |event|
          name = event.data["name"]?.try(&.as_s) || "tool"
          ok = event.data["ok"]?.try(&.as_bool) || false
          ui.set_activity("#{ok ? "✓" : "×"} #{name}\n", ok ? "tool" : "error")
        end
      end

      private def watch_resize
        @render_ticks += 1
        return unless (@render_ticks % 15) == 0
        dimensions = Terminal.dimensions
        if @last_dimensions != dimensions
          @last_dimensions = dimensions
          @dirty = true
        end
      end

      private def render_if_dirty
        return unless @dirty
        @last_dimensions = Terminal.dimensions
        @renderer.workspace = ui.workspace
        @renderer.resize(@last_dimensions.not_nil![0], @last_dimensions.not_nil![1])
        @renderer.render
        @dirty = false
      end
    end

    # Compatibility alias for callers that used the old name.
    alias Fullscreen = Application
  end
end

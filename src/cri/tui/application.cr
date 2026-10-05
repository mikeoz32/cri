module Cri
  module Tui
    class Application
      getter controller : Controller
      getter ui : UiRuntime
      getter handler : EventHandler
      getter renderer : Renderer
      @running : Bool = true
      @dirty : Bool = true
      @render_ticks : Int32 = 0
      @last_dimensions : Tuple(Int32, Int32)? = nil
      @renderer : Renderer
      @approvals = [] of API::CapabilityRequest

      def initialize(@controller : Controller)
        broker = controller.host.capabilities
        if broker.backend.is_a?(API::DenyAllBackend)
          broker.backend = API::EventApprovalBackend.new(controller.host.events)
        end
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
              @running = handle_key(event)
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

      def handle_key(event : KeyEvent) : Bool
        if approval = @approvals.first?
          if event.key.escape? || event.key.character? && {"n", "N"}.includes?(event.value || "")
            controller.host.capabilities.resolve(approval.id, API::ApprovalDecision::Deny)
            @approvals.shift
          elsif event.key.character? && {"y", "Y"}.includes?(event.value || "")
            controller.host.capabilities.resolve(approval.id, API::ApprovalDecision::Allow)
            @approvals.shift
          end
          update_approval_prompt
          return true
        end
        handler.handle(event) { }
      end

      private def subscribe_to_ui_events
        # Extensions may add event names later. Any UiRuntime event invalidates
        # this application, so render scheduling is not coupled to a fixed list.
        ui.subscribe_all { |_event| @dirty = true }
      end

      private def subscribe_to_host_events
        controller.host.events.subscribe("approval.requested") do |event|
          data = event.data
          @approvals << API::CapabilityRequest.new(
            data["id"].as_s,
            data["actor"].as_s,
            data["capability"].as_s,
            data["target"].as_s,
            data["reason"].as_s
          )
          update_approval_prompt
        end
        controller.host.events.subscribe("tool.completed") do |event|
          name = event.data["name"]?.try(&.as_s) || "tool"
          ok = event.data["ok"]?.try(&.as_bool) || false
          ui.set_activity("#{ok ? "✓" : "×"} #{name}\n", ok ? "tool" : "error")
        end
      end

      private def update_approval_prompt
        if approval = @approvals.first?
          target = approval.target
          graphemes = target.each_grapheme.to_a
          target = "…#{graphemes.last(16).join}" if graphemes.size > 20
          @renderer.approval_prompt = "Approve #{approval.capability} by #{approval.actor} at #{target} [y]allow [n/Esc]deny"
        else
          @renderer.approval_prompt = nil
        end
        @dirty = true
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

module Cri
  module Tui
    # Dispatches semantic keymap actions. It deliberately does not encode key
    # bindings; users/extensions can rebind UiRuntime#keymap independently.
    class EventHandler
      getter ui : UiRuntime
      getter controller : Controller

      @auth_prompt : {String, String}?

      def initialize(@ui : UiRuntime, @controller : Controller)
        @history = [] of String
        @history_index = 0
        @submission_running = false
        @auth_prompt = nil
      end

      def handle(event : KeyEvent, &refresh : -> Nil) : Bool
        match = ui.keymap.resolve(ui.mode, event)
        return true unless match.kind.action?
        dispatch(match.action.not_nil!, event, refresh)
      end

      private def dispatch(action : String, event : KeyEvent, refresh : Proc(Nil)) : Bool
        case action
        when "mode.insert"
          ui.begin_insert || ui.set_activity("panel is read-only\n", "activity")
        when "mode.append"
          if ui.begin_insert
            ui.focused_buffer.not_nil!.cursor += 1
          else
            ui.set_activity("panel is read-only\n", "activity")
          end
        when "mode.command"
          ui.begin_command
        when "mode.visual"
          ui.begin_visual || ui.set_activity("no focused buffer\n", "activity")
        when "mode.normal"
          if @auth_prompt
            cancel_auth_prompt
          else
            ui.end_insert
          end
        when "mode.normal_clear"
          if @auth_prompt
            cancel_auth_prompt
          else
            ui.input.clear
            ui.end_command
          end
        when "input.insert"
          ui.focused_buffer.try { |buffer| buffer.insert(event.value || "") }
        when "input.backspace"
          ui.focused_buffer.try(&.backspace)
        when "input.cursor_left", "buffer.cursor_left"
          ui.focused_buffer.try { |buffer| buffer.cursor -= 1 }
        when "input.cursor_right", "buffer.cursor_right"
          ui.focused_buffer.try { |buffer| buffer.cursor += 1 }
        when "buffer.cursor_up"
          ui.focused_buffer.try { |buffer| buffer.move_vertical(-1) }
        when "buffer.cursor_down"
          ui.focused_buffer.try { |buffer| buffer.move_vertical(1) }
        when "history.previous"
          history_up
        when "history.next"
          history_down
        when "panel.scroll_down"
          focused_panel.try(&.scroll_by(-1))
        when "panel.scroll_up"
          focused_panel.try(&.scroll_by(1))
        when "panel.page_down"
          focused_panel.try { |panel| panel.scroll_by(-panel.page_size) }
        when "panel.page_up"
          focused_panel.try { |panel| panel.scroll_by(panel.page_size) }
        when "panel.focus_left"
          ui.workspace.focus_direction("left")
        when "panel.focus_right"
          ui.workspace.focus_direction("right")
        when "panel.focus_up"
          ui.workspace.focus_direction("up")
        when "panel.focus_down"
          ui.workspace.focus_direction("down")
        when "prompt.submit"
          return true unless ui.prompt_focused?
          return submit(false, refresh)
        when "command.submit"
          return true unless ui.prompt_focused?
          return submit(true, refresh)
        when "selection.yank"
          ui.yank_selection || ui.set_activity("empty selection\n", "activity")
        else
          context = ActionContext.new(ui, event, action)
          unless ui.actions.dispatch(action, context)
            ui.events.emit(Event.new("ui.keymap.action", JSON.parse({
              "action" => action,
              "key"    => event.token,
              "mode"   => ui.mode.label,
            }.to_json)))
          end
        end
        true
      end

      private def submit(command_mode : Bool, refresh : Proc(Nil)) : Bool
        if command_mode
          return submit_now(command_mode, refresh)
        end

        return true if @submission_running
        @submission_running = true
        spawn do
          begin
            submit_now(false, refresh)
          ensure
            @submission_running = false
          end
        end
        true
      end

      private def submit_now(command_mode : Bool, refresh : Proc(Nil)) : Bool
        raw = ui.input.content

        if @auth_prompt
          return finish_auth_prompt(raw)
        end

        return true if raw.strip.empty?

        if command_mode && begin_auth_prompt(raw)
          ui.append_transcript(": #{raw}\n", "command")
          @history << raw
          @history_index = @history.size
          ui.input.clear
          ui.input.mode = Mode::Insert
          ui.input.masked = true
          ui.input_panel.prompt = "token: "
          ui.set_activity("enter token, Escape cancels\n", "activity")
          return true
        end

        command = command_mode ? "/#{raw}" : raw.strip
        ui.append_transcript(command_mode ? ": #{raw}\n" : "> #{raw}\n", command_mode ? "command" : "user")
        @history << raw
        @history_index = @history.size
        ui.input.clear
        ui.workspace.status = "thinking"
        ui.set_activity("thinking…\n", "activity")
        keep_running = true
        streamed = false
        stream_prefix = true

        begin
          keep_running, output = controller.submit(command) do |chunk|
            streamed = true
            if stream_prefix
              ui.append_transcript("assistant: ", "assistant")
              stream_prefix = false
            end
            ui.append_transcript(chunk, "assistant")
          end
          if streamed
            ui.append_transcript("\n", "assistant")
          elsif !output.empty?
            ui.append_transcript("assistant: #{output}\n", "assistant")
          end
        rescue ex
          ui.append_transcript("error: #{ex.message || ex.class.name}\n", "error")
        ensure
          ui.workspace.status = "ready"
          ui.set_activity("ready\n", "activity")
          command_mode ? ui.end_command : ui.end_insert
        end
        keep_running
      end

      private def begin_auth_prompt(raw : String) : Bool
        parts = raw.split
        return false unless parts.size >= 3 && parts[0] == "auth" && parts[1] == "login"

        provider_id = parts[2]
        provider = controller.host.providers.find(provider_id)
        return false unless provider
        flow_id = parts[3]? || provider.auth_flows.first?.try(&.id)
        flow = flow_id && provider.auth_flows.find { |candidate| candidate.id == flow_id }
        return false unless flow && flow.not_nil!.kind == Auth::FlowKind::ApiToken

        @auth_prompt = {provider_id, flow.not_nil!.id}
        true
      end

      private def finish_auth_prompt(token : String) : Bool
        provider_id, flow_id = @auth_prompt.not_nil!
        if token.empty?
          ui.set_activity("empty token; try again or Escape to cancel\n", "activity")
          return true
        end

        begin
          ref = controller.host.login_api_token(provider_id, flow_id, token)
          ui.append_transcript("assistant: saved #{provider_id}/#{flow_id} as #{ref.id}\n", "assistant")
          ui.set_activity("authentication saved\n", "activity")
        rescue ex
          ui.append_transcript("error: #{ex.message || ex.class.name}\n", "error")
          ui.set_activity("authentication failed\n", "activity")
        ensure
          clear_auth_prompt
        end
        true
      end

      private def cancel_auth_prompt
        ui.input.clear
        clear_auth_prompt
        ui.set_activity("authentication cancelled\n", "activity")
      end

      private def clear_auth_prompt
        @auth_prompt = nil
        ui.input.clear
        ui.input.masked = false
        ui.input_panel.prompt = "> "
        ui.end_command
      end

      private def history_up
        return if @history.empty?
        @history_index = {@history_index - 1, 0}.max
        ui.input.replace(@history[@history_index])
      end

      private def history_down
        return if @history.empty?
        @history_index = {@history_index + 1, @history.size}.min
        ui.input.replace(@history_index == @history.size ? "" : @history[@history_index])
      end

      private def focused_panel : Panel?
        ui.workspace.panels.focused
      end
    end
  end
end

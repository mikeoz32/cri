module Cri
  module Tui
    # Application-scoped UI root. All buffer and panel changes publish to one
    # event bus; workspaces only own panel/layout state.
    class UiRuntime
      include Effects::UiSink

      getter events : EventBus
      getter clipboard : Clipboard
      getter keymap : Keymap
      getter actions : ActionRegistry
      getter theme : Theme = Theme.new

      def define_style(group : String, style : Style)
        theme.define(group, style)
        invalidate("theme.changed")
      end

      getter buffers : BufferStore
      getter workspaces : WorkspaceStore

      def initialize(@events : EventBus = EventBus.new, @clipboard : Clipboard = MemoryClipboard.new)
        @keymap = Keymap.new
        @actions = ActionRegistry.new
        @buffers = BufferStore.new(events)
        @workspaces = WorkspaceStore.new
        @prompt_origins = {} of String => String
        configure_default_theme
        configure_default_keymap

        create_buffer("transcript", owner: "core", persistent: true)
        create_buffer("input", owner: "ui")
        create_buffer("activity", "ready\n", owner: "core", persistent: true)

        main = create_workspace("main")
        main.add_panel("transcript", "transcript", "Conversation", "main", true, editable: false)
        main.add_panel("activity", "activity", "Activity", "right", editable: false)
        main.add_panel("input", "input", "Prompt", "bottom", false, "> ", editable: true)
      end

      def workspace : Workspace
        workspaces.active
      end

      def transcript : TextBuffer
        buffers.get("transcript").as(TextBuffer)
      end

      def input : TextBuffer
        buffers.get("input").as(TextBuffer)
      end

      def focused_buffer : TextBuffer?
        panel = workspace.panels.focused
        panel.try { |item| buffers.get(item.buffer_id).as?(TextBuffer) }
      end

      def prompt_focused? : Bool
        workspace.panels.focused.try(&.id) == "input"
      end

      def mode : Mode
        focused_buffer.try(&.mode) || Mode::Normal
      end

      def begin_insert : Bool
        panel = workspace.panels.focused
        return false unless panel && panel.editable
        buffer = buffers.get(panel.buffer_id).as?(TextBuffer)
        return false unless buffer
        buffer.mode = Mode::Insert
        true
      end

      # Command mode is a command-line operation, so it temporarily focuses
      # the dedicated Prompt buffer and restores the previous panel on exit.
      def begin_command
        origin = workspace.panels.focused
        @prompt_origins[workspace.id] = origin.id if origin && origin.id != "input"
        input.clear
        input.mode = Mode::Command
        input_panel.prompt = ": "
        workspace.focus("input")
      end

      def end_command
        input.mode = Mode::Normal
        input_panel.prompt = "> "
        origin = @prompt_origins.delete(workspace.id)
        workspace.focus(origin) if origin && workspace.panels.panels.has_key?(origin)
      end

      def end_insert
        focused_buffer.try { |buffer| buffer.mode = Mode::Normal }
      end

      def begin_visual : Bool
        buffer = focused_buffer
        return false unless buffer
        buffer.begin_visual
        true
      end

      def end_visual
        focused_buffer.try { |buffer| buffer.mode = Mode::Normal }
      end

      def yank_selection : Bool
        buffer = focused_buffer
        return false unless buffer
        selected = buffer.selected_text
        return false if selected.empty?
        clipboard.copy(selected)
        end_visual
        set_activity("copied #{selected.chars.size} characters\n", "activity")
        true
      end

      def activity : TextBuffer
        buffers.get("activity").as(TextBuffer)
      end

      def append_transcript(text : String, group : String? = nil)
        start = transcript.content.size.to_i32
        transcript.append(text)
        transcript.highlight(start, transcript.content.size.to_i32, group.not_nil!) if group && !text.empty?
      end

      def restore_session(session : Session)
        transcript.clear
        session.messages.each do |message|
          case message.role
          when "user"
            append_transcript("> #{message.content || ""}\n", "user")
          when "assistant"
            if content = message.content
              append_transcript("assistant: #{content}\n", "assistant") unless content.empty?
            end
            message.tool_calls.each do |call|
              append_transcript("assistant: [tool call #{call.name}]\n", "assistant")
            end
          when "tool"
            append_transcript("tool: #{message.content || ""}\n", "tool")
          end
        end
      end

      def set_activity(text : String, group : String? = nil)
        activity.replace(text)
        activity.highlight(0, activity.content.size.to_i32, group.not_nil!) if group && !text.empty?
      end

      def notify(message : String, level : String)
        set_activity("[#{level}] #{message}\n", "activity")
        events.emit(Event.new("ui.notification", JSON.parse({"message" => message, "level" => level}.to_json), "ui"))
      end

      def create_ui_buffer(id : String, content : String, owner : String) : String
        buffer_id = plugin_buffer_id(id, owner)
        create_buffer(buffer_id, content, owner: owner)
        buffer_id
      end

      def append_ui_buffer(id : String, content : String, owner : String) : String
        buffer = plugin_buffer(id, owner)
        buffer.append(content)
        plugin_buffer_id(id, owner)
      end

      def replace_ui_buffer(id : String, content : String, owner : String) : String
        buffer = plugin_buffer(id, owner)
        buffer.replace(content)
        plugin_buffer_id(id, owner)
      end

      def set_ui_highlight(id : String, start : Int32, finish : Int32, group : String, owner : String) : String
        buffer = plugin_buffer(id, owner)
        resolved_group = resolve_ui_group(group, owner)
        buffer.highlight(start, finish, resolved_group)
        plugin_buffer_id(id, owner)
      end

      def define_ui_style(group : String, foreground : Int32?, bold : Bool, underline : Bool, owner : String) : String
        resolved_group = plugin_style_id(group, owner)
        define_style(resolved_group, Style.new(foreground, bold, underline))
        resolved_group
      end

      private def resolve_ui_group(group : String, owner : String) : String
        return group if theme[group]
        resolved = plugin_style_id(group, owner)
        raise "unknown UI highlight style: #{group}" unless theme[resolved]
        resolved
      end

      private def plugin_style_id(group : String, owner : String) : String
        "plugin:#{owner}:#{group}"
      end

      def open_ui_panel(id : String, buffer_id : String, title : String, position : String, focus : Bool, owner : String) : String
        plugin_buffer(buffer_id, owner)
        panel_id = plugin_panel_id(id, owner)
        workspace.add_panel(panel_id, plugin_buffer_id(buffer_id, owner), title, position, focus)
        panel_id
      end

      def focus_ui_panel(id : String, owner : String) : String
        panel_id = plugin_panel_id(id, owner)
        raise "unknown UI panel: #{id}" unless workspace.panels.includes?(panel_id)
        workspace.focus(panel_id)
        panel_id
      end

      private def plugin_panel_id(id : String, owner : String) : String
        "plugin:#{owner}:#{id}"
      end

      private def plugin_buffer_id(id : String, owner : String) : String
        "plugin:#{owner}:#{id}"
      end

      private def plugin_buffer(id : String, owner : String) : TextBuffer
        buffer = buffers.get(plugin_buffer_id(id, owner)).as?(TextBuffer)
        raise "unknown UI buffer: #{id}" unless buffer
        buffer
      end

      def input_panel : Panel
        workspace.panels.get("input")
      end

      def subscribe(event_name : String, &listener : Event -> Nil)
        events.subscribe(event_name, &listener)
      end

      def subscribe_all(&listener : Event -> Nil)
        events.subscribe_all(&listener)
      end

      def invalidate(reason : String = "ui.changed")
        events.emit(Event.new("ui.invalidate", JSON.parse({"reason" => reason}.to_json)))
      end

      def create_buffer(id : String, content : String = "", owner : String = "extension", persistent : Bool = false, mode : Mode = Mode::Normal) : TextBuffer
        buffers.text(id, content, owner, persistent, mode)
      end

      def create_text_panel(id : String, title : String, position : String = "right", owner : String = "extension") : TextBuffer
        raise "panel already exists: #{id}" if workspace.panels.includes?(id)
        buffer = create_buffer("panel:#{id}", owner: owner)
        begin
          workspace.add_panel(id, buffer.id, title, position)
        rescue ex
          buffers.remove(buffer.id)
          raise ex
        end
        buffer
      end

      def create_workspace(id : String) : Workspace
        checker = ->(buffer_id : String) { buffers.includes?(buffer_id) }
        workspace = Workspace.new(id, PanelStore.new, events, checker)
        workspaces.register(workspace)
        workspace
      end

      def create_panel(workspace_id : String, id : String, buffer_id : String, title : String, position : String = "right", editable : Bool = true) : Panel
        target = workspaces.get(workspace_id)
        raise "unknown buffer: #{buffer_id}" unless buffers.includes?(buffer_id)
        target.add_panel(id, buffer_id, title, position, editable: editable)
      end

      def activate_workspace(id : String)
        workspaces.activate(id)
        invalidate("workspace.activated")
      end

      private def configure_default_keymap
        keymap.bind(Mode::Normal, "i", "mode.insert")
        keymap.bind(Mode::Normal, "a", "mode.append")
        keymap.bind(Mode::Normal, "v", "mode.visual")
        keymap.bind(Mode::Normal, ":", "mode.command")
        keymap.bind(Mode::Normal, "h", "buffer.cursor_left")
        keymap.bind(Mode::Normal, "j", "buffer.cursor_down")
        keymap.bind(Mode::Normal, "k", "buffer.cursor_up")
        keymap.bind(Mode::Normal, "l", "buffer.cursor_right")
        keymap.bind(Mode::Normal, "ctrl-e", "panel.scroll_down")
        keymap.bind(Mode::Normal, "ctrl-y", "panel.scroll_up")
        keymap.bind(Mode::Normal, "ctrl-d", "panel.page_down")
        keymap.bind(Mode::Normal, "ctrl-u", "panel.page_up")
        keymap.bind(Mode::Normal, "ctrl-w h", "panel.focus_left")
        keymap.bind(Mode::Normal, "ctrl-w j", "panel.focus_down")
        keymap.bind(Mode::Normal, "ctrl-w k", "panel.focus_up")
        keymap.bind(Mode::Normal, "ctrl-w l", "panel.focus_right")

        [Mode::Insert, Mode::Command].each do |mode|
          keymap.bind(mode, "<char>", "input.insert")
          keymap.bind(mode, "backspace", "input.backspace")
          keymap.bind(mode, "left", "input.cursor_left")
          keymap.bind(mode, "right", "input.cursor_right")
          keymap.bind(mode, "up", "history.previous")
          keymap.bind(mode, "down", "history.next")
        end
        keymap.bind(Mode::Insert, "escape", "mode.normal")
        keymap.bind(Mode::Insert, "ctrl-c", "mode.normal")
        keymap.bind(Mode::Insert, "ctrl-d", "mode.normal")
        keymap.bind(Mode::Insert, "enter", "prompt.submit")
        keymap.bind(Mode::Command, "escape", "mode.normal_clear")
        keymap.bind(Mode::Command, "ctrl-c", "mode.normal_clear")
        keymap.bind(Mode::Command, "ctrl-d", "mode.normal_clear")
        keymap.bind(Mode::Command, "enter", "command.submit")

        keymap.bind(Mode::Visual, "h", "buffer.cursor_left")
        keymap.bind(Mode::Visual, "j", "buffer.cursor_down")
        keymap.bind(Mode::Visual, "k", "buffer.cursor_up")
        keymap.bind(Mode::Visual, "l", "buffer.cursor_right")
        keymap.bind(Mode::Visual, "escape", "mode.normal")
        keymap.bind(Mode::Visual, "ctrl-c", "mode.normal")
        keymap.bind(Mode::Visual, "y", "selection.yank")
      end

      private def configure_default_theme
        theme.define("user", Style.new(81, bold: true))
        theme.define("assistant", Style.new(252))
        theme.define("command", Style.new(214, bold: true))
        theme.define("activity", Style.new(244))
        theme.define("tool", Style.new(141))
      end

      def close_buffer(id : String, force : Bool = false) : Bool
        buffer = buffers.get(id)
        referenced = workspaces.all.any? { |workspace| workspace.panels.all.any? { |panel| panel.buffer_id == id } }
        return false if referenced
        return false if buffer.persistent && !force
        !!buffers.remove(id)
      end
    end
  end
end

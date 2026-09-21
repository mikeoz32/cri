module Cri
  module Tui
    class ActionContext
      getter ui : UiRuntime
      getter event : KeyEvent
      getter name : String

      def initialize(@ui : UiRuntime, @event : KeyEvent, @name : String)
      end

      def serialized : JSON::Any
        panel = ui.workspace.panels.focused
        buffer = panel.try { |item| ui.buffers.get(item.buffer_id).as?(TextBuffer) }
        JSON.parse({
          "action" => name,
          "event"  => {
            "token" => event.token,
            "value" => event.value,
          },
          "workspace" => {
            "id"     => ui.workspace.id,
            "status" => ui.workspace.status,
          },
          "focus" => {
            "panel_id"  => panel.try(&.id),
            "buffer_id" => panel.try(&.buffer_id),
            "mode"      => ui.mode.label,
            "cursor"    => buffer.try(&.cursor),
            "selection" => buffer.try(&.selection_range).try { |range| {"start" => range.begin, "end" => range.end} },
          },
        }.to_json)
      end
    end

    # Host-side action registry. Keymaps keep serializable action names; this
    # registry optionally attaches Crystal behavior to those names.
    class ActionRegistry
      alias Handler = Proc(ActionContext, Nil)

      def initialize
        @handlers = {} of String => Handler
      end

      def register(name : String, &handler : ActionContext -> Nil)
        validate_name(name)
        raise ArgumentError.new("action already registered: #{name}") if @handlers.has_key?(name)
        @handlers[name] = handler
      end

      def unregister(name : String)
        @handlers.delete(name)
      end

      def registered?(name : String) : Bool
        @handlers.has_key?(name)
      end

      def names : Array(String)
        @handlers.keys.sort
      end

      def dispatch(name : String, context : ActionContext) : Bool
        handler = @handlers[name]?
        return false unless handler
        handler.call(context)
        true
      end

      private def validate_name(name : String)
        raise ArgumentError.new("action name is empty") if name.empty?
        raise ArgumentError.new("action name must not contain whitespace") if name =~ /\s/
      end
    end
  end
end

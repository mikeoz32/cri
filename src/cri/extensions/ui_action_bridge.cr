module Cri
  module Extensions
    # Connects manifest-declared UI actions to the public TUI action registry.
    # The bridge passes only serializable context to WASM and gives the effect
    # handler a narrow UI sink; plugins never receive UiRuntime itself.
    class UiActionBridge
      def initialize(@ui : Tui::UiRuntime, @invoker : Invoker, @manifests : Array(Manifest))
      end

      def register_all : Array(String)
        registered = [] of String
        @manifests.each do |manifest|
          manifest.ui_actions.each do |action|
            action_id = action.name
            @ui.actions.register(action_id) do |context|
              response = @invoker.invoke(manifest, action.kind, action.name, context.serialized, @ui)
              unless response.ok
                @ui.set_activity("[error] #{response.error || "UI action failed"}\n", "activity")
              end
            end
            registered << action_id
          end
        end
        registered
      end
    end
  end
end

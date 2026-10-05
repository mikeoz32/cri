module Cri
  module Extensions
    class Invoker
      getter runtime : Wasm::Runtime
      getter grants : Permissions::GrantPolicy
      getter capabilities : API::CapabilityBroker
      getter workspace_root : String

      def initialize(@runtime : Wasm::Runtime = default_runtime, @grants : Permissions::GrantPolicy = Permissions::GrantPolicy.default, @capabilities : API::CapabilityBroker = API::CapabilityBroker.deny_all, @workspace_root : String = Dir.current)
      end

      def available? : Bool
        !runtime.is_a?(Wasm::UnimplementedRuntime)
      end

      def invoke(manifest : Manifest, kind : String, name : String, input : RawJSON, ui_sink : Effects::UiSink? = nil, provider_sink : Proc(JSON::Any, Nil)? = nil) : Wasm::ResponseEnvelope
        return failure("extension is disabled: #{manifest.name}") unless grants.enabled?(manifest.name)

        contribution = manifest.all_contributions.find { |item| item.kind == kind && item.name == name }
        return failure("contribution not declared: #{kind}:#{name}") unless contribution

        request = Wasm::RequestEnvelope.new(
          kind,
          name,
          input,
          Wasm::CallContext.new(tui: true)
        )
        handler = Effects::Handler.new(grants.for_extension(manifest.name), manifest.permissions, ui_sink: ui_sink, ui_owner: manifest.name, capabilities: capabilities, actor: manifest.name, provider_sink: provider_sink, workspace_root: workspace_root)
        runtime.run(manifest, request, handler)
      end

      def invoke(manifest : Manifest, kind : String, name : String, input : JSON::Any, ui_sink : Effects::UiSink? = nil, provider_sink : Proc(JSON::Any, Nil)? = nil) : Wasm::ResponseEnvelope
        invoke(manifest, kind, name, RawJSON.from_any(input), ui_sink, provider_sink)
      end

      private def default_runtime : Wasm::Runtime
        {% if flag?(:wasm3) || flag?(:Wasm3) %}
          Wasm::Wasm3Runtime.new
        {% else %}
          Wasm::UnimplementedRuntime.new
        {% end %}
      end

      private def failure(message : String) : Wasm::ResponseEnvelope
        Wasm::ResponseEnvelope.new(false, nil, [] of Effects::Effect, message)
      end
    end
  end
end

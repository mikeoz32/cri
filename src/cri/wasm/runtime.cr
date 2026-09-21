module Cri
  module Wasm
    abstract class Runtime
      abstract def call(manifest : Extensions::Manifest, request : RequestEnvelope) : ResponseEnvelope

      # A runtime may override this when it can keep a module alive across
      # effect responses. The fallback is deliberately conservative.
      def run(manifest : Extensions::Manifest, request : RequestEnvelope, handler : Effects::Handler) : ResponseEnvelope
        response = call(manifest, request)
        return response if response.effects.empty? || !response.ok
        ResponseEnvelope.new(false, nil, [] of JSON::Any, "runtime cannot resume after effects")
      end
    end

    class UnimplementedRuntime < Runtime
      def call(manifest : Extensions::Manifest, request : RequestEnvelope) : ResponseEnvelope
        ResponseEnvelope.new(false, nil, [] of JSON::Any, "WASM runtime is not wired yet for #{manifest.name}; request=#{request.kind}:#{request.name}")
      end
    end
  end
end

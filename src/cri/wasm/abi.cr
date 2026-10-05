module Cri
  module Wasm
    class CallContext
      include JSON::Serializable

      property session_id : String?
      property cwd : String
      property tui : Bool

      def initialize(@cwd : String = Dir.current, @session_id : String? = nil, @tui : Bool = false)
      end
    end

    class RequestEnvelope
      include JSON::Serializable

      property abi : String = Cri::ABI_VERSION
      property kind : String
      property name : String
      property input : RawJSON
      property context : CallContext

      def initialize(@kind : String, @name : String, @input : RawJSON, @context : CallContext = CallContext.new)
      end

      def initialize(kind : String, name : String, input : JSON::Any, context : CallContext = CallContext.new)
        initialize(kind, name, RawJSON.from_any(input), context)
      end
    end

    class ResponseEnvelope
      include JSON::Serializable

      property ok : Bool
      property result : RawJSON?
      property effects : Array(Effects::Effect)
      property error : String?

      def initialize(@ok : Bool, @result : RawJSON? = nil, @effects = [] of Effects::Effect, @error : String? = nil)
      end

      def initialize(ok : Bool, result : JSON::Any, effects = [] of JSON::Any, error : String? = nil)
        initialize(ok, RawJSON.from_any(result), effects.map { |effect| Effects::Effect.from_json(effect.to_json) }, error)
      end

      def initialize(ok : Bool, result : Nil, effects : Array(JSON::Any), error : String? = nil)
        initialize(ok, nil, effects.map { |effect| Effects::Effect.from_json(effect.to_json) }, error)
      end
    end
  end
end

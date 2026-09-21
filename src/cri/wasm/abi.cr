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
      property input : JSON::Any
      property context : CallContext

      def initialize(@kind : String, @name : String, @input : JSON::Any, @context : CallContext = CallContext.new)
      end
    end

    class ResponseEnvelope
      include JSON::Serializable

      property ok : Bool
      property result : JSON::Any?
      property effects : Array(JSON::Any)
      property error : String?

      def initialize(@ok : Bool, @result : JSON::Any? = nil, @effects = [] of JSON::Any, @error : String? = nil)
      end
    end
  end
end

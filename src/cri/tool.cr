module Cri
  alias ToolInput = RawJSON
  alias ToolOutput = RawJSON

  class ToolResult
    include JSON::Serializable

    property ok : Bool
    property result : RawJSON?
    property error : String?

    def initialize(@ok : Bool, @result : RawJSON? = nil, @error : String? = nil)
    end

    def initialize(ok : Bool, result : JSON::Any, error : String? = nil)
      initialize(ok, RawJSON.from_any(result), error)
    end
  end

  abstract class Tool
    getter name : String
    getter description : String

    def initialize(@name : String, @description : String)
    end

    abstract def call(input : RawJSON) : ToolResult

    def call(input : JSON::Any) : ToolResult
      call(RawJSON.from_any(input))
    end
  end

  class EchoTool < Tool
    def initialize
      super("builtin.echo", "Echo JSON input")
    end

    def call(input : RawJSON) : ToolResult
      ToolResult.new(true, input)
    end
  end
end

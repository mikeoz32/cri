module Cri
  alias ToolInput = JSON::Any
  alias ToolOutput = JSON::Any

  class ToolResult
    include JSON::Serializable

    property ok : Bool
    property result : JSON::Any?
    property error : String?

    def initialize(@ok : Bool, @result : JSON::Any? = nil, @error : String? = nil)
    end
  end

  abstract class Tool
    getter name : String
    getter description : String

    def initialize(@name : String, @description : String)
    end

    abstract def call(input : JSON::Any) : ToolResult
  end

  class EchoTool < Tool
    def initialize
      super("builtin.echo", "Echo JSON input")
    end

    def call(input : JSON::Any) : ToolResult
      ToolResult.new(true, input)
    end
  end
end

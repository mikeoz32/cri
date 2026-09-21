module Cri
  abstract class ToolExecutor
    abstract def names : Array(String)
    abstract def specs : Array(ToolSpec)
    abstract def call(name : String, input : JSON::Any) : ToolResult
  end

  class ToolRegistry < ToolExecutor
    getter tools = {} of String => Tool

    def initialize
    end

    def register(tool : Tool)
      @tools[tool.name] = tool
    end

    def register_builtins
      register(EchoTool.new)
    end

    def names : Array(String)
      @tools.keys.sort
    end

    def specs : Array(ToolSpec)
      tools.values.sort_by(&.name).map { |tool| ToolSpec.new(tool.name, tool.description) }
    end

    def call(name : String, input : JSON::Any) : ToolResult
      tool = @tools[name]?
      return ToolResult.new(false, nil, "unknown tool: #{name}") unless tool
      tool.call(input)
    rescue ex
      ToolResult.new(false, nil, ex.message || ex.class.name)
    end
  end
end

module Cri
  class ToolSpec
    getter name : String
    getter description : String

    def initialize(@name : String, @description : String)
    end

    def to_json_any : JSON::Any
      JSON.parse({
        "type" => "function",
        "function" => {
          "name" => name,
          "description" => description,
          "parameters" => {"type" => "object"},
        },
      }.to_json)
    end
  end

  class AssistantResponse
    getter content : String?
    getter tool_calls : Array(ToolCall)

    def initialize(@content : String?, @tool_calls : Array(ToolCall) = [] of ToolCall)
    end
  end

  abstract class Provider
    abstract def complete(messages : Array(Message), tools : Array(ToolSpec)) : AssistantResponse

    def complete_stream(messages : Array(Message), tools : Array(ToolSpec), &on_text : String -> Nil) : AssistantResponse
      response = complete(messages, tools)
      response.content.try { |content| on_text.call(content) }
      response
    end

    def supports_streaming? : Bool
      false
    end
  end
end

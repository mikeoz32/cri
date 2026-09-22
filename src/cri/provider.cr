module Cri
  class ToolSpec
    getter name : String
    getter description : String

    def initialize(@name : String, @description : String)
    end

    def to_json_any : JSON::Any
      JSON.parse({
        "type"     => "function",
        "function" => {
          "name"        => name,
          "description" => description,
          "parameters"  => {"type" => "object"},
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

  # Generic provider runtime. Provider identity/configuration comes from the
  # registration; wire semantics come from the selected APIClient.
  class Provider
    getter registration : ProviderRegistration?
    getter client : APIClient?

    # The no-argument initializer keeps the public Provider seam usable for
    # custom/native implementations that override complete.
    def initialize
      @registration = nil
      @client = nil
    end

    def initialize(@registration : ProviderRegistration, @client : APIClient)
    end

    def complete(messages : Array(Message), tools : Array(ToolSpec)) : AssistantResponse
      client.not_nil!.complete(messages, tools)
    end

    def complete_stream(messages : Array(Message), tools : Array(ToolSpec), &on_text : String -> Nil) : AssistantResponse
      response = complete(messages, tools)
      response.content.try { |content| on_text.call(content) }
      response
    end

    def supports_streaming? : Bool
      client.try(&.supports_streaming?) || false
    end
  end

  # API clients implement wire-level API semantics. They are not providers:
  # provider registrations supply identity/configuration and wrap one client.
  abstract class APIClient
    abstract def complete(messages : Array(Message), tools : Array(ToolSpec)) : AssistantResponse

    def complete_stream(messages : Array(Message), tools : Array(ToolSpec), &on_text : String -> Nil) : AssistantResponse
      response = complete(messages, tools)
      response.content.try { |content| on_text.call(content) }
      response
    end

    def supports_streaming? : Bool
      false
    end

    def validate_credentials : Nil
    end
  end
end

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

  class ModelSettings
    getter reasoning_effort : String?
    getter temperature : Float64?
    getter max_output_tokens : Int64?

    def initialize(
      @reasoning_effort : String? = nil,
      @temperature : Float64? = nil,
      @max_output_tokens : Int64? = nil,
    )
    end

    def empty? : Bool
      !reasoning_effort && !temperature && !max_output_tokens
    end

    def to_json_any : JSON::Any
      values = {} of String => JSON::Any
      values["reasoning_effort"] = JSON::Any.new(reasoning_effort) if reasoning_effort
      values["temperature"] = JSON::Any.new(temperature) if temperature
      values["max_output_tokens"] = JSON::Any.new(max_output_tokens) if max_output_tokens
      JSON::Any.new(values)
    end

    def self.from_json(value : JSON::Any) : ModelSettings
      new(
        value["reasoning_effort"]?.try(&.as_s?),
        value["temperature"]?.try(&.as_f?),
        value["max_output_tokens"]?.try(&.as_i64?)
      )
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

    def complete(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings) : AssistantResponse
      return complete(messages, tools) if settings.empty?
      client.not_nil!.complete(messages, tools, settings)
    end

    def complete_stream(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings = ModelSettings.new, &on_text : String -> Nil) : AssistantResponse
      if client = @client
        if client.supports_streaming?
          chunks = Channel(String).new
          done = Channel(AssistantResponse | Exception).new
          spawn do
            begin
              done.send(client.stream_with_channel(messages, tools, settings, chunks))
            rescue ex
              done.send(ex)
            end
          end
          loop do
            select
            when chunk = chunks.receive
              on_text.call(chunk)
            when result = done.receive
              raise result if result.is_a?(Exception)
              return result
            end
          end
        end
      end
      response = complete(messages, tools, settings)
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
    @stream_channel : Channel(String)?

    def complete(messages : Array(Message), tools : Array(ToolSpec)) : AssistantResponse
      complete(messages, tools, ModelSettings.new)
    end

    abstract def complete(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings) : AssistantResponse

    def complete_stream(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings = ModelSettings.new, &on_text : String -> Nil) : AssistantResponse
      chunks = Channel(String).new
      done = Channel(AssistantResponse | Exception).new
      spawn do
        begin
          done.send(stream_with_channel(messages, tools, settings, chunks))
        rescue ex
          done.send(ex)
        end
      end
      loop do
        select
        when chunk = chunks.receive
          on_text.call(chunk)
        when result = done.receive
          raise result if result.is_a?(Exception)
          return result
        end
      end
    end

    def stream_with_channel(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings, channel : Channel(String)) : AssistantResponse
      @stream_channel = channel
      begin
        complete_stream_internal(messages, tools, settings)
      ensure
        @stream_channel = nil
      end
    end

    protected def complete_stream_internal(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings) : AssistantResponse
      response = complete(messages, tools, settings)
      response.content.try { |content| emit_stream_text(content) }
      response
    end

    protected def emit_stream_text(text : String) : Nil
      @stream_channel.try(&.send(text))
      nil
    end

    def supports_streaming? : Bool
      false
    end

    def validate_credentials : Nil
    end

    def list_models : Array(String)
      [] of String
    end
  end
end

module Cri
  module APIClients
    class ChatCompletionsRequest
      include JSON::Serializable

      property model : String
      property messages : Array(Message)
      property stream : Bool

      @[JSON::Field(ignore_serialize: tools.empty?)]
      property tools : Array(ToolSpec) = [] of ToolSpec

      property reasoning_effort : String?
      property temperature : Float64?

      @[JSON::Field(key: "max_tokens")]
      property max_output_tokens : Int64?

      def initialize(
        @model : String,
        @messages : Array(Message),
        @stream : Bool,
        @tools : Array(ToolSpec) = [] of ToolSpec,
        @reasoning_effort : String? = nil,
        @temperature : Float64? = nil,
        @max_output_tokens : Int64? = nil,
      )
      end
    end

    # OpenAI-compatible API client. Provider identity/configuration lives in
    # ProviderRegistration and ProviderRuntime.
    class OpenAICompatible < APIClient
      getter client : OpenAICompatibleHTTP
      getter model : String

      def initialize(
        endpoint : String = ENV["CRI_MODEL_URL"]? || "https://api.openai.com/v1/chat/completions",
        @model : String = ENV["CRI_MODEL"]? || "gpt-4o-mini",
        api_key : String? = ENV["CRI_API_KEY"]?,
        timeout : Time::Span = 120.seconds,
        transport : Cri::Transport = Cri::Transports::SSE.new,
      )
        @client = OpenAICompatibleHTTP.new(endpoint, api_key, timeout, transport)
      end

      def complete(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings = ModelSettings.new) : AssistantResponse
        parse_response(client.chat(payload(messages, tools, settings, false)))
      end

      def supports_streaming? : Bool
        true
      end

      def validate_credentials : Nil
        client.validate_api_key
      end

      def list_models : Array(String)
        client.list_models
      end

      protected def complete_stream_internal(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings) : AssistantResponse
        tool_call_parts = {} of Int32 => NamedTuple(id: String, name: String, arguments: String)
        content = String.build do |output|
          client.chat_stream(payload(messages, tools, settings, true)) do |chunk|
            choice = chunk.choices.first?
            next unless choice
            delta = choice.delta
            text = delta.content
            if text
              output << text
              emit_stream_text(text)
            end

            delta.tool_calls.each do |raw_call|
              index = raw_call.index
              previous = tool_call_parts[index]?
              function = raw_call.function
              id = raw_call.id || previous.try(&.[:id]) || "stream-call-#{index}"
              name = function.try(&.name) || previous.try(&.[:name]) || ""
              arguments = function.try(&.arguments) || ""
              if previous
                arguments = previous[:arguments] + arguments
              end
              tool_call_parts[index] = {id: id, name: name, arguments: arguments}
            end
          end
        end

        calls = tool_call_parts.keys.sort.map do |index|
          part = tool_call_parts[index]
          ToolCall.new(part[:id], part[:name], RawJSON.new(part[:arguments]))
        end
        AssistantResponse.new(content.empty? ? nil : content, calls)
      rescue JSON::ParseException | JSON::SerializableError
        raise "invalid streamed OpenAI tool call arguments"
      end

      private def payload(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings, stream : Bool) : String
        ChatCompletionsRequest.new(
          model,
          messages,
          stream,
          tools,
          settings.reasoning_effort,
          settings.temperature,
          settings.max_output_tokens
        ).to_json
      end

      private def parse_response(root : ChatCompletionResponse) : AssistantResponse
        message = root.choices.first?.try(&.message) || raise "invalid OpenAI response: missing choices"
        calls = message.tool_calls.map do |raw_call|
          ToolCall.new(raw_call.id, raw_call.function.name, RawJSON.new(raw_call.function.arguments))
        end
        AssistantResponse.new(message.content, calls)
      rescue ex : JSON::ParseException | JSON::SerializableError
        raise "invalid OpenAI response: #{ex.message}"
      end
    end
  end
end

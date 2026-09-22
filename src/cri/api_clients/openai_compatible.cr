module Cri
  module APIClients
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
            choice = chunk["choices"]?.try(&.as_a.first?)
            next unless choice
            delta = choice["delta"]
            text = delta["content"]?.try(&.as_s?)
            if text
              output << text
              emit_stream_text(text)
            end

            delta["tool_calls"]?.try do |raw_calls|
              raw_calls.as_a.each do |raw_call|
                index = raw_call["index"]?.try(&.as_i) || 0
                previous = tool_call_parts[index]?
                function = raw_call["function"]?
                id = raw_call["id"]?.try(&.as_s) || previous.try(&.[:id]) || "stream-call-#{index}"
                name = function.try { |value| value["name"]?.try(&.as_s) } || previous.try(&.[:name]) || ""
                arguments = function.try { |value| value["arguments"]?.try(&.as_s) } || ""
                if previous
                  arguments = previous[:arguments] + arguments
                end
                tool_call_parts[index] = {id: id, name: name, arguments: arguments}
              end
            end
          end
        end

        calls = tool_call_parts.keys.sort.map do |index|
          part = tool_call_parts[index]
          arguments = JSON.parse(part[:arguments])
          ToolCall.new(part[:id], part[:name], arguments)
        end
        AssistantResponse.new(content.empty? ? nil : content, calls)
      rescue JSON::ParseException
        raise "invalid streamed OpenAI tool call arguments"
      end

      private def payload(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings, stream : Bool) : JSON::Any
        body = JSON.parse({
          "model"    => model,
          "messages" => messages.map(&.to_api_json),
          "stream"   => stream,
        }.to_json).as_h
        body["tools"] = JSON::Any.new(tools.map(&.to_json_any)) unless tools.empty?
        settings.reasoning_effort.try { |effort| body["reasoning_effort"] = JSON::Any.new(effort) }
        settings.temperature.try { |temperature| body["temperature"] = JSON::Any.new(temperature) }
        settings.max_output_tokens.try { |limit| body["max_tokens"] = JSON::Any.new(limit) }
        JSON::Any.new(body)
      end

      private def parse_response(root : JSON::Any) : AssistantResponse
        message = root["choices"][0]["message"]
        content = message["content"]?.try(&.as_s?)
        calls = [] of ToolCall

        message["tool_calls"]?.try do |tool_calls|
          tool_calls.as_a.each do |raw_call|
            function = raw_call["function"]
            arguments = JSON.parse(function["arguments"].as_s)
            calls << ToolCall.new(raw_call["id"].as_s, function["name"].as_s, arguments)
          end
        end

        AssistantResponse.new(content, calls)
      rescue ex : JSON::ParseException
        raise "invalid OpenAI response: #{ex.message}"
      end
    end
  end
end

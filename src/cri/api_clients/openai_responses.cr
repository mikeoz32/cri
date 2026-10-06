require "json"

module Cri
  module APIClients
    class ResponsesAnnotation
      include JSON::Serializable

      property type : String = ""
      property url : String? = nil
      property title : String? = nil
    end

    class ResponsesContentPart
      include JSON::Serializable

      property type : String = ""
      property text : String? = nil
      property annotations : Array(ResponsesAnnotation) = [] of ResponsesAnnotation
    end

    class ResponsesOutputItem
      include JSON::Serializable

      property type : String = ""
      property call_id : String? = nil
      property id : String? = nil
      property name : String? = nil
      property arguments : String? = nil
      property content : Array(ResponsesContentPart) = [] of ResponsesContentPart
    end

    class ResponsesResult
      include JSON::Serializable

      property output : Array(ResponsesOutputItem) = [] of ResponsesOutputItem
    end

    class ResponsesStreamEvent
      include JSON::Serializable

      property type : String = ""
      property delta : String? = nil
      property item : ResponsesOutputItem? = nil
    end

    # OpenAI's first-party Responses API client. OpenAI decides when the
    # native web_search tool is useful and whether to invoke it.
    class OpenAIResponses < APIClient
      getter endpoint : URI
      getter model : String
      getter api_key : String?
      getter transport : Transport

      def initialize(
        endpoint : String = ENV["CRI_MODEL_URL"]? || "https://api.openai.com/v1/responses",
        @model : String = ENV["CRI_MODEL"]? || "gpt-4o-mini",
        @api_key : String? = ENV["CRI_API_KEY"]?,
        @transport : Transport = Transports::SSE.new,
      )
        @endpoint = URI.parse(endpoint.sub(/\/chat\/completions\z/, "/responses"))
      end

      def complete(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings = ModelSettings.new) : AssistantResponse
        response = transport.request("POST", endpoint, headers, request_body(messages, tools, settings, false))
        raise "OpenAI Responses API error (#{response.status}): #{response.body}" unless response.status.in?(200...300)
        parse_response(ResponsesResult.from_json(response.body), tools)
      end

      protected def complete_stream_internal(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings) : AssistantResponse
        content = String::Builder.new
        tool_calls = [] of ToolCall
        citations = {} of String => String
        names = tool_name_map(tools)
        response = transport.stream(endpoint, headers(true), request_body(messages, tools, settings, true)) do |data|
          handle_stream_event(data, content, tool_calls, citations, names)
        end
        raise "OpenAI Responses API error (#{response.status}): #{response.body}" unless response.status.in?(200...300)
        text = with_sources(content.to_s, citations)
        AssistantResponse.new(text.empty? ? nil : text, tool_calls)
      rescue ex : JSON::ParseException | JSON::SerializableError
        raise "invalid OpenAI Responses stream JSON: #{ex.message}"
      end

      def supports_streaming? : Bool
        true
      end

      def validate_credentials : Nil
        response = transport.request("GET", models_endpoint, headers, nil)
        raise "OpenAI API key validation failed (#{response.status}): #{response.body}" unless response.status.in?(200...300)
      end

      def list_models : Array(String)
        response = transport.request("GET", models_endpoint, headers, nil)
        raise "OpenAI model discovery failed (#{response.status}): #{response.body}" unless response.status.in?(200...300)
        ModelListResponse.from_json(response.body).data.compact_map(&.id)
      end

      private def models_endpoint : URI
        URI.parse(endpoint.to_s.sub(/\/responses\z/, "/models"))
      end

      private def headers(stream : Bool = false) : HTTP::Headers
        result = HTTP::Headers{
          "Accept"       => (stream ? "text/event-stream" : "application/json"),
          "Content-Type" => "application/json",
        }
        result["Authorization"] = "Bearer #{api_key}" if api_key
        result
      end

      private def request_body(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings, stream : Bool) : String
        String.build do |json|
          JSON.build(json) do |builder|
            builder.object do
              builder.field "model", model
              builder.field "input" do
                builder.array { messages.each { |message| write_input_message(builder, message) } }
              end
              builder.field "stream", stream
              builder.field "store", false
              builder.field "tools" do
                builder.array do
                  builder.object { builder.field "type", "web_search" }
                  tools.each do |tool|
                    builder.object do
                      builder.field "type", "function"
                      builder.field "name", responses_tool_name(tool.name)
                      builder.field "description", tool.description
                      builder.field "parameters" do
                        builder.object { builder.field "type", "object" }
                      end
                    end
                  end
                end
              end
              settings.reasoning_effort.try do |effort|
                builder.field "reasoning" { builder.object { builder.field "effort", effort } }
              end
              settings.temperature.try { |temperature| builder.field "temperature", temperature }
              settings.max_output_tokens.try { |limit| builder.field "max_output_tokens", limit }
            end
          end
        end
      end

      private def write_input_message(builder : JSON::Builder, message : Message) : Nil
        if message.role == "tool"
          builder.object do
            builder.field "type", "function_call_output"
            builder.field "call_id", message.tool_call_id || ""
            builder.field "output", message.content || ""
          end
        elsif message.role == "assistant" && !message.tool_calls.empty?
          if content = message.content
            builder.object do
              builder.field "role", "assistant"
              builder.field "content", content
            end
          end
          message.tool_calls.each do |call|
            builder.object do
              builder.field "type", "function_call"
              builder.field "call_id", call.id
              builder.field "name", responses_tool_name(call.name)
              builder.field "arguments", call.arguments.raw
            end
          end
        else
          message.to_json(builder)
        end
        nil
      end

      private def parse_response(response : ResponsesResult, tools : Array(ToolSpec)) : AssistantResponse
        content = String::Builder.new
        tool_calls = [] of ToolCall
        citations = {} of String => String
        names = tool_name_map(tools)
        response.output.each { |item| collect_item(item, content, tool_calls, citations, names, true) }
        text = with_sources(content.to_s, citations)
        AssistantResponse.new(text.empty? ? nil : text, tool_calls)
      end

      private def handle_stream_event(data : String, content : String::Builder, tool_calls : Array(ToolCall), citations : Hash(String, String), names : Hash(String, String)) : Nil
        return if data == "[DONE]"
        event = ResponsesStreamEvent.from_json(data)
        if event.type == "response.output_text.delta"
          delta = event.delta || ""
          content << delta
          emit_stream_text(delta)
        elsif event.type == "response.output_item.done"
          if item = event.item
            collect_item(item, content, tool_calls, citations, names, false)
          end
        end
        nil
      end

      private def collect_item(item : ResponsesOutputItem, content : String::Builder, tool_calls : Array(ToolCall), citations : Hash(String, String), names : Hash(String, String), include_text : Bool) : Nil
        if item.type == "function_call"
          if id = item.call_id || item.id
            if name = item.name
              tool_calls << ToolCall.new(id, names[name]? || name, RawJSON.new(item.arguments || "{}"))
            end
          end
        elsif item.type == "message"
          item.content.each do |part|
            next unless part.type == "output_text"
            content << (part.text || "") if include_text
            part.annotations.each do |citation|
              if citation.type == "url_citation"
                if url = citation.url
                  citations[url] = citation.title || url
                end
              end
            end
          end
        end
        nil
      end

      private def tool_name_map(tools : Array(ToolSpec)) : Hash(String, String)
        tools.to_h { |tool| {responses_tool_name(tool.name), tool.name} }
      end

      private def responses_tool_name(name : String) : String
        name.gsub(/[^a-zA-Z0-9_-]/, "_")
      end

      private def with_sources(text : String, citations : Hash(String, String)) : String
        return text if citations.empty?
        String.build do |result|
          result << text
          result << "\n\nSources:\n"
          citations.each { |url, title| result << "- [#{title}](#{url})\n" }
        end
      end
    end
  end
end

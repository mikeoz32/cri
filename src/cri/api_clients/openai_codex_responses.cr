require "base64"
require "json"
require "random/secure"

module Cri
  module APIClients
    class OpenAICodexResponses < APIClient
      getter endpoint : URI
      getter model : String
      getter transport : Transport
      @access_token : String
      @account_id : String

      def initialize(
        endpoint : String,
        @model : String,
        credential : String?,
        @transport : Transport = Transports::SSE.new,
      )
        @endpoint = URI.parse(endpoint)
        @access_token, @account_id = parse_credential(credential)
      end

      def list_models : Array(String)
        models_endpoint = URI.parse(endpoint.to_s.sub(/\/backend-api\/codex\/responses\z/, "/backend-api/codex/models?client_version=1.0.0"))
        response = transport.request("GET", models_endpoint, headers, nil)
        raise "ChatGPT model discovery failed (#{response.status})" unless response.status.in?(200...300)
        JSON.parse(response.body)["models"].as_a.compact_map do |entry|
          next if entry["visibility"]?.try(&.as_s?) == "hide"
          entry["slug"]?.try(&.as_s?)
        end
      end

      def complete(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings = ModelSettings.new) : AssistantResponse
        # Codex Responses requires streaming even for callers that request a
        # collected response. Read the SSE body to completion here.
        response = transport.request("POST", endpoint, headers, request_body(messages, tools, settings, true))
        raise "Codex API error (#{response.status}): #{response.body}" unless response.status.in?(200...300)
        content = String::Builder.new
        tool_calls = [] of ToolCall
        tool_names = tool_name_map(tools)
        response.body.each_line do |line|
          data = line.strip
          if data.starts_with?("data: ")
            data = data[6..]
            unless data == "[DONE]"
              event = JSON.parse(data)
              case event["type"]?.try(&.as_s?)
              when "response.output_text.delta"
                content << (event["delta"]?.try(&.as_s?) || "")
              when "response.output_item.done", "response.function_call_arguments.done"
                item = event["item"]? || event
                if call = parse_tool_call(item, tool_names)
                  tool_calls << call unless tool_calls.any? { |existing| existing.id == call.id }
                end
              end
            end
          end
        end
        text = content.to_s
        return parse_response(JSON.parse(response.body), tool_names) if text.empty? && response.body.lstrip.starts_with?("{")
        AssistantResponse.new(text.empty? ? nil : text, tool_calls)
      end

      def complete_stream(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings = ModelSettings.new, &on_text : String -> Nil) : AssistantResponse
        content = String::Builder.new
        tool_calls = [] of ToolCall
        tool_names = tool_name_map(tools)
        response = transport.stream(endpoint, headers, request_body(messages, tools, settings, true)) do |data|
          unless data == "[DONE]"
            event = JSON.parse(data)
            case event["type"]?.try(&.as_s?)
            when "response.output_text.delta"
              delta = event["delta"]?.try(&.as_s?) || ""
              content << delta
              on_text.call(delta)
            when "response.output_item.done", "response.function_call_arguments.done"
              item = event["item"]? || event
              if call = parse_tool_call(item, tool_names)
                tool_calls << call unless tool_calls.any? { |existing| existing.id == call.id }
              end
            end
          end
        end
        raise "Codex API error (#{response.status}): #{response.body}" unless response.status.in?(200...300)
        AssistantResponse.new(content.to_s.empty? ? nil : content.to_s, tool_calls)
      end

      def supports_streaming? : Bool
        true
      end

      private def headers : HTTP::Headers
        HTTP::Headers{
          "Authorization"      => "Bearer #{@access_token}",
          "chatgpt-account-id" => @account_id,
          "originator"         => "cri",
          "OpenAI-Beta"        => "responses=experimental",
          "Accept"             => "text/event-stream",
          "Content-Type"       => "application/json",
          "User-Agent"         => "cri",
        }
      end

      private def request_body(messages : Array(Message), tools : Array(ToolSpec), settings : ModelSettings, stream : Bool) : String
        body = JSON.parse({
          "model"  => model,
          "input"  => codex_input(messages),
          "stream" => stream,
          "store"  => false,
        }.to_json).as_h
        settings.reasoning_effort.try do |effort|
          body["reasoning"] = JSON.parse({"effort" => effort}.to_json)
        end
        settings.temperature.try { |temperature| body["temperature"] = JSON::Any.new(temperature) }
        settings.max_output_tokens.try { |limit| body["max_output_tokens"] = JSON::Any.new(limit) }
        unless tools.empty?
          body["tools"] = JSON::Any.new(tools.map do |tool|
            function = tool.to_json_any["function"]
            JSON.parse({
              "type"        => "function",
              "name"        => codex_tool_name(function["name"].as_s),
              "description" => function["description"],
              "parameters"  => function["parameters"],
            }.to_json)
          end)
        end
        body.to_json
      end

      private def codex_input(messages : Array(Message)) : Array(JSON::Any)
        messages.flat_map do |message|
          if message.role == "tool"
            [JSON.parse({
              "type"    => "function_call_output",
              "call_id" => message.tool_call_id || "",
              "output"  => message.content || "",
            }.to_json)]
          elsif message.role == "assistant" && !message.tool_calls.empty?
            items = [] of JSON::Any
            if content = message.content
              items << JSON.parse({"role" => "assistant", "content" => content}.to_json)
            end
            message.tool_calls.each do |call|
              items << JSON.parse({
                "type"      => "function_call",
                "call_id"   => call.id,
                "name"      => codex_tool_name(call.name),
                "arguments" => call.arguments.to_json,
              }.to_json)
            end
            items
          else
            [message.to_api_json]
          end
        end
      end

      private def tool_name_map(tools : Array(ToolSpec)) : Hash(String, String)
        tools.to_h { |tool| {codex_tool_name(tool.name), tool.name} }
      end

      private def codex_tool_name(name : String) : String
        name.gsub(/[^a-zA-Z0-9_-]/, "_")
      end

      private def parse_tool_call(item : JSON::Any, names : Hash(String, String)) : ToolCall?
        return nil unless item["type"]?.try(&.as_s?) == "function_call" || (item["name"]? && item["arguments"]?)
        name = item["name"]?.try(&.as_s?) || return nil
        id = item["call_id"]?.try(&.as_s?) || item["id"]?.try(&.as_s?) || return nil
        raw_arguments = item["arguments"]?.try(&.as_s?) || "{}"
        arguments = begin
          JSON.parse(raw_arguments)
        rescue JSON::ParseException
          JSON.parse("{}")
        end
        ToolCall.new(id, names[name]? || name, arguments)
      end

      private def parse_response(json : JSON::Any, names : Hash(String, String) = {} of String => String) : AssistantResponse
        output = json["output"]?.try(&.as_a) || [] of JSON::Any
        tool_calls = [] of ToolCall
        text = String.build do |result|
          output.each do |item|
            if item["type"]?.try(&.as_s?) == "function_call"
              if call = parse_tool_call(item, names)
                tool_calls << call
              end
            elsif item["type"]?.try(&.as_s?) == "message"
              if content = item["content"]?.try(&.as_a)
                content.each do |part|
                  result << part["text"].as_s if part["type"]?.try(&.as_s?) == "output_text"
                end
              end
            end
          end
        end
        AssistantResponse.new(text.empty? ? nil : text, tool_calls)
      end

      private def parse_credential(credential : String?) : {String, String}
        raise "ChatGPT credential is not configured" unless credential
        json = JSON.parse(credential)
        access = json["access_token"]?.try(&.as_s) || raise "ChatGPT credential omitted access_token"
        id_token = json["id_token"]?.try(&.as_s?)
        account = json["account_id"]?.try(&.as_s?) || id_token.try { |token| account_id_from_jwt(token) } || account_id_from_jwt(access) || raise "ChatGPT credential omitted account id"
        {access, account}
      rescue JSON::ParseException
        raise "ChatGPT credential has invalid token data"
      end

      private def account_id_from_jwt(token : String) : String?
        parts = token.split('.')
        return nil unless parts.size >= 2
        payload = Base64.decode_string(parts[1] + ("=" * ((4 - parts[1].size % 4) % 4)))
        json = JSON.parse(payload)
        json["https://api.openai.com/auth"]?.try(&.as_h).try { |claims| claims["chatgpt_account_id"]?.try(&.as_s?) } ||
          json["chatgpt_account_id"]?.try(&.as_s?)
      rescue
        nil
      end
    end
  end
end

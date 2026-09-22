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

      def complete(messages : Array(Message), tools : Array(ToolSpec)) : AssistantResponse
        # Codex Responses requires streaming even for callers that request a
        # collected response. Read the SSE body to completion here.
        response = transport.request("POST", endpoint, headers, request_body(messages, tools, true))
        raise "Codex API error (#{response.status}): #{response.body}" unless response.status.in?(200...300)
        content = String::Builder.new
        response.body.each_line do |line|
          data = line.strip
          if data.starts_with?("data: ")
            data = data[6..]
            unless data == "[DONE]"
              event = JSON.parse(data)
              if event["type"]?.try(&.as_s?) == "response.output_text.delta"
                content << (event["delta"]?.try(&.as_s?) || "")
              end
            end
          end
        end
        text = content.to_s
        return parse_response(JSON.parse(response.body)) if text.empty? && response.body.lstrip.starts_with?("{")
        AssistantResponse.new(text.empty? ? nil : text)
      end

      def complete_stream(messages : Array(Message), tools : Array(ToolSpec), &on_text : String -> Nil) : AssistantResponse
        content = String::Builder.new
        response = transport.stream(endpoint, headers, request_body(messages, tools, true)) do |data|
          unless data == "[DONE]"
            event = JSON.parse(data)
            if event["type"]?.try(&.as_s?) == "response.output_text.delta"
              delta = event["delta"]?.try(&.as_s?) || ""
              content << delta
              on_text.call(delta)
            end
          end
        end
        raise "Codex API error (#{response.status}): #{response.body}" unless response.status.in?(200...300)
        AssistantResponse.new(content.to_s.empty? ? nil : content.to_s)
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

      private def request_body(messages : Array(Message), tools : Array(ToolSpec), stream : Bool) : String
        {
          "model"  => model,
          "input"  => messages.map(&.to_api_json),
          "stream" => stream,
          "store"  => false,
          "tools"  => tools.map { |tool| tool.to_json_any["function"] },
        }.to_json
      end

      private def parse_response(json : JSON::Any) : AssistantResponse
        output = json["output"]?.try(&.as_a) || [] of JSON::Any
        text = String.build do |result|
          output.each do |item|
            next unless item["type"]?.try(&.as_s?) == "message"
            if content = item["content"]?.try(&.as_a)
              content.each do |part|
                result << part["text"].as_s if part["type"]?.try(&.as_s?) == "output_text"
              end
            end
          end
        end
        AssistantResponse.new(text.empty? ? nil : text)
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

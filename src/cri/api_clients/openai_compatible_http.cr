module Cri
  module APIClients
    # OpenAI-compatible HTTP/SSE wire client. The enclosing provider,
    # credentials, and provider identity are supplied by the host registry.
    # It intentionally exposes raw JSON so provider adapters own semantics.
    class OpenAICompatibleHTTP
      getter endpoint : URI
      getter api_key : String?
      getter timeout : Time::Span
      getter transport : Cri::Transport

      def initialize(
        endpoint : String = ENV["CRI_MODEL_URL"]? || "https://api.openai.com/v1/chat/completions",
        @api_key : String? = ENV["CRI_API_KEY"]?,
        @timeout : Time::Span = 120.seconds,
        @transport : Cri::Transport = Cri::Transports::SSE.new,
      )
        @endpoint = URI.parse(endpoint)
      end

      def chat(payload : JSON::Any) : JSON::Any
        response = request(payload.to_json)
        JSON.parse(response)
      end

      def validate_api_key : Nil
        list_models
      end

      def list_models : Array(String)
        validation_endpoint = URI.parse(endpoint.to_s.sub(/\/chat\/completions\z/, "/models"))
        response = transport.request("GET", validation_endpoint, authorization_headers, nil)
        raise ApiError.new(response.status, response.body) unless response.status.in?(200...300)
        JSON.parse(response.body)["data"].as_a.compact_map do |entry|
          entry["id"]?.try(&.as_s?)
        end
      end

      def chat_stream(payload : JSON::Any, &block : JSON::Any -> Nil) : Nil
        payload_hash = payload.as_h
        payload_hash["stream"] = JSON::Any.new(true)
        completed = false
        stream_request(payload_hash.to_json) do |line|
          data = line
          next if data.empty?
          if data == "[DONE]"
            completed = true
            next
          end
          next if completed
          begin
            block.call(JSON.parse(data))
          rescue ex : JSON::ParseException
            raise StreamError.new("invalid OpenAI SSE JSON: #{ex.message}")
          end
        end
        raise StreamError.new("OpenAI SSE stream ended before [DONE]") unless completed
      end

      private def request(body : String) : String
        response = transport.request("POST", endpoint, request_headers, body)
        raise ApiError.new(response.status, response.body) unless response.status.in?(200...300)
        response.body
      end

      private def stream_request(body : String, &block : String -> Nil)
        response = transport.stream(endpoint, request_headers, body) { |data| block.call(data) }
        raise ApiError.new(response.status, response.body) unless response.status.in?(200...300)
      end

      private def authorization_headers : HTTP::Headers
        headers = HTTP::Headers{"Accept" => "application/json"}
        headers["Authorization"] = "Bearer #{@api_key}" if @api_key
        headers
      end

      private def request_headers : HTTP::Headers
        headers = authorization_headers
        headers["Content-Type"] = "application/json"
        headers["Accept"] = "text/event-stream"
        headers
      end
    end

    class ApiError < Exception
      getter status : Int32
      getter body : String

      def initialize(@status : Int32, @body : String)
        detail = body.strip
        detail = "API key rejected; use an OpenAI Platform API key, not a ChatGPT/Codex token" if status == 401
        super("OpenAI API error (#{status}): #{detail}")
      end
    end

    class StreamError < Exception
      def initialize(message : String)
        super(message)
      end
    end
  end
end

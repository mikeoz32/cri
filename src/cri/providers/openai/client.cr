module Cri
  module Providers
    module OpenAIAPI
      # Small local transport extracted from the Ametist OpenAI client.
      # It intentionally exposes raw JSON so provider adapters own semantics.
      class Client
        getter endpoint : URI
        getter api_key : String?
        getter timeout : Time::Span

        def initialize(
          endpoint : String = ENV["CRI_MODEL_URL"]? || "https://api.openai.com/v1/chat/completions",
          @api_key : String? = ENV["CRI_API_KEY"]?,
          @timeout : Time::Span = 120.seconds,
        )
          @endpoint = URI.parse(endpoint)
        end

        def chat(payload : JSON::Any) : JSON::Any
          response = request(payload.to_json)
          JSON.parse(response)
        end

        def validate_api_key : Nil
          validation_endpoint = URI.parse(endpoint.to_s.sub(/\/chat\/completions\z/, "/models"))
          client = HTTP::Client.new(validation_endpoint)
          client.connect_timeout = timeout
          client.read_timeout = timeout
          response = client.get(validation_endpoint.request_target, headers: authorization_headers)
          raise ApiError.new(response.status_code, response.body) unless response.success?
        ensure
          client.try(&.close)
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
              yield JSON.parse(data)
            rescue ex : JSON::ParseException
              raise StreamError.new("invalid OpenAI SSE JSON: #{ex.message}")
            end
          end
          raise StreamError.new("OpenAI SSE stream ended before [DONE]") unless completed
        end

        private def request(body : String) : String
          client = HTTP::Client.new(endpoint)
          client.connect_timeout = timeout
          client.read_timeout = timeout
          headers = request_headers
          response = client.post(endpoint.request_target, headers: headers, body: body)
          raise ApiError.new(response.status_code, response.body) unless response.success?
          response.body
        ensure
          client.try(&.close)
        end

        private def stream_request(body : String, &block : String -> Nil)
          client = HTTP::Client.new(endpoint)
          client.connect_timeout = timeout
          client.read_timeout = timeout
          request = HTTP::Request.new("POST", endpoint.request_target, request_headers, body: body)
          client.exec(request) do |response|
            raise ApiError.new(response.status_code, response.body) unless response.success?

            response.body_io.each_line do |line|
              next unless line.starts_with?("data:")
              yield line[5..-1].strip
            end
          end
        ensure
          client.try(&.close)
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
          super("OpenAI API error (#{status}): #{body}")
        end
      end

      class StreamError < Exception
        def initialize(message : String)
          super(message)
        end
      end
    end
  end
end

require "http/client"

module Cri
  abstract class Transport
    record Response, status : Int32, body : String

    abstract def request(method : String, endpoint : URI, headers : ::HTTP::Headers, body : String?) : Response

    def stream(endpoint : URI, headers : ::HTTP::Headers, body : String, &on_data : String -> Nil) : Response
      raise "transport does not support streaming"
    end
  end

  module Transports
    class HTTP < Cri::Transport
      getter timeout : Time::Span

      def initialize(@timeout : Time::Span = 120.seconds)
      end

      def request(method : String, endpoint : URI, headers : ::HTTP::Headers, body : String? = nil) : Response
        client = ::HTTP::Client.new(endpoint)
        client.connect_timeout = timeout
        client.read_timeout = timeout
        response = client.exec(method, endpoint.request_target, headers: headers, body: body)
        Response.new(response.status_code, response.body)
      ensure
        client.try(&.close)
      end
    end

    class SSE < HTTP
      def stream(endpoint : URI, headers : ::HTTP::Headers, body : String, &on_data : String -> Nil) : Response
        client = ::HTTP::Client.new(endpoint)
        client.connect_timeout = timeout
        client.read_timeout = timeout
        request = ::HTTP::Request.new("POST", endpoint.request_target, headers, body: body)
        status = 0
        response_body = String.build do |body_output|
          client.exec(request) do |response|
            status = response.status_code
            unless response.success?
              body_output << response.body
              next
            end
            response.body_io.each_line do |line|
              next unless line.starts_with?("data:")
              data = line[5..-1].strip
              on_data.call(data)
            end
          end
        end
        Response.new(status, response_body)
      ensure
        client.try(&.close)
      end
    end

    class Registry
      def initialize
        @factories = {
          "http"     => -> { HTTP.new.as(Cri::Transport) },
          "http+sse" => -> { SSE.new.as(Cri::Transport) },
          "sse"      => -> { SSE.new.as(Cri::Transport) },
        } of String => Proc(Cri::Transport)
      end

      def register(name : String, &factory : -> Cri::Transport)
        raise "duplicate transport: #{name}" if @factories.has_key?(name)
        @factories[name] = factory
      end

      def build(name : String) : Cri::Transport
        @factories[name]?.try(&.call) || raise "no transport registered: #{name}"
      end
    end
  end
end

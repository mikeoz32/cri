require "../spec_helper"

def http_effect_handler(port : Int32, read_timeout : Time::Span = 1.second, max_response_bytes : Int64 = Cri::Effects::Handler::DEFAULT_HTTP_RESPONSE_BYTES) : Cri::Effects::Handler
  scope = "http://127.0.0.1:#{port}"
  requested = Cri::Permissions::Request.new(network: [scope])
  grants = Cri::Permissions::GrantSet.new(network: [scope])
  Cri::Effects::Handler.new(grants, requested, 1.second, read_timeout, max_response_bytes, capabilities: Cri::API::CapabilityBroker.allow_all)
end

def http_request_effect(port : Int32, path : String) : JSON::Any
  JSON.parse({
    "type"   => "http.request",
    "url"    => "http://127.0.0.1:#{port}#{path}",
    "method" => "GET",
  }.to_json)
end

describe "HTTP effects" do
  it "returns a bounded response body" do
    server = HTTP::Server.new do |context|
      body = "ok"
      context.response.content_length = body.bytesize
      context.response.print(body)
    end
    address = server.bind_unused_port
    spawn { server.listen }

    begin
      result = http_effect_handler(address.port).handle(http_request_effect(address.port, "/"))
      result.ok.should be_true
      result.result.not_nil!["body"].as_s.should eq("ok")
    ensure
      server.close
    end
  end

  it "rejects an oversized response without buffering it all" do
    server = HTTP::Server.new do |context|
      context.response.print("x" * 4097)
    end
    address = server.bind_unused_port
    spawn { server.listen }

    begin
      result = http_effect_handler(address.port, max_response_bytes: 4096).handle(http_request_effect(address.port, "/large"))
      result.ok.should be_false
      result.error.not_nil!.should contain("exceeds")
    ensure
      server.close
    end
  end

  it "does not follow redirects" do
    server = HTTP::Server.new do |context|
      context.response.status_code = 302
      context.response.headers["Location"] = "/final"
      context.response.print("redirect")
    end
    address = server.bind_unused_port
    spawn { server.listen }

    begin
      result = http_effect_handler(address.port).handle(http_request_effect(address.port, "/redirect"))
      result.ok.should be_false
      result.error.should eq("HTTP redirects are not followed")
    ensure
      server.close
    end
  end

  it "returns a timeout failure when the response is too slow" do
    server = HTTP::Server.new do |context|
      sleep 100.milliseconds
      context.response.print("late")
    end
    address = server.bind_unused_port
    spawn { server.listen }

    begin
      result = http_effect_handler(address.port, 10.milliseconds).handle(http_request_effect(address.port, "/slow"))
      result.ok.should be_false
    ensure
      server.close
    end
  end
end

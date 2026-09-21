require "../spec_helper"

describe Cri::Providers::OpenAI do
  it "exposes streaming capability through the provider abstraction" do
    provider = Cri::Providers::OpenAI.new("http://127.0.0.1:1/v1/chat/completions", "test-model", nil)
    provider.supports_streaming?.should be_true
  end

  it "builds OpenAI-compatible tool specs" do
    spec = Cri::ToolSpec.new("demo.tool", "Demo tool")
    json = spec.to_json_any

    json["type"].as_s.should eq("function")
    json["function"]["name"].as_s.should eq("demo.tool")
  end

  it "parses completion and streaming responses through the local client" do
    server = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      if body.includes?("\"tools\"")
        context.response.content_type = "application/json"
        context.response.print(%({"choices":[{"message":{"content":null,"tool_calls":[{"id":"call-1","type":"function","function":{"name":"demo.tool","arguments":"{\\"value\\":42}"}}]}}]}))
      elsif body.includes?(%("stream":true))
        context.response.content_type = "text/event-stream"
        if body.includes?("truncated")
          context.response.print("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n")
        elsif body.includes?("malformed")
          context.response.print("data: {not-json}\n\ndata: [DONE]\n\n")
        else
          context.response.print("data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}\n\ndata: [DONE]\n\n")
        end
      else
        context.response.content_type = "application/json"
        context.response.print(%({"choices":[{"message":{"content":"hello","tool_calls":[]}}]}))
      end
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    endpoint = "http://127.0.0.1:#{address.port}/v1/chat/completions"
    provider = Cri::Providers::OpenAI.new(endpoint, "test-model", nil, 5.seconds)

    provider.complete([] of Cri::Message, [] of Cri::ToolSpec).content.should eq("hello")
    tool_response = provider.complete([] of Cri::Message, [Cri::ToolSpec.new("demo.tool", "Demo tool")])
    tool_response.tool_calls.first.name.should eq("demo.tool")
    tool_response.tool_calls.first.arguments["value"].as_i.should eq(42)

    chunks = [] of String
    response = provider.complete_stream([] of Cri::Message, [] of Cri::ToolSpec) { |chunk| chunks << chunk }
    response.content.should eq("hello")
    chunks.should eq(["hello"])

    expect_raises(Cri::Providers::OpenAIAPI::StreamError, /before \[DONE\]/) do
      provider.complete_stream([Cri::Message.user("truncated")], [] of Cri::ToolSpec) { }
    end
    expect_raises(Cri::Providers::OpenAIAPI::StreamError, /invalid OpenAI SSE JSON/) do
      provider.complete_stream([Cri::Message.user("malformed")], [] of Cri::ToolSpec) { }
    end
  ensure
    server.try(&.close)
  end
end

require "../spec_helper"

describe Cri::APIClients::OpenAICompatible do
  it "exposes streaming capability through the API client abstraction" do
    client = Cri::APIClients::OpenAICompatible.new("http://127.0.0.1:1/v1/chat/completions", "test-model", nil)
    client.supports_streaming?.should be_true
  end

  it "builds OpenAI-compatible tool specs" do
    spec = Cri::ToolSpec.new("demo.tool", "Demo tool")
    json = spec.to_json_any
    json["type"].as_s.should eq("function")
    json["function"]["name"].as_s.should eq("demo.tool")
  end

  it "uses ChatGPT credentials with the Codex responses API client" do
    server = HTTP::Server.new do |context|
      context.request.headers["Authorization"].should eq("Bearer access-token")
      context.request.headers["chatgpt-account-id"].should eq("account-1")
      context.request.path.should eq("/backend-api/codex/responses")
      body = JSON.parse(context.request.body.try(&.gets_to_end) || "{}")
      body["stream"].as_bool.should be_true
      if tools = body["tools"]?.try(&.as_a)
        tools.size.should eq(1)
        tools[0]["type"].as_s.should eq("function")
        tools[0]["name"].as_s.should eq("demo_tool")
      end
      input = body["input"].as_a
      if input.any? { |item| item["type"]?.try(&.as_s?) == "function_call" }
        input.any? { |item| item["type"]?.try(&.as_s?) == "function_call_output" }.should be_true
        input.any? { |item| item["tool_calls"]? }.should be_false
      end
      context.response.print(%({"output":[{"type":"message","content":[{"type":"output_text","text":"hello from subscription"}]}]}))
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    client = Cri::APIClients::OpenAICodexResponses.new(
      "http://127.0.0.1:#{address.port}/backend-api/codex/responses",
      "gpt-5",
      %({"access_token":"access-token","account_id":"account-1"})
    )

    response = client.complete([Cri::Message.user("hello")], [] of Cri::ToolSpec)
    response.content.should eq("hello from subscription")

    # Responses API tools must carry the type at the top level, unlike the
    # Chat Completions function wrapper.
    tool = Cri::ToolSpec.new("demo.tool", "Demo tool")
    tool_client = Cri::APIClients::OpenAICodexResponses.new(
      "http://127.0.0.1:#{address.port}/backend-api/codex/responses",
      "gpt-5",
      %({"access_token":"access-token","account_id":"account-1"})
    )
    tool_response = tool_client.complete([Cri::Message.user("hello")], [tool])
    tool_response.content.should eq("hello from subscription")

    call = Cri::ToolCall.new("call-1", "demo.tool", JSON.parse(%({"city":"Lviv"})))
    history = [
      Cri::Message.user("what is the weather?"),
      Cri::Message.assistant(nil, [call]),
      Cri::Message.tool(call, %({"temperature":10})),
    ]
    history_response = tool_client.complete(history, [tool])
    history_response.content.should eq("hello from subscription")
  ensure
    server.try(&.close)
  end

  it "validates an API key through the models endpoint" do
    server = HTTP::Server.new do |context|
      context.request.path.should eq("/v1/models")
      context.request.headers["Authorization"].should eq("Bearer test-token")
      context.response.status_code = 200
      context.response.print(%({"data":[]}))
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    client = Cri::APIClients::OpenAICompatibleHTTP.new("http://127.0.0.1:#{address.port}/v1/chat/completions", "test-token", 5.seconds)
    client.validate_api_key
  ensure
    server.try(&.close)
  end

  it "parses completion and streaming responses through the local client" do
    server = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      if body.includes?("\"tools\"")
        context.response.content_type = "application/json"
        context.response.print("{\"choices\":[{\"message\":{\"content\":null,\"tool_calls\":[{\"id\":\"call-1\",\"type\":\"function\",\"function\":{\"name\":\"demo.tool\",\"arguments\":\"{\\\"value\\\":42}\"}}]}}]}")
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
    client = Cri::APIClients::OpenAICompatible.new(endpoint, "test-model", nil, 5.seconds)

    client.complete([] of Cri::Message, [] of Cri::ToolSpec).content.should eq("hello")
    tool_response = client.complete([] of Cri::Message, [Cri::ToolSpec.new("demo.tool", "Demo tool")])
    tool_response.tool_calls.first.name.should eq("demo.tool")
    JSON.parse(tool_response.tool_calls.first.arguments.raw)["value"].as_i.should eq(42)

    chunks = [] of String
    response = client.complete_stream([] of Cri::Message, [] of Cri::ToolSpec) { |chunk| chunks << chunk }
    response.content.should eq("hello")
    chunks.should eq(["hello"])

    expect_raises(Cri::APIClients::StreamError, /before \[DONE\]/) do
      client.complete_stream([Cri::Message.user("truncated")], [] of Cri::ToolSpec) { }
    end
    expect_raises(Cri::APIClients::StreamError, /invalid OpenAI SSE JSON/) do
      client.complete_stream([Cri::Message.user("malformed")], [] of Cri::ToolSpec) { }
    end
  ensure
    server.try(&.close)
  end
end

describe Cri::APIClients::OpenAIResponses do
  it "uses native web search and preserves web citations and function calls" do
    server = HTTP::Server.new do |context|
      context.request.method.should eq("POST")
      context.request.path.should eq("/v1/responses")
      context.request.headers["Authorization"].should eq("Bearer test-token")
      body = JSON.parse(context.request.body.try(&.gets_to_end) || "{}")
      body["model"].as_s.should eq("gpt-4.1")
      body["stream"].as_bool.should be_false
      body["tools"].as_a.map { |tool| tool["type"].as_s }.should eq(["web_search", "function"])
      body["tools"].as_a.last["name"].as_s.should eq("demo_tool")
      body["input"].as_a.first["content"].as_s.should eq("Find recent Crystal news")
      context.response.content_type = "application/json"
      context.response.print(%({"output":[{"type":"message","content":[{"type":"output_text","text":"Crystal released a new version.","annotations":[{"type":"url_citation","url":"https://crystal-lang.org/releases/","title":"Crystal releases"}]}]},{"type":"function_call","call_id":"call-1","name":"demo_tool","arguments":"{\\"ok\\":true}"}]}))
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }

    client = Cri::APIClients::OpenAIResponses.new(
      "http://127.0.0.1:#{address.port}/v1/chat/completions",
      "gpt-4.1",
      "test-token"
    )
    response = client.complete([Cri::Message.user("Find recent Crystal news")], [Cri::ToolSpec.new("demo.tool", "Demonstration tool")])

    response.content.not_nil!.should contain("Crystal released a new version.")
    response.content.not_nil!.should contain("[Crystal releases](https://crystal-lang.org/releases/)")
    response.tool_calls.size.should eq(1)
    response.tool_calls.first.name.should eq("demo.tool")
    JSON.parse(response.tool_calls.first.arguments.raw)["ok"].as_bool.should be_true
  ensure
    server.try(&.close)
  end

  it "streams response text once and adds citations from the completed output item" do
    server = HTTP::Server.new do |context|
      context.request.path.should eq("/v1/responses")
      body = JSON.parse(context.request.body.try(&.gets_to_end) || "{}")
      body["stream"].as_bool.should be_true
      context.response.content_type = "text/event-stream"
      context.response.print("data: {\"type\":\"response.output_text.delta\",\"delta\":\"Answer\"}\n\n")
      context.response.print("data: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Answer\",\"annotations\":[{\"type\":\"url_citation\",\"url\":\"https://example.com\",\"title\":\"Example\"}]}]}}\n\n")
      context.response.print("data: [DONE]\n\n")
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    client = Cri::APIClients::OpenAIResponses.new("http://127.0.0.1:#{address.port}/v1/responses", "gpt-4.1", "test-token")

    chunks = [] of String
    response = client.complete_stream([Cri::Message.user("Search")], [] of Cri::ToolSpec) { |chunk| chunks << chunk }

    chunks.should eq(["Answer"])
    response.content.should eq("Answer\n\nSources:\n- [Example](https://example.com)\n")
  ensure
    server.try(&.close)
  end
end

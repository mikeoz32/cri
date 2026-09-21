require "../spec_helper"

class InfiniteToolProvider < Cri::Provider
  def complete(messages : Array(Cri::Message), tools : Array(Cri::ToolSpec)) : Cri::AssistantResponse
    call = Cri::ToolCall.new("loop", "builtin.echo", JSON.parse("{}"))
    Cri::AssistantResponse.new(nil, [call])
  end
end

class ManyToolCallsProvider < Cri::Provider
  def complete(messages : Array(Cri::Message), tools : Array(Cri::ToolSpec)) : Cri::AssistantResponse
    calls = (0...4).map { |index| Cri::ToolCall.new("call-#{index}", "builtin.echo", JSON.parse("{}")) }
    Cri::AssistantResponse.new(nil, calls)
  end
end

class LargeResponseProvider < Cri::Provider
  def complete(messages : Array(Cri::Message), tools : Array(Cri::ToolSpec)) : Cri::AssistantResponse
    Cri::AssistantResponse.new("x" * 100)
  end
end

class LargeResultTool < Cri::Tool
  def initialize
    super("large.result", "Return a large result")
  end

  def call(input : JSON::Any) : Cri::ToolResult
    Cri::ToolResult.new(true, JSON.parse({"content" => "x" * 100}.to_json))
  end
end

class LargeResultProvider < Cri::Provider
  def complete(messages : Array(Cri::Message), tools : Array(Cri::ToolSpec)) : Cri::AssistantResponse
    call = Cri::ToolCall.new("large", "large.result", JSON.parse("{}"))
    Cri::AssistantResponse.new(nil, [call])
  end
end

describe Cri::Agent do
  it "stops an unbounded tool loop" do
    tools = Cri::ToolRegistry.new
    tools.register_builtins
    agent = Cri::Agent.new(InfiniteToolProvider.new, tools, max_steps: 2)

    expect_raises(Exception, /agent step limit exceeded/) do
      agent.run_turn("loop")
    end
  end

  it "rejects oversized input before mutating the session" do
    agent = Cri::Agent.new(LargeResponseProvider.new, Cri::ToolRegistry.new, max_input_bytes: 4_i64)

    expect_raises(Cri::Agent::LimitError, /input exceeds/) do
      agent.run_turn("12345")
    end
    agent.session.messages.should be_empty
  end

  it "bounds tool calls in one provider response" do
    agent = Cri::Agent.new(ManyToolCallsProvider.new, Cri::ToolRegistry.new, max_tool_calls_per_step: 2)

    expect_raises(Cri::Agent::LimitError, /too many tool calls/) do
      agent.run_turn("many")
    end
  end

  it "bounds non-streaming model responses" do
    agent = Cri::Agent.new(LargeResponseProvider.new, Cri::ToolRegistry.new, max_response_bytes: 10_i64)

    expect_raises(Cri::Agent::LimitError, /agent response exceeds/) do
      agent.run_turn("large")
    end
  end

  it "bounds serialized tool results" do
    tools = Cri::ToolRegistry.new
    tools.register(LargeResultTool.new)
    agent = Cri::Agent.new(LargeResultProvider.new, tools, max_tool_result_bytes: 16_i64)

    expect_raises(Cri::Agent::LimitError, /tool result exceeds/) do
      agent.run_turn("result")
    end
  end
end

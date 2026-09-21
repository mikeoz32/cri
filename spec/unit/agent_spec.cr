require "../spec_helper"

class SequenceProvider < Cri::Provider
  getter calls = 0

  def complete(messages : Array(Cri::Message), tools : Array(Cri::ToolSpec)) : Cri::AssistantResponse
    @calls += 1
    if @calls == 1
      call = Cri::ToolCall.new("call-1", "builtin.echo", JSON.parse(%({"value":42})))
      Cri::AssistantResponse.new(nil, [call])
    else
      Cri::AssistantResponse.new("done")
    end
  end
end

describe Cri::Agent do
  it "runs a model turn through the tool loop" do
    tools = Cri::ToolRegistry.new
    tools.register_builtins
    provider = SequenceProvider.new
    agent = Cri::Agent.new(provider, tools)

    agent.run_turn("hello").should eq("done")
    provider.calls.should eq(2)
    agent.session.messages.size.should eq(4)
  end
end

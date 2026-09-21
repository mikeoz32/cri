require "../spec_helper"

describe Cri::Auth::Broker do
  it "registers OpenAI API and Codex flow configuration" do
    broker = Cri::Auth::Broker.new
    broker.register(Cri::Auth::Provider.new(
      "openai-api",
      "OpenAI API",
      [Cri::Auth::Flow.new("api-key", Cri::Auth::FlowKind::ApiToken)]
    ))
    broker.register(Cri::Auth::Provider.new(
      "openai-codex",
      "ChatGPT / Codex",
      [Cri::Auth::Flow.new("chatgpt", Cri::Auth::FlowKind::OAuthBrowser, {"transport" => "codex-app-server"})]
    ))

    broker.provider("openai-api").flow("api-key").kind.should eq(Cri::Auth::FlowKind::ApiToken)
    broker.provider("openai-codex").flow("chatgpt").metadata["transport"].should eq("codex-app-server")
  end

  it "keeps API tokens behind an opaque credential reference" do
    broker = Cri::Auth::Broker.new
    broker.register(Cri::Auth::Provider.new(
      "openai-api",
      "OpenAI API",
      [Cri::Auth::Flow.new("api-key", Cri::Auth::FlowKind::ApiToken)]
    ))

    ref = broker.import_api_token("openai-api", "api-key", "secret-token")
    ref.id.should_not contain("secret-token")
    ref.provider_id.should eq("openai-api")
    broker.secret(ref).should eq("secret-token")
  end

  it "rejects API tokens for non-token flows" do
    broker = Cri::Auth::Broker.new
    broker.register(Cri::Auth::Provider.new(
      "openai-codex",
      "ChatGPT / Codex",
      [Cri::Auth::Flow.new("chatgpt", Cri::Auth::FlowKind::OAuthBrowser)]
    ))

    expect_raises(Exception, /not an API token flow/) do
      broker.import_api_token("openai-codex", "chatgpt", "token")
    end
  end
end

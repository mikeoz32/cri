require "../spec_helper"

describe Cri::Auth::Broker do
  it "registers OpenAI API and Codex flow configuration" do
    broker = Cri::Auth::Broker.new(Cri::Auth::MemoryCredentialStore.new)
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
    broker = Cri::Auth::Broker.new(Cri::Auth::MemoryCredentialStore.new)
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

  it "keeps the memory store explicitly non-persistent" do
    store = Cri::Auth::MemoryCredentialStore.new
    store.persistent?.should be_false
  end

  it "runs generic OAuth device polling and refresh" do
    requests = [] of String
    server = HTTP::Server.new do |context|
      requests << context.request.path
      body = context.request.body.try(&.gets_to_end) || ""
      if context.request.path == "/device"
        context.response.print(%({"device_code":"device-1","user_code":"USER-1","verification_uri":"https://example.test/device","expires_in":60,"interval":0}))
      else
        if body.includes?("grant_type=refresh_token")
          context.response.print(%({"access_token":"access-2","token_type":"Bearer","expires_in":3600}))
        else
          context.response.print(%({"access_token":"access-1","refresh_token":"refresh-1","token_type":"Bearer","expires_in":3600}))
        end
      end
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    config = Cri::Auth::OAuthConfig.new(
      "http://127.0.0.1:#{address.port}/token",
      "client",
      nil,
      "http://127.0.0.1:#{address.port}/device",
      ["openid"]
    )
    statuses = [] of String
    tokens = Cri::Auth::OAuthClient.new.device_login(config) { |status| statuses << status }

    tokens.access_token.should eq("access-1")
    statuses.should contain("Code: USER-1")
    refreshed = Cri::Auth::OAuthClient.new.refresh(config, tokens.refresh_token.not_nil!)
    refreshed.access_token.should eq("access-2")
    requests.should eq(["/device", "/token", "/token"])
  ensure
    server.try(&.close)
  end

  it "runs the Codex-compatible device-code flow" do
    polls = 0
    server = HTTP::Server.new do |context|
      if context.request.path.ends_with?("/usercode")
        context.response.print(%({"device_auth_id":"device-1","user_code":"CODE-1","interval":0}))
      elsif context.request.path == "/token"
        polls += 1
        if polls == 1
          context.response.status_code = 403
        else
          context.response.print(%({"authorization_code":"auth-code","code_verifier":"verifier"}))
        end
      else
        context.response.print(%({"access_token":"access-1","refresh_token":"refresh-1","token_type":"Bearer","expires_in":3600}))
      end
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    config = Cri::Auth::OAuthConfig.new(
      "http://127.0.0.1:#{address.port}/oauth/token",
      "client",
      nil,
      "http://127.0.0.1:#{address.port}/usercode",
      ["openid"],
      nil,
      nil,
      "openai_codex",
      "http://127.0.0.1:#{address.port}/token",
      "https://example.test/device",
      "https://example.test/callback"
    )
    statuses = [] of String
    tokens = Cri::Auth::OAuthClient.new.device_login(config) { |status| statuses << status }

    tokens.access_token.should eq("access-1")
    statuses.should contain("Code: CODE-1")
  ensure
    server.try(&.close)
  end

  it "persists only cri-owned credentials and reloads them" do
    root = "/tmp/cri-auth-store-#{Process.pid}-#{Random.rand(1_000_000)}"
    path = File.join(root, "auth.json")
    begin
      store = Cri::Auth::FileCredentialStore.new(path)
      ref = Cri::Auth::CredentialRef.new("cred-test", "openai-api", "api-key")
      store.save(Cri::Auth::Credential.new(ref, "secret-token"))

      reloaded = Cri::Auth::FileCredentialStore.new(path)
      reloaded.get(ref).not_nil!.secret.should eq("secret-token")
      reloaded.find("openai-api", "api-key").not_nil!.id.should eq("cred-test")
      File.info(path).permissions.value.should eq(0o600)
      File.exists?("#{path}.tmp").should be_false

      reloaded.delete(ref)
      reloaded.get(ref).should be_nil
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "rejects API tokens for non-token flows" do
    broker = Cri::Auth::Broker.new(Cri::Auth::MemoryCredentialStore.new)
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

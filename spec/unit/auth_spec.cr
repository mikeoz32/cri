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

  it "reports a missing Codex executable without reading external auth state" do
    root = "/tmp/cri-codex-missing-#{Process.pid}"
    expect_raises(Exception, /Codex executable not found/) do
      Cri::Auth::CodexAppServer.new(root, "/tmp/cri-codex-does-not-exist").login_browser { |_| }
    end
  ensure
    FileUtils.rm_rf(root) if root
  end

  it "completes the documented browser login protocol" do
    root = "/tmp/cri-codex-protocol-#{Process.pid}-#{Random.rand(1_000_000)}"
    script = File.join(root, "codex")
    FileUtils.mkdir_p(root)
    File.write(script, <<-SH)
      #!/bin/sh
      while IFS= read -r line; do
        case "$line" in
          *'"id":0'*) printf '%s\\n' '{"id":0,"result":{}}' ;;
          *'"id":1'*) printf '%s\\n' '{"id":1,"result":{"loginId":"login-1","authUrl":"https://example.test/login"}}' ; printf '%s\\n' '{"method":"account/login/completed","params":{"loginId":"login-1","success":true}}' ;;
        esac
      done
    SH
    File.chmod(script, 0o700)
    previous = ENV["CRI_NO_BROWSER"]?
    ENV["CRI_NO_BROWSER"] = "1"
    statuses = [] of String

    result = Cri::Auth::CodexAppServer.new(File.join(root, "home"), script).login_browser { |status| statuses << status }

    result.login_id.should eq("login-1")
    result.auth_url.should eq("https://example.test/login")
    statuses.should contain("Waiting for ChatGPT login")
  ensure
    if previous
      ENV["CRI_NO_BROWSER"] = previous
    else
      ENV.delete("CRI_NO_BROWSER")
    end
    FileUtils.rm_rf(root) if root
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

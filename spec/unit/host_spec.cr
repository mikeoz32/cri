require "../spec_helper"

describe Cri::Host do
  it "composes builtins and extension contributions behind registries" do
    host = Cri::Host.new

    host.tools.names.should contain("builtin.read_file")
    host.tools.names.should contain("fixture.echo")
    host.commands.names.should contain("fixture:run")
    host.extension_command("fixture:run").not_nil!.name.should eq("fixture")
  end

  it "registers providers with their auth flows through the host provider registry" do
    host = Cri::Host.new(auth: Cri::Auth::Broker.new(Cri::Auth::MemoryCredentialStore.new))

    host.providers.register(Cri::ProviderRegistration.new(
      "test-provider",
      "Test Provider",
      "test-api",
      "https://example.test/v1",
      "test-model",
      "http+sse",
      [Cri::Auth::Flow.new("api-key", Cri::Auth::FlowKind::ApiToken)]
    ))
    test_provider = host.providers.find("test-provider").not_nil!
    test_provider.api_type.should eq("test-api")
    test_provider.endpoint.should eq("https://example.test/v1")
    test_provider.model.should eq("test-model")
    test_provider.transport_type.should eq("http+sse")
    test_provider.auth_flows.first.id.should eq("api-key")
    host.providers.register(Cri::ProviderRegistration.new(
      "openrouter",
      "OpenRouter",
      "openai",
      "https://openrouter.ai/api/v1/chat/completions",
      "openai/gpt-4o-mini",
      "http+sse",
      [Cri::Auth::Flow.new("api-key", Cri::Auth::FlowKind::ApiToken)]
    ))
    host.provider("openrouter").should be_a(Cri::ProviderRuntime)
    host.providers.register(Cri::ProviderRegistration.new(
      "extension/fixture/example",
      "Example Service",
      "example-api",
      "https://example.test/v1",
      "example-model",
      "http+sse",
      [Cri::Auth::Flow.new("token", Cri::Auth::FlowKind::ApiToken)],
      "extension:fixture"
    ))
    host.providers.find("extension/fixture/example").not_nil!.source.should eq("extension:fixture")
  end

  it "registers provider definitions returned by an extension init hook" do
    host = Cri::Host.new(auth: Cri::Auth::Broker.new(Cri::Auth::MemoryCredentialStore.new))
    effect = JSON.parse({
      "type"       => "host.provider.register",
      "id"         => "example",
      "title"      => "Example Service",
      "api_type"   => "example-api",
      "endpoint"   => "https://example.test/v1",
      "model"      => "example-model",
      "auth_flows" => [{
        "id"    => "device",
        "kind"  => "oauth_device",
        "oauth" => {
          "device_authorization_endpoint" => "https://auth.example/device",
          "token_endpoint"                => "https://auth.example/token",
          "client_id"                     => "client",
          "scopes"                        => ["openid", "offline_access"],
        },
      }],
    }.to_json)

    host.providers.register_extension_effect(effect, "fixture")

    provider = host.providers.find("extension/fixture/example").not_nil!
    provider.auth_flows.first.kind.should eq(Cri::Auth::FlowKind::OAuthDevice)
    provider.auth_flows.first.oauth.not_nil!.scopes.should eq(["openid", "offline_access"])
  end
end

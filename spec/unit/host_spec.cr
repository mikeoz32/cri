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

    openai = host.providers.find("openai-api").not_nil!
    openai.transport.should eq("openai")
    openai.auth_flows.first.id.should eq("api-key")
    host.providers.register(Cri::ProviderRegistration.new(
      "extension/fixture/example",
      "Example Service",
      "extension/fixture",
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
      "transport"  => "example",
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

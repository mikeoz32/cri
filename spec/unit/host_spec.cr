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
    host.providers.find("extension/fixture/example").not_nil!.source.should eq("extension:fixture")
  end
end

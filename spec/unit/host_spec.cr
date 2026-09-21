require "../spec_helper"

describe Cri::Host do
  it "composes builtins and extension contributions behind registries" do
    host = Cri::Host.new

    host.tools.names.should contain("builtin.read_file")
    host.tools.names.should contain("fixture.echo")
    host.commands.names.should contain("fixture:run")
    host.extension_command("fixture:run").not_nil!.name.should eq("fixture")
  end
end

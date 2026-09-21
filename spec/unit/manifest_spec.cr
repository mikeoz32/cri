require "../spec_helper"

describe Cri::Extensions::Manifest do
  it "parses contribution bundles" do
    manifest = Cri::Extensions::Manifest.load("examples/extensions/fixture/extension.toml")
    manifest.valid?.should be_true
    manifest.name.should eq("fixture")
    manifest.tools.first.name.should eq("fixture.echo")
    manifest.commands.first.name.should eq("fixture:run")
    manifest.ui_actions.size.should eq(1)
    manifest.ui_actions.first.name.should eq("fixture.notify")
    manifest.auth_providers.size.should eq(1)
    manifest.auth_providers.first.id.should eq("example")
    manifest.auth_providers.first.flows.first.kind.should eq("api_token")

    github = Cri::Extensions::Manifest.load("examples/extensions/github_issue/extension.toml")
    github.valid?.should be_false
    github.errors.should contain("wasm file not found: #{File.expand_path("plugin.wasm", "examples/extensions/github_issue")}")
  end
end

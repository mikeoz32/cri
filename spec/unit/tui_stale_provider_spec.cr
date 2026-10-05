require "../spec_helper"
require "file_utils"

describe Cri::Tui::Controller do
  it "explains how to recover when a saved session references an unavailable provider" do
    root = "/tmp/cri-stale-provider-#{Process.pid}-#{Random.rand(1_000_000)}"
    Dir.mkdir(root)
    begin
      session = Cri::Session.new
      session.select_model(Cri::ModelRef.new("openrouter/gpt-4o", "openrouter", "openai/gpt-4o", "GPT-4o"))
      Cri::SessionStore.new(root).save(session)
      config = Cri::Config.new(root, [] of String, Cri::Permissions::GrantPolicy.default)
      controller = Cri::Tui::Controller.new(Cri::Host.new(config))

      _keep_running, output = controller.submit("hello")

      output.should contain("saved session model 'openrouter/gpt-4o'")
      output.should contain("unavailable provider 'openrouter'")
      output.should contain(":model refresh")
      output.should contain(":session new")
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "accepts models as an alias for the singular model command" do
    root = "/tmp/cri-stale-provider-#{Process.pid}-#{Random.rand(1_000_000)}"
    Dir.mkdir(root)
    begin
      config = Cri::Config.new(root, [] of String, Cri::Permissions::GrantPolicy.default)
      controller = Cri::Tui::Controller.new(Cri::Host.new(config))

      _keep_running, output = controller.submit("/models")

      output.should start_with("Models:")
      output.should_not contain("unknown command")
    ensure
      FileUtils.rm_rf(root)
    end
  end
end

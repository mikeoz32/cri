require "../spec_helper"
require "file_utils"

describe Cri::Tui::Application do
  it "shows pending approvals and resolves them from the TUI keys" do
    root = "/tmp/cri-approval-ui-#{Process.pid}-#{Random.rand(1_000_000)}"
    Dir.mkdir(root)
    begin
      config = Cri::Config.new(root, [] of String, Cri::Permissions::GrantPolicy.default)
      host = Cri::Host.new(config)
      app = Cri::Tui::Application.new(Cri::Tui::Controller.new(host))
      requested = Channel(String).new(1)
      completed = Channel(Bool).new(1)
      host.events.subscribe("approval.requested") { |event| requested.send(event.data["id"].as_s) }
      request = Cri::API::CapabilityRequest.new("test-approval", "fixture", "filesystem.list", root, "List directory contents")

      spawn { completed.send(host.capabilities.authorize(request)) }
      id = requested.receive
      app.renderer.approval_prompt.not_nil!.should contain("filesystem.list")
      app.renderer.frame.join.should contain("[y]allow")
      app.handle_key(Cri::Tui::KeyEvent.character("y"))
      host.capabilities.resolve("missing", Cri::API::ApprovalDecision::Deny).should be_false
      completed.receive.should be_true
      app.renderer.approval_prompt.should be_nil
      id.should eq("test-approval")
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "denies an approval with Escape" do
    root = "/tmp/cri-approval-ui-#{Process.pid}-#{Random.rand(1_000_000)}"
    Dir.mkdir(root)
    begin
      host = Cri::Host.new(Cri::Config.new(root, [] of String, Cri::Permissions::GrantPolicy.default))
      app = Cri::Tui::Application.new(Cri::Tui::Controller.new(host))
      requested = Channel(String).new(1)
      completed = Channel(Bool).new(1)
      host.events.subscribe("approval.requested") { |event| requested.send(event.data["id"].as_s) }
      spawn do
        completed.send(host.capabilities.authorize(Cri::API::CapabilityRequest.new("deny-me", "fixture", "filesystem.list", root, "List")))
      end
      requested.receive
      app.handle_key(Cri::Tui::KeyEvent.new(Cri::Tui::Key::Escape))
      completed.receive.should be_false
    ensure
      FileUtils.rm_rf(root)
    end
  end
end

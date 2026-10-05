require "../spec_helper"
require "file_utils"

describe "host filesystem API" do
  it "lists workspace entries only after one-shot approval" do
    root = "/tmp/cri-fs-api-#{Process.pid}-#{Random.rand(1_000_000)}"
    nested = File.join(root, "src")
    FileUtils.mkdir_p(nested)
    File.write(File.join(nested, "main.cr"), "puts 1")
    begin
      requested = Cri::Permissions::Request.new(filesystem_read: ["."])
      grants = Cri::Permissions::GrantSet.new(filesystem_read: ["."])
      events = Cri::EventBus.new
      broker = Cri::API::CapabilityBroker.new(Cri::API::EventApprovalBackend.new(events))
      handler = Cri::Effects::Handler.new(grants, requested, capabilities: broker, actor: "fixture", workspace_root: root)
      approval_id = Channel(String).new(1)
      events.subscribe("approval.requested") { |event| approval_id.send(event.data["id"].as_s) }
      result_channel = Channel(Cri::Effects::Result).new(1)

      spawn { result_channel.send(handler.handle(JSON.parse(%({"type":"filesystem.list","path":"src"})))) }
      id = approval_id.receive
      broker.resolve(id, Cri::API::ApprovalDecision::Allow).should be_true
      result = result_channel.receive

      result.ok.should be_true
      JSON.parse(result.result.not_nil!.raw)["entries"].as_a.map { |entry| entry["name"].as_s }.should eq(["main.cr"])
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "denies the API call when approval is denied" do
    root = "/tmp/cri-fs-api-#{Process.pid}-#{Random.rand(1_000_000)}"
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "file"), "data")
    begin
      handler = Cri::Effects::Handler.new(
        Cri::Permissions::GrantSet.new(filesystem_read: ["."]),
        Cri::Permissions::Request.new(filesystem_read: ["."]),
        workspace_root: root
      )
      result = handler.handle(JSON.parse(%({"type":"filesystem.list","path":"."})))
      result.ok.should be_false
      result.error.should eq("capability approval denied")
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "checks the extension and host filesystem scopes before asking for approval" do
    root = "/tmp/cri-fs-api-#{Process.pid}-#{Random.rand(1_000_000)}"
    FileUtils.mkdir_p(root)
    begin
      handler = Cri::Effects::Handler.new(
        Cri::Permissions::GrantSet.default_dev,
        Cri::Permissions::Request.new(filesystem_read: ["."]),
        capabilities: Cri::API::CapabilityBroker.allow_all,
        workspace_root: root
      )
      result = handler.handle(JSON.parse(%({"type":"filesystem.list","path":"."})))
      result.ok.should be_false
      result.error.not_nil!.should contain("file read permission denied")
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "rejects paths that escape the workspace through traversal or symlinks" do
    root = "/tmp/cri-fs-api-#{Process.pid}-#{Random.rand(1_000_000)}"
    outside = "#{root}-outside"
    FileUtils.mkdir_p(root)
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, "secret"), "secret")
    File.symlink(outside, File.join(root, "external"))
    begin
      handler = Cri::Effects::Handler.new(
        Cri::Permissions::GrantSet.new(filesystem_read: ["."]),
        Cri::Permissions::Request.new(filesystem_read: ["."]),
        capabilities: Cri::API::CapabilityBroker.allow_all,
        workspace_root: root
      )
      ["../#{File.basename(outside)}", "external"].each do |path|
        result = handler.handle(JSON.parse({"type" => "filesystem.list", "path" => path}.to_json))
        result.ok.should be_false
      end
    ensure
      FileUtils.rm_rf(root)
      FileUtils.rm_rf(outside)
    end
  end
end

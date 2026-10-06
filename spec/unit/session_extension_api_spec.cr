require "../spec_helper"
require "file_utils"

class SessionStateWritingRuntime < Cri::Wasm::Runtime
  def call(manifest : Cri::Extensions::Manifest, request : Cri::Wasm::RequestEnvelope) : Cri::Wasm::ResponseEnvelope
    Cri::Wasm::ResponseEnvelope.new(false, nil, [] of Cri::Effects::Effect, "unexpected direct call")
  end

  def run(manifest : Cri::Extensions::Manifest, request : Cri::Wasm::RequestEnvelope, handler : Cri::Effects::Handler) : Cri::Wasm::ResponseEnvelope
    effect = Cri::Effects::Effect.from_json(%({
      "type":"session.state.set",
      "value":{"from_tool":"#{request.name}"}
    }))
    result = handler.handle(effect)
    Cri::Wasm::ResponseEnvelope.new(result.ok, result.result, [] of Cri::Effects::Effect, result.error)
  end
end

describe "extension session state API" do
  it "stores state in the session under the calling extension namespace and emits an update event" do
    session = Cri::Session.new("session-1")
    events = Cri::EventBus.new
    event_channel = Channel(Cri::Event).new(1)
    events.subscribe("session.extension_state.updated") { |event| event_channel.send(event) }
    handler = Cri::Effects::Handler.new(
      Cri::Permissions::GrantSet.new(session_state: true),
      Cri::Permissions::Request.new(session_state: true),
      capabilities: Cri::API::CapabilityBroker.allow_all,
      actor: "todo",
      session: session,
      events: events
    )

    written = handler.handle(Cri::Effects::Effect.from_json(%({
      "type":"session.state.set",
      "value":{"todos":[{"id":"a","text":"ship it","done":false}]}
    })))
    written.ok.should be_true

    updated = event_channel.receive
    updated.data["session_id"].as_s.should eq("session-1")
    updated.data["extension_id"].as_s.should eq("todo")

    read = handler.handle(Cri::Effects::Effect.from_json(%({"type":"session.state.get"})))
    read.ok.should be_true
    read.result.not_nil!.raw.should eq(%({"todos":[{"id":"a","text":"ship it","done":false}]}))

    another = Cri::Effects::Handler.new(
      Cri::Permissions::GrantSet.new(session_state: true),
      Cri::Permissions::Request.new(session_state: true),
      capabilities: Cri::API::CapabilityBroker.allow_all,
      actor: "other",
      session: session
    ).handle(Cri::Effects::Effect.from_json(%({"type":"session.state.get"})))
    another.ok.should be_true
    another.result.should be_nil
  end

  it "requires both a declared permission and a configured grant before asking for approval" do
    handler = Cri::Effects::Handler.new(
      Cri::Permissions::GrantSet.default_dev,
      Cri::Permissions::Request.new(session_state: true),
      capabilities: Cri::API::CapabilityBroker.allow_all,
      actor: "todo",
      session: Cri::Session.new("session-1")
    )

    result = handler.handle(Cri::Effects::Effect.from_json(%({"type":"session.state.get"})))
    result.ok.should be_false
    result.error.should eq("session state permission denied")
  end

  it "does not update extension state until the user approves the write" do
    session = Cri::Session.new("session-1")
    events = Cri::EventBus.new
    broker = Cri::API::CapabilityBroker.new(Cri::API::EventApprovalBackend.new(events))
    handler = Cri::Effects::Handler.new(
      Cri::Permissions::GrantSet.new(session_state: true),
      Cri::Permissions::Request.new(session_state: true),
      capabilities: broker,
      actor: "todo",
      session: session,
      events: events
    )
    approval_channel = Channel(Cri::API::CapabilityRequest).new(1)
    events.subscribe("approval.requested") do |event|
      approval_channel.send(Cri::API::CapabilityRequest.new(
        event.data["id"].as_s,
        event.data["actor"].as_s,
        event.data["capability"].as_s,
        event.data["target"].as_s,
        event.data["reason"].as_s
      ))
    end
    result_channel = Channel(Cri::Effects::Result).new(1)
    spawn do
      result_channel.send(handler.handle(Cri::Effects::Effect.from_json(%({
        "type":"session.state.set",
        "value":{"items":[]}
      }))))
    end

    request = approval_channel.receive
    request.capability.should eq("session.state.write")
    request.target.should eq("session-1")
    broker.resolve(request.id, Cri::API::ApprovalDecision::Deny).should be_true

    result = result_channel.receive
    result.ok.should be_false
    result.error.should eq("capability approval denied")
    session.extension_data("todo").should be_nil
  end

  it "round-trips namespaced extension data in the session envelope" do
    session = Cri::Session.new("session-1")
    session.set_extension_data("todo", Cri::RawJSON.new(%({"items":[]})))

    restored = Cri::Session.from_json(session.to_json)
    restored.extension_data("todo").not_nil!.raw.should eq(%({"items":[]}))
  end

  it "passes the active session through the agent tool router to the extension host API" do
    root = File.join(Dir.tempdir, "cri-session-state-#{Random::Secure.hex(4)}")
    extension_dir = File.join(root, "todo_ext")
    Dir.mkdir_p(extension_dir)
    manifest_path = File.join(extension_dir, "extension.toml")
    File.write(manifest_path, <<-TOML
      name = "todo_ext"
      version = "0.1.0"
      abi = "cri.extension.v1"
      wasm = "plugin.wasm"

      [permissions]
      session_state = true

      [[tools]]
      name = "todo.add"
      description = "Add a todo"
      TOML
    )
    begin
      manifest = Cri::Extensions::Manifest.load(manifest_path, require_wasm: false)
      extensions = Cri::Extensions::Registry.new([root])
      extensions.manifests << manifest
      grants = Cri::Permissions::GrantPolicy.new
      grants.extensions["todo_ext"] = Cri::Permissions::GrantSet.new(session_state: true)
      broker = Cri::API::CapabilityBroker.allow_all
      invoker = Cri::Extensions::Invoker.new(SessionStateWritingRuntime.new, grants, broker, root)
      router = Cri::ToolRouter.new(Cri::ToolRegistry.new, extensions, invoker, grants)
      session = Cri::Session.new("session-1")

      result = router.call("todo.add", Cri::RawJSON.new(%({})), session)

      result.ok.should be_true
      session.extension_data("todo_ext").not_nil!.raw.should eq(%({"from_tool":"todo.add"}))
    ensure
      FileUtils.rm_rf(root)
    end
  end
end

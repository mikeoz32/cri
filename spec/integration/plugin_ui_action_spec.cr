require "../spec_helper"

class UiNotificationRuntime < Cri::Wasm::Runtime
  getter last_input : JSON::Any?

  def call(manifest : Cri::Extensions::Manifest, request : Cri::Wasm::RequestEnvelope) : Cri::Wasm::ResponseEnvelope
    @last_input = request.input
    effect = JSON.parse(%({"type":"ui.notification","message":"hello from plugin","level":"info"}))
    Cri::Wasm::ResponseEnvelope.new(true, nil, [effect])
  end

  def run(manifest : Cri::Extensions::Manifest, request : Cri::Wasm::RequestEnvelope, handler : Cri::Effects::Handler) : Cri::Wasm::ResponseEnvelope
    response = call(manifest, request)
    result = handler.handle(response.effects.first)
    Cri::Wasm::ResponseEnvelope.new(result.ok, result.result)
  end
end

describe "plugin UI action contract" do
  it "registers a manifest action, serializes UI context, and applies notification" do
    manifest = Cri::Extensions::Manifest.load("examples/extensions/fixture/extension.toml")
    manifest.valid?.should be_true
    runtime = UiNotificationRuntime.new
    invoker = Cri::Extensions::Invoker.new(runtime, capabilities: Cri::API::CapabilityBroker.allow_all)
    ui = Cri::Tui::UiRuntime.new
    bridge = Cri::Extensions::UiActionBridge.new(ui, invoker, [manifest])

    bridge.register_all.should eq(["fixture.notify"])
    ui.actions.dispatch("fixture.notify", Cri::Tui::ActionContext.new(ui, Cri::Tui::KeyEvent.character("x"), "fixture.notify")).should be_true

    runtime.last_input.not_nil!["action"].as_s.should eq("fixture.notify")
    runtime.last_input.not_nil!["focus"]["panel_id"].as_s.should eq("transcript")
    ui.activity.content.should contain("hello from plugin")
  end

  it "rejects malformed notification effects" do
    grants = Cri::Permissions::GrantPolicy.default
    handler = Cri::Effects::Handler.new(grants.for_extension("fixture"), Cri::Permissions::Request.new, capabilities: Cri::API::CapabilityBroker.allow_all)
    effect = JSON.parse(%({"type":"ui.notification","message":"bad","level":"invalid"}))

    result = handler.handle(effect)
    result.ok.should be_false
    result.error.should eq("invalid ui.notification level")
  end

  it "applies owner-scoped buffer and highlight effects" do
    ui = Cri::Tui::UiRuntime.new
    grants = Cri::Permissions::GrantPolicy.default
    handler = Cri::Effects::Handler.new(
      grants.for_extension("fixture"),
      Cri::Permissions::Request.new,
      ui_sink: ui,
      ui_owner: "fixture",
      capabilities: Cri::API::CapabilityBroker.allow_all
    )

    handler.handle(JSON.parse(%({"type":"ui.buffer.create","id":"review","content":"from plugin"}))).ok.should be_true
    handler.handle(JSON.parse(%({"type":"ui.buffer.append","id":"review","content":" + more"}))).ok.should be_true
    handler.handle(JSON.parse(%({"type":"ui.highlight.define","group":"plugin_accent","foreground":45,"bold":true,"underline":false}))).ok.should be_true
    handler.handle(JSON.parse(%({"type":"ui.highlight.set","id":"review","start":0,"finish":4,"group":"plugin_accent"}))).ok.should be_true

    buffer = ui.buffers.get("plugin:fixture:review").as(Cri::Tui::TextBuffer)
    buffer.content.should eq("from plugin + more")
    buffer.highlights.first.group.should eq("plugin:fixture:plugin_accent")
    ui.theme["plugin:fixture:plugin_accent"].not_nil!.foreground.should eq(45)
    ui.theme["plugin:fixture:plugin_accent"].not_nil!.bold.should be_true

    handler.handle(JSON.parse(%({"type":"ui.buffer.replace","id":"review","content":"replaced"}))).ok.should be_true
    buffer.content.should eq("replaced")
    buffer.highlights.should be_empty
  end

  it "opens and focuses an owner-scoped panel" do
    ui = Cri::Tui::UiRuntime.new
    grants = Cri::Permissions::GrantPolicy.default
    handler = Cri::Effects::Handler.new(
      grants.for_extension("fixture"),
      Cri::Permissions::Request.new,
      ui_sink: ui,
      ui_owner: "fixture",
      capabilities: Cri::API::CapabilityBroker.allow_all
    )
    handler.handle(JSON.parse(%({"type":"ui.buffer.create","id":"review","content":"panel"}))).ok.should be_true
    handler.handle(JSON.parse(%({"type":"ui.panel.open","id":"review","buffer_id":"review","title":"Review","position":"right","focus":false}))).ok.should be_true
    handler.handle(JSON.parse(%({"type":"ui.panel.focus","id":"review"}))).ok.should be_true

    ui.workspace.panels.includes?("plugin:fixture:review").should be_true
    ui.workspace.focused_panel_id.should eq("plugin:fixture:review")
  end
end

require "../spec_helper"

{% if flag?(:wasm3) %}
  describe Cri::Wasm::Wasm3Runtime do
    it "loads a raw wasm module and invokes the JSON ABI" do
      manifest = Cri::Extensions::Manifest.load("examples/extensions/fixture/extension.toml")
      request = Cri::Wasm::RequestEnvelope.new("tool", "fixture.echo", JSON.parse(%({"hello":"world"})))
      response = Cri::Wasm::Wasm3Runtime.new.call(manifest, request)

      response.ok.should be_true
      response.effects.should be_empty
    end

    it "executes host effects and resumes the same module" do
      manifest = Cri::Extensions::Manifest.load("examples/extensions/effect_fixture/extension.toml")
      request = Cri::Wasm::RequestEnvelope.new("tool", "effect_fixture.request", JSON.parse("{}"))
      handler = Cri::Effects::Handler.new(Cri::Permissions::GrantSet.default_dev, manifest.permissions, capabilities: Cri::API::CapabilityBroker.allow_all)
      response = Cri::Wasm::Wasm3Runtime.new.run(manifest, request, handler)

      response.ok.should be_true
      response.result.not_nil!["resumed"].as_bool.should be_true
    end

    it "runs a real Zig freestanding plugin" do
      manifest = Cri::Extensions::Manifest.load("examples/extensions/zig_fetch/extension.toml")
      request = Cri::Wasm::RequestEnvelope.new("tool", "zig.fetch", JSON.parse(%({"repo":"octocat/Hello-World","issue":"1"})))
      handler = Cri::Effects::Handler.new(Cri::Permissions::GrantSet.default_dev, manifest.permissions, capabilities: Cri::API::CapabilityBroker.allow_all)
      response = Cri::Wasm::Wasm3Runtime.new.run(manifest, request, handler)

      response.ok.should be_true
      response.result.not_nil!.as_a.first["type"].as_s.should eq("http.request")
    end

    it "runs a real Zig UI action and creates an owner-namespaced buffer" do
      manifest = Cri::Extensions::Manifest.load("examples/extensions/zig_ui_buffer/extension.toml")
      request = Cri::Wasm::RequestEnvelope.new("ui.action", "zig_ui_buffer.create", JSON.parse(%({"action":"zig_ui_buffer.create"})))
      ui = Cri::Tui::UiRuntime.new
      handler = Cri::Effects::Handler.new(
        Cri::Permissions::GrantSet.default_dev,
        manifest.permissions,
        ui_sink: ui,
        ui_owner: manifest.name,
        capabilities: Cri::API::CapabilityBroker.allow_all
      )
      response = Cri::Wasm::Wasm3Runtime.new.run(manifest, request, handler)

      response.ok.should be_true
      buffer = ui.buffers.get("plugin:zig_ui_buffer:review").as(Cri::Tui::TextBuffer)
      buffer.content.should eq("final content")
      buffer.highlights.first.group.should eq("plugin:zig_ui_buffer:plugin_accent")
      ui.theme["plugin:zig_ui_buffer:plugin_accent"].not_nil!.foreground.should eq(45)
      ui.theme["plugin:zig_ui_buffer:plugin_accent"].not_nil!.bold.should be_true
      buffer.highlights.first.start.should eq(0)
      buffer.highlights.first.finish.should eq(5)
      ui.workspace.panels.includes?("plugin:zig_ui_buffer:review").should be_true
      ui.workspace.focused_panel_id.should eq("plugin:zig_ui_buffer:review")
    end
  end
{% end %}

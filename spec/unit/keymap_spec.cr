require "../spec_helper"

class KeymapProvider < Cri::Provider
  def complete(messages : Array(Cri::Message), tools : Array(Cri::ToolSpec)) : Cri::AssistantResponse
    Cri::AssistantResponse.new("ok")
  end
end

describe Cri::Tui::Keymap do
  it "resolves modal multi-key sequences" do
    keymap = Cri::Tui::Keymap.new
    keymap.bind(Cri::Tui::Mode::Normal, "ctrl-w l", "panel.focus_right")

    keymap.resolve(Cri::Tui::Mode::Normal, Cri::Tui::KeyEvent.new(Cri::Tui::Key::CtrlW)).kind.should eq(Cri::Tui::KeyMatchKind::Prefix)
    match = keymap.resolve(Cri::Tui::Mode::Normal, Cri::Tui::KeyEvent.character("l"))
    match.kind.should eq(Cri::Tui::KeyMatchKind::Action)
    match.action.should eq("panel.focus_right")
  end

  it "supports rebinding and unbinding without changing event handling" do
    keymap = Cri::Tui::Keymap.new
    keymap.bind(Cri::Tui::Mode::Normal, "x", "panel.focus_right")
    keymap.resolve(Cri::Tui::Mode::Normal, Cri::Tui::KeyEvent.character("x")).action.should eq("panel.focus_right")
    keymap.bind(Cri::Tui::Mode::Normal, "x", "panel.focus_left")
    keymap.resolve(Cri::Tui::Mode::Normal, Cri::Tui::KeyEvent.character("x")).action.should eq("panel.focus_left")
    keymap.unbind(Cri::Tui::Mode::Normal, "x")
    keymap.resolve(Cri::Tui::Mode::Normal, Cri::Tui::KeyEvent.character("x")).kind.should eq(Cri::Tui::KeyMatchKind::None)
  end

  it "uses wildcard input only in editable modes" do
    keymap = Cri::Tui::Keymap.new
    keymap.bind(Cri::Tui::Mode::Insert, "<char>", "input.insert")
    keymap.resolve(Cri::Tui::Mode::Insert, Cri::Tui::KeyEvent.character("і")).action.should eq("input.insert")
    keymap.resolve(Cri::Tui::Mode::Normal, Cri::Tui::KeyEvent.character("і")).kind.should eq(Cri::Tui::KeyMatchKind::None)
  end
end

describe "Keymap actions" do
  it "runs registered host-side UI actions with an ergonomic context API" do
    ui = Cri::Tui::UiRuntime.new
    ui.keymap.bind(Cri::Tui::Mode::Normal, "g", "extension.git.open")
    ui.actions.register("extension.git.open") do |context|
      context.ui.set_activity("opened by #{context.event.token}\n", "activity")
    end
    ui.focused_buffer.not_nil!.mode = Cri::Tui::Mode::Normal
    handler = Cri::Tui::EventHandler.new(ui, Cri::Tui::Controller.new(Cri::Host.new, KeymapProvider.new))

    handler.handle(Cri::Tui::KeyEvent.character("g")) {}
    ui.activity.content.should eq("opened by g\n")
  end

  it "emits unhandled actions through the global UI event bus" do
    ui = Cri::Tui::UiRuntime.new
    received = ""
    ui.subscribe("ui.keymap.action") { |event| received = event.data["action"].as_s }
    ui.keymap.bind(Cri::Tui::Mode::Normal, "g", "extension.git.open")
    ui.focused_buffer.not_nil!.mode = Cri::Tui::Mode::Normal
    handler = Cri::Tui::EventHandler.new(ui, Cri::Tui::Controller.new(Cri::Host.new, KeymapProvider.new))

    handler.handle(Cri::Tui::KeyEvent.character("g")) {}
    received.should eq("extension.git.open")
  end
end

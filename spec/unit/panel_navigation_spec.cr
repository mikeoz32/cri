require "../spec_helper"

class NavigationProvider < Cri::Provider
  def complete(messages : Array(Cri::Message), tools : Array(Cri::ToolSpec)) : Cri::AssistantResponse
    Cri::AssistantResponse.new("ok")
  end
end

describe "Ctrl-W panel navigation" do
  it "moves focus between main and right panels" do
    ui = Cri::Tui::UiRuntime.new
    ui.focused_buffer.not_nil!.mode = Cri::Tui::Mode::Normal
    handler = Cri::Tui::EventHandler.new(ui, Cri::Tui::Controller.new(Cri::Host.new, NavigationProvider.new))

    handler.handle(Cri::Tui::KeyEvent.new(Cri::Tui::Key::CtrlW)) {}
    handler.handle(Cri::Tui::KeyEvent.character("l")) {}
    ui.workspace.focused_panel_id.should eq("activity")

    handler.handle(Cri::Tui::KeyEvent.new(Cri::Tui::Key::CtrlW)) {}
    handler.handle(Cri::Tui::KeyEvent.character("h")) {}
    ui.workspace.focused_panel_id.should eq("transcript")
  end

  it "focuses the bottom prompt through Ctrl-W j" do
    ui = Cri::Tui::UiRuntime.new
    ui.focused_buffer.not_nil!.mode = Cri::Tui::Mode::Normal
    handler = Cri::Tui::EventHandler.new(ui, Cri::Tui::Controller.new(Cri::Host.new, NavigationProvider.new))

    handler.handle(Cri::Tui::KeyEvent.new(Cri::Tui::Key::CtrlW)) {}
    handler.handle(Cri::Tui::KeyEvent.character("j")) {}
    ui.workspace.focused_panel_id.should eq("input")
  end

  it "treats an incomplete Ctrl-W sequence as a no-op" do
    ui = Cri::Tui::UiRuntime.new
    ui.focused_buffer.not_nil!.mode = Cri::Tui::Mode::Normal
    handler = Cri::Tui::EventHandler.new(ui, Cri::Tui::Controller.new(Cri::Host.new, NavigationProvider.new))

    handler.handle(Cri::Tui::KeyEvent.new(Cri::Tui::Key::CtrlW)) {}
    handler.handle(Cri::Tui::KeyEvent.character("x")) {}
    ui.workspace.focused_panel_id.should eq("transcript")
  end
end

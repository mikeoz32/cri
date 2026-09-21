require "../spec_helper"

describe "Buffer-local modes" do
  it "keeps buffer modes independent of focus" do
    ui = Cri::Tui::UiRuntime.new
    transcript = ui.transcript
    input = ui.input

    transcript.mode.should eq(Cri::Tui::Mode::Normal)
    input.mode.should eq(Cri::Tui::Mode::Normal)
    ui.workspace.focus("input")
    ui.begin_insert.should be_true
    ui.mode.should eq(Cri::Tui::Mode::Insert)
    transcript.mode.should eq(Cri::Tui::Mode::Normal)
    input.mode.should eq(Cri::Tui::Mode::Insert)
    ui.workspace.focus("transcript")

    ui.mode.should eq(Cri::Tui::Mode::Normal)
    input.mode.should eq(Cri::Tui::Mode::Insert)
  end

  it "keeps an extension buffer mode when another panel becomes focused" do
    ui = Cri::Tui::UiRuntime.new
    buffer = ui.create_text_panel("review", "Review")
    panel = ui.workspace.panels.get("review")
    ui.workspace.focus(panel.id)
    buffer.mode = Cri::Tui::Mode::Insert
    ui.workspace.focus("transcript")

    buffer.mode.should eq(Cri::Tui::Mode::Insert)
    ui.mode.should eq(Cri::Tui::Mode::Normal)
  end

  it "does not enter insert mode for a read-only focused panel" do
    ui = Cri::Tui::UiRuntime.new
    ui.workspace.focus("transcript")
    ui.begin_insert.should be_false
    ui.mode.should eq(Cri::Tui::Mode::Normal)
  end
end

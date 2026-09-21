require "../spec_helper"

describe Cri::Tui::UiRuntime do
  it "owns buffers while Workspace owns panels" do
    ui = Cri::Tui::UiRuntime.new
    buffer = ui.create_text_panel("diagnostics", "Diagnostics", "right")
    buffer.append("line one\nline two")

    panel = ui.workspace.panels.get("diagnostics")
    panel.buffer_id.should eq("panel:diagnostics")
    ui.buffers.get(panel.buffer_id).lines.should eq(["line one", "line two"])
    ui.workspace.panels.all.map(&.buffer_id).should_not contain("diagnostics")
  end

  it "keeps cursor state on the buffer" do
    ui = Cri::Tui::UiRuntime.new
    ui.input.insert("abc")
    ui.input.backspace

    ui.input.cursor.should eq(2)
    ui.input.content.should eq("ab")
  end

  it "publishes buffer changes on the global event bus" do
    ui = Cri::Tui::UiRuntime.new
    sources = [] of String
    ui.subscribe("buffer.changed") { |event| sources << event.source.not_nil! }

    ui.input.insert("x")

    sources.should contain("input")
  end
end

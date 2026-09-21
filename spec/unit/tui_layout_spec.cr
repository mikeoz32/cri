require "../spec_helper"

describe Cri::Tui::Renderer do
  it "uses mode-specific terminal cursor shapes" do
    ui = Cri::Tui::UiRuntime.new
    renderer = Cri::Tui::Renderer.new(ui.workspace, ui.buffers, 80, 12, ui.theme)

    ui.focused_buffer.not_nil!.mode = Cri::Tui::Mode::Normal
    renderer.cursor_shape.should eq("\e[2 q")
    ui.workspace.focus("input")
    ui.begin_insert
    renderer.cursor_shape.should eq("\e[6 q")
    ui.begin_command
    renderer.cursor_shape.should eq("\e[4 q")
  end

  it "fills each requested terminal row with a main/right/bottom layout" do
    ui = Cri::Tui::UiRuntime.new
    ui.transcript.append("hello\n")
    ui.set_activity("working\n", "activity")
    frame = Cri::Tui::Renderer.new(ui.workspace, ui.buffers, 90, 18, ui.theme).frame

    frame.size.should eq(18)
    frame[0].should contain("cri")
    frame[1].should eq("─" * 90)
    frame[-2].should eq("─" * 90)
    frame[-1].should start_with("> ")
    frame.join.should contain("Conversation")
    frame.join.should contain("Activity")
  end

  it "stacks right panels when terminal width is narrow" do
    ui = Cri::Tui::UiRuntime.new
    frame = Cri::Tui::Renderer.new(ui.workspace, ui.buffers, 40, 12, ui.theme).frame

    frame.size.should eq(12)
    frame.join.should contain("Conversation")
    frame.join.should contain("Activity")
  end
end

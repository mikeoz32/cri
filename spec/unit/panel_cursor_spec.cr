require "../spec_helper"

describe "Panel cursor rendering" do
  it "locates the cursor in the focused read-only panel rather than Prompt" do
    ui = Cri::Tui::UiRuntime.new
    renderer = Cri::Tui::Renderer.new(ui.workspace, ui.buffers, 80, 20)

    renderer.cursor_screen_position.should eq({4, 1})
    ui.workspace.focus("activity")
    renderer.cursor_screen_position.should eq({5, 55})
  end

  it "places the prompt cursor only while Prompt is focused" do
    ui = Cri::Tui::UiRuntime.new
    renderer = Cri::Tui::Renderer.new(ui.workspace, ui.buffers, 80, 20)

    ui.workspace.focus("input")
    renderer.cursor_screen_position.should eq({20, 3})
    ui.workspace.focus("transcript")
    renderer.cursor_screen_position.should eq({4, 1})
  end
end

describe Cri::Tui::TextBuffer do
  it "moves its cursor vertically without changing read-only status" do
    buffer = Cri::Tui::TextBuffer.new("notes", "one\ntwo\nthree")
    buffer.cursor = 5
    buffer.move_vertical(1)
    buffer.cursor_line_column.should eq({2, 1})
    buffer.move_vertical(-1)
    buffer.cursor_line_column.should eq({1, 1})
  end
end

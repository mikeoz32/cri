require "../spec_helper"

describe Cri::Tui::TextBuffer do
  it "handles empty and multiline content" do
    buffer = Cri::Tui::TextBuffer.new("test")
    buffer.lines.should eq([""])
    buffer.replace("one\ntwo\n")
    buffer.lines.should eq(["one", "two", ""])
  end

  it "does not backspace before the start" do
    buffer = Cri::Tui::TextBuffer.new("test")
    buffer.backspace
    buffer.content.should eq("")
  end
end

describe Cri::Tui::Panel do
  it "clamps scroll to available content" do
    buffers = Cri::Tui::BufferStore.new
    buffer = buffers.text("log", "one\ntwo\nthree")
    panel = Cri::Tui::Panel.new("log-panel", buffer.id, "Log")
    panel.scroll_by(100)

    panel.render_lines(buffers, 2, 80).should eq(["one", "two"])
  end
end

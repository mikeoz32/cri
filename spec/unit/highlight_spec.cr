require "../spec_helper"

describe "Buffer highlights" do
  it "keeps styles separate from text and emits invalidation" do
    ui = Cri::Tui::UiRuntime.new
    buffer = ui.create_buffer("source", "привіт")
    changes = 0
    ui.subscribe("buffer.changed") { |_| changes += 1 }
    buffer.highlight(0, 3, "keyword")
    buffer.content.should eq("привіт")
    buffer.cursor.should eq(6)
    changes.should eq(1)
    detached = buffer.highlights
    detached.clear
    buffer.highlights.size.should eq(1)
  end

  it "rejects empty, negative and out of bounds ranges" do
    buffer = Cri::Tui::TextBuffer.new("test", "abc")
    [{-1, 1}, {1, 1}, {0, 4}].each do |range|
      expect_raises(ArgumentError) { buffer.highlight(range[0], range[1], "error") }
    end
    expect_raises(ArgumentError) { buffer.highlight(0, 1, "") }
  end

  it "publishes arbitrary UI events to Application subscribers" do
    ui = Cri::Tui::UiRuntime.new
    received = [] of String
    ui.subscribe_all { |event| received << event.name }
    ui.events.emit(Cri::Event.new("extension.panel.updated"))
    received.should contain("extension.panel.updated")
  end

  it "invalidates stale highlights on editing but preserves them on append" do
    buffer = Cri::Tui::TextBuffer.new("test", "abc")
    buffer.highlight(0, 2, "error")
    buffer.append("def")
    buffer.highlights.size.should eq(1)
    buffer.insert("x")
    buffer.highlights.should be_empty
    buffer.highlight(0, 2, "error")
    buffer.backspace
    buffer.highlights.should be_empty
    buffer.highlight(0, 2, "error")
    buffer.replace("new")
    buffer.highlights.should be_empty
  end

  it "uses last-added region precedence and resets ANSI at line boundaries" do
    regions = [Cri::Tui::Highlight.new(0, 3, "error"), Cri::Tui::Highlight.new(1, 2, "accent")]
    theme = Cri::Tui::Theme.new
    result = Cri::Tui::HighlightRenderer.line("abc", 0, regions, 3, theme)
    result.should eq(theme["error"].not_nil!.ansi + "a" + theme["accent"].not_nil!.ansi + "b" + theme["error"].not_nil!.ansi + "c\e[0m")
    Cri::Tui::HighlightRenderer.line("abc", 0, regions, 0, theme).should eq("")
  end

  it "accounts for newlines and viewport offsets for a shared buffer" do
    buffers = Cri::Tui::BufferStore.new
    buffer = buffers.text("shared", "one\nдва\nthree")
    buffer.highlight(4, 7, "keyword")
    a = Cri::Tui::Panel.new("a", buffer.id, "A")
    b = Cri::Tui::Panel.new("b", buffer.id, "B")
    a.render_lines(buffers, 2, 2, Cri::Tui::Theme.new).first.should contain("дв\e[0m")
    b.scroll_by(1)
    b.render_lines(buffers, 2, 80, Cri::Tui::Theme.new).should eq(["one", Cri::Tui::Theme.new["keyword"].not_nil!.ansi + "два\e[0m"])
  end

  it "renders unknown groups as plain text without interpreting control bytes" do
    regions = [Cri::Tui::Highlight.new(0, 10, "missing")]
    Cri::Tui::HighlightRenderer.line("a\eb\ac", 0, regions, 3, Cri::Tui::Theme.new).should eq("abc")
  end

  it "renders Visual selection with the selection style" do
    theme = Cri::Tui::Theme.new
    result = Cri::Tui::HighlightRenderer.line("abc", 0, [] of Cri::Tui::Highlight, 3, theme, 1...3)
    result.should contain(theme["selection"].not_nil!.ansi)
    result.should contain("bc")
  end

  it "only includes ANSI when rendering a styled frame" do
    ui = Cri::Tui::UiRuntime.new
    ui.transcript.replace("failure")
    ui.transcript.highlight(0, 7, "error")
    renderer = Cri::Tui::Renderer.new(ui.workspace, ui.buffers)
    renderer.frame.join.includes?('\e').should be_false
    renderer.frame(true).join.should contain("\e[0;38;5;196;1m")
  end
end

require "../spec_helper"

class BufferMotionTestProvider < Cri::Provider
  def complete(messages : Array(Cri::Message), tools : Array(Cri::ToolSpec)) : Cri::AssistantResponse
    Cri::AssistantResponse.new("ok")
  end
end

describe Cri::Tui::TextBuffer do
  it "moves and deletes whole grapheme clusters" do
    buffer = Cri::Tui::TextBuffer.new("text", "A👍🏻éZ")
    buffer.cursor = 1

    buffer.move_right
    buffer.cursor.should eq(1 + "👍🏻".size)
    buffer.move_right
    buffer.cursor.should eq(1 + "👍🏻".size + "é".size)
    buffer.move_left
    buffer.cursor.should eq(1 + "👍🏻".size)

    buffer.cursor = 2 # Inside the skin-tone emoji cluster.
    buffer.cursor.should eq(1)
    buffer.cursor = 1 + "👍🏻".size
    buffer.backspace
    buffer.content.should eq("AéZ")
    buffer.cursor.should eq(1)
  end

  it "moves to line boundaries and preserves the terminal column vertically" do
    buffer = Cri::Tui::TextBuffer.new("text", "  wide😀\na😀x")

    buffer.cursor = 0
    buffer.move_first_nonblank
    buffer.cursor.should eq(2)
    buffer.move_line_end
    buffer.cursor.should eq(6)

    buffer.cursor = 10 # After the emoji on the second line (cell column 3).
    buffer.move_line_start
    buffer.cursor.should eq(8)
    buffer.cursor = 10
    buffer.move_vertical(-1)
    buffer.cursor_line_column.should eq({0, 3})
    buffer.move_line_end
    buffer.cursor.should eq(6)
  end

  it "moves over Unicode words and punctuation" do
    buffer = Cri::Tui::TextBuffer.new("text", "привіт, 世界!")
    buffer.cursor = 0

    buffer.move_word_forward
    buffer.cursor.should eq("привіт".size)
    buffer.move_word_forward
    buffer.cursor.should eq("привіт, ".size)
    buffer.move_word_end
    buffer.cursor.should eq("привіт, 世界".size - 1)
    buffer.move_word_backward
    buffer.cursor.should eq("привіт, ".size)
  end

  it "moves to the first and last grapheme in the buffer" do
    buffer = Cri::Tui::TextBuffer.new("text", "first\nlast😀")

    buffer.move_document_start
    buffer.cursor.should eq(0)
    buffer.move_document_end
    buffer.cursor.should eq("first\nlast".size)
  end
end

describe "Vim-like buffer movement bindings" do
  it "binds gg and case-sensitive G, and keeps movements active in Visual mode" do
    ui = Cri::Tui::UiRuntime.new
    handler = Cri::Tui::EventHandler.new(ui, Cri::Tui::Controller.new(Cri::Host.new, BufferMotionTestProvider.new))
    buffer = ui.transcript
    buffer.replace("one two\nthree")
    buffer.cursor = buffer.content.size

    handler.handle(Cri::Tui::KeyEvent.character("g")) { }
    buffer.cursor.should eq(buffer.content.size)
    handler.handle(Cri::Tui::KeyEvent.character("g")) { }
    buffer.cursor.should eq(0)

    handler.handle(Cri::Tui::KeyEvent.character("G")) { }
    buffer.cursor.should eq("one two\nthre".size)

    buffer.cursor = 0
    handler.handle(Cri::Tui::KeyEvent.character("v")) { }
    buffer.mode.should eq(Cri::Tui::Mode::Visual)
    handler.handle(Cri::Tui::KeyEvent.character("w")) { }
    buffer.selected_text.should eq("one t")
    handler.handle(Cri::Tui::KeyEvent.new(Cri::Tui::Key::Escape)) { }
    buffer.mode.should eq(Cri::Tui::Mode::Normal)
    buffer.selection_range.should be_nil
  end
end

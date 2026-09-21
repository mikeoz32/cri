require "../spec_helper"

class VimTestProvider < Cri::Provider
  def complete(messages : Array(Cri::Message), tools : Array(Cri::ToolSpec)) : Cri::AssistantResponse
    Cri::AssistantResponse.new("ok")
  end
end

describe "Simplified Vim UI regressions" do
  it "leaves q and Tab unbound and exits with :q" do
    ui = Cri::Tui::UiRuntime.new
    controller = Cri::Tui::Controller.new(Cri::Host.new, VimTestProvider.new)
    handler = Cri::Tui::EventHandler.new(ui, controller)
    ui.focused_buffer.not_nil!.mode = Cri::Tui::Mode::Normal
    handler.handle(Cri::Tui::KeyEvent.character("q")) { }.should be_true
    handler.handle(Cri::Tui::KeyEvent.new(Cri::Tui::Key::Tab)) { }.should be_true
    handler.handle(Cri::Tui::KeyEvent.character(":")) { }
    handler.handle(Cri::Tui::KeyEvent.character("q")) { }
    handler.handle(Cri::Tui::KeyEvent.new(Cri::Tui::Key::Enter)) { }.should be_false
  end

  it "edits Ukrainian characters without mixing byte and character offsets" do
    buffer = Cri::Tui::TextBuffer.new("test", "привіт")
    buffer.backspace
    buffer.content.should eq("приві")
    buffer.cursor = 2
    buffer.insert("🙂")
    buffer.content.should eq("пр🙂иві")
    buffer.backspace
    buffer.content.should eq("приві")
  end

  it "decodes UTF-8 and preserves the key following Escape" do
    decoder = Cri::Tui::KeyDecoder.new(IO::Memory.new("\eі"))
    decoder.next_event.not_nil!.key.should eq(Cri::Tui::Key::Escape)
    decoder.next_event.not_nil!.value.should eq("і")
  end

  it "decodes Ctrl-E and Ctrl-Y into reachable scroll actions" do
    decoder = Cri::Tui::KeyDecoder.new(IO::Memory.new("\u0005\u0019"))
    first = decoder.next_event.not_nil!
    second = decoder.next_event.not_nil!
    first.key.should eq(Cri::Tui::Key::CtrlE)
    first.token.should eq("ctrl-e")
    second.key.should eq(Cri::Tui::Key::CtrlY)
    second.token.should eq("ctrl-y")
  end

  it "does not submit the Prompt from another editable panel" do
    ui = Cri::Tui::UiRuntime.new
    controller = Cri::Tui::Controller.new(Cri::Host.new, VimTestProvider.new)
    handler = Cri::Tui::EventHandler.new(ui, controller)
    editor = ui.create_text_panel("editor", "Editor")
    ui.workspace.focus("editor")
    handler.handle(Cri::Tui::KeyEvent.character("i")) { }
    editor.insert("draft")
    ui.input.insert("pending")

    handler.handle(Cri::Tui::KeyEvent.new(Cri::Tui::Key::Enter)) { }

    editor.content.should eq("draft")
    ui.input.content.should eq("pending")
    ui.workspace.focused_panel_id.should eq("editor")
  end

  it "dispatches decoded Ctrl-Y and Ctrl-E to the focused panel" do
    ui = Cri::Tui::UiRuntime.new
    controller = Cri::Tui::Controller.new(Cri::Host.new, VimTestProvider.new)
    handler = Cri::Tui::EventHandler.new(ui, controller)
    panel = ui.workspace.panels.get("transcript")

    decoder = Cri::Tui::KeyDecoder.new(IO::Memory.new("\u0019\u0005"))
    handler.handle(decoder.next_event.not_nil!) { }
    panel.scroll.should eq(1)
    handler.handle(decoder.next_event.not_nil!) { }
    panel.scroll.should eq(0)
  end

  it "keeps the focused cursor visible while scrolling a text panel" do
    buffers = Cri::Tui::BufferStore.new
    buffer = buffers.text("long", (0...10).map { |index| "line#{index}" }.join("\n"))
    panel = Cri::Tui::Panel.new("long", buffer.id, "Long")

    buffer.cursor = 0
    panel.render_lines(buffers, 3, 80)
    panel.scroll.should eq(7)
    buffer.cursor = buffer.content.size
    panel.render_lines(buffers, 3, 80)
    panel.scroll.should eq(0)
  end

  it "selects and yanks text through Visual mode" do
    ui = Cri::Tui::UiRuntime.new
    controller = Cri::Tui::Controller.new(Cri::Host.new, VimTestProvider.new)
    handler = Cri::Tui::EventHandler.new(ui, controller)
    ui.transcript.replace("abc")
    ui.transcript.cursor = 0

    handler.handle(Cri::Tui::KeyEvent.character("v")) { }
    handler.handle(Cri::Tui::KeyEvent.character("l")) { }
    ui.transcript.mode.should eq(Cri::Tui::Mode::Visual)
    ui.transcript.selected_text.should eq("ab")
    handler.handle(Cri::Tui::KeyEvent.character("y")) { }

    ui.clipboard.as(Cri::Tui::MemoryClipboard).content.should eq("ab")
    ui.transcript.mode.should eq(Cri::Tui::Mode::Normal)
    ui.transcript.selection_range.should be_nil
  end

  it "renders empty workspaces and narrow screens safely" do
    ui = Cri::Tui::UiRuntime.new
    ui.create_workspace("empty")
    ui.activate_workspace("empty")
    frame = Cri::Tui::Renderer.new(ui.workspace, ui.buffers, 5, 3).frame
    frame.size.should eq(5)
    frame.all? { |line| line.size <= 5 }.should be_true
  end

  it "strips terminal control bytes from buffer text" do
    ui = Cri::Tui::UiRuntime.new
    ui.transcript.replace("hello\e]52;c;evil\a")
    frame = Cri::Tui::Renderer.new(ui.workspace, ui.buffers).frame.join
    frame.includes?('\e').should be_false
    frame.includes?('\a').should be_false
  end

  it "does not force-delete buffers referenced by panels" do
    ui = Cri::Tui::UiRuntime.new
    ui.close_buffer("input", force: true).should be_false
  end
end

require "../spec_helper"

class UiEventNoopProvider < Cri::Provider
  def complete(messages : Array(Cri::Message), tools : Array(Cri::ToolSpec)) : Cri::AssistantResponse
    Cri::AssistantResponse.new("noop")
  end
end

class UiEventSlowProvider < Cri::Provider
  def complete(messages : Array(Cri::Message), tools : Array(Cri::ToolSpec)) : Cri::AssistantResponse
    sleep 20.milliseconds
    Cri::AssistantResponse.new("async response")
  end
end

describe Cri::Tui::EventHandler do
  it "edits the prompt buffer in insert mode and restores focused panel" do
    ui = Cri::Tui::UiRuntime.new
    controller = Cri::Tui::Controller.new(Cri::Host.new, UiEventNoopProvider.new)
    handler = Cri::Tui::EventHandler.new(ui, controller)

    ui.mode.should eq(Cri::Tui::Mode::Normal)
    ui.workspace.focus("input")
    handler.handle(Cri::Tui::KeyEvent.character("i")) { }
    ui.mode.should eq(Cri::Tui::Mode::Insert)
    handler.handle(Cri::Tui::KeyEvent.character("h")) { }
    ui.input.content.should eq("h")
    handler.handle(Cri::Tui::KeyEvent.new(Cri::Tui::Key::Escape)) { }
    ui.mode.should eq(Cri::Tui::Mode::Normal)
    ui.workspace.focused_panel_id.should eq("input")
  end

  it "returns control to input while a model request is running" do
    ui = Cri::Tui::UiRuntime.new
    controller = Cri::Tui::Controller.new(Cri::Host.new, UiEventSlowProvider.new)
    handler = Cri::Tui::EventHandler.new(ui, controller)

    ui.workspace.focus("input")
    handler.handle(Cri::Tui::KeyEvent.character("i")) { }
    handler.handle(Cri::Tui::KeyEvent.character("h")) { }
    handler.handle(Cri::Tui::KeyEvent.new(Cri::Tui::Key::Enter)) { }.should be_true
    sleep 50.milliseconds

    ui.transcript.content.should contain("async response")
    ui.workspace.status.should eq("ready")
  end

  it "routes command mode through the controller" do
    ui = Cri::Tui::UiRuntime.new
    controller = Cri::Tui::Controller.new(Cri::Host.new, UiEventNoopProvider.new)
    handler = Cri::Tui::EventHandler.new(ui, controller)

    handler.handle(Cri::Tui::KeyEvent.character(":")) { }
    "session".each_char { |char| handler.handle(Cri::Tui::KeyEvent.character(char.to_s)) { } }
    handler.handle(Cri::Tui::KeyEvent.new(Cri::Tui::Key::Enter)) { }

    ui.mode.should eq(Cri::Tui::Mode::Normal)
    ui.transcript.content.should contain("session:")
  end

  it "collects API tokens in a masked TUI prompt without transcript leakage" do
    ui = Cri::Tui::UiRuntime.new
    auth = Cri::Auth::Broker.new(Cri::Auth::MemoryCredentialStore.new)
    host = Cri::Host.new(auth: auth)
    controller = Cri::Tui::Controller.new(host, UiEventNoopProvider.new)
    handler = Cri::Tui::EventHandler.new(ui, controller)

    handler.handle(Cri::Tui::KeyEvent.character(":")) { }
    "auth login openai-api".each_char { |char| handler.handle(Cri::Tui::KeyEvent.character(char.to_s)) { } }
    handler.handle(Cri::Tui::KeyEvent.new(Cri::Tui::Key::Enter)) { }
    ui.input.masked.should be_true
    "secret-token".each_char { |char| handler.handle(Cri::Tui::KeyEvent.character(char.to_s)) { } }
    handler.handle(Cri::Tui::KeyEvent.new(Cri::Tui::Key::Enter)) { }
    sleep 10.milliseconds

    auth.existing("openai-api", "api-key").should_not be_nil
    ui.transcript.content.should_not contain("secret-token")
    ui.input.content.should be_empty
    ui.input.masked.should be_false
  end
end

describe Cri::Tui::KeyDecoder do
  it "decodes arrow escape sequences" do
    input = IO::Memory.new("[A")
    event = Cri::Tui::KeyDecoder.new(input).decode(27_u8)
    event.not_nil!.key.should eq(Cri::Tui::Key::Up)
  end
end

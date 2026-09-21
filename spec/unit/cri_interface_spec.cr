require "../spec_helper"

describe "cri default interface" do
  it "builds conversation, activity and prompt panels from runtime buffers" do
    ui = Cri::Tui::UiRuntime.new
    panels = ui.workspace.panels.all

    panels.map(&.id).should eq(["transcript", "activity", "input"])
    panels.map(&.buffer_id).should eq(["transcript", "activity", "input"])
    ui.activity.content.should eq("ready\n")
  end

  it "writes semantic transcript styles without ANSI in buffers" do
    ui = Cri::Tui::UiRuntime.new
    ui.append_transcript("> hello\n", "user")
    ui.append_transcript("assistant: hi\n", "assistant")

    ui.transcript.content.should eq("> hello\nassistant: hi\n")
    ui.transcript.highlights.map(&.group).should eq(["user", "assistant"])
    ui.transcript.content.includes?('\e').should be_false
  end

  it "renders activity in a right column on a normal terminal" do
    ui = Cri::Tui::UiRuntime.new
    ui.set_activity("thinking…\n", "activity")
    frame = Cri::Tui::Renderer.new(ui.workspace, ui.buffers, 80, 10, ui.theme).frame(true)

    frame.join.should contain("Conversation")
    frame.join.should contain("Activity")
    frame.join.should contain("thinking")
  end
end

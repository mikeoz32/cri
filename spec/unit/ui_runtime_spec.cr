require "../spec_helper"

describe Cri::Tui::UiRuntime do
  it "keeps persistent buffers after panel removal" do
    ui = Cri::Tui::UiRuntime.new
    ui.workspace.remove_panel("transcript")

    ui.close_buffer("transcript").should be_false
    ui.buffers.includes?("transcript").should be_true
  end

  it "does not close a buffer while a panel references it" do
    ui = Cri::Tui::UiRuntime.new
    buffer = ui.create_text_panel("logs", "Logs")

    ui.close_buffer(buffer.id).should be_false
    ui.buffers.includes?(buffer.id).should be_true

    ui.workspace.remove_panel("logs")
    ui.close_buffer(buffer.id).should be_true
    ui.buffers.includes?(buffer.id).should be_false
  end

  it "keeps buffers when switching workspaces" do
    ui = Cri::Tui::UiRuntime.new
    buffer = ui.create_text_panel("shared", "Shared")
    secondary = ui.create_workspace("secondary")
    secondary.add_panel("shared-view", buffer.id, "Shared", "main", true)

    ui.activate_workspace("secondary")
    ui.buffers.get(buffer.id).should eq(buffer)
    ui.workspace.id.should eq("secondary")
  end

  it "rejects a panel that references an unknown buffer" do
    ui = Cri::Tui::UiRuntime.new
    expect_raises(Exception, /unknown buffer/) do
      ui.workspace.add_panel("broken", "missing", "Broken")
    end
    ui.workspace.panels.includes?("broken").should be_false
  end

  it "does not leave an orphan buffer when a panel ID collides" do
    ui = Cri::Tui::UiRuntime.new
    ui.create_text_panel("logs", "Logs")

    expect_raises(Exception, /panel already exists/) do
      ui.create_text_panel("logs", "Logs again")
    end
    ui.buffers.all.count { |buffer| buffer.id == "panel:logs" }.should eq(1)
  end

  it "moves focus when the focused panel is removed" do
    ui = Cri::Tui::UiRuntime.new
    ui.workspace.focus("activity")
    ui.workspace.remove_panel("activity").should_not be_nil
    ui.workspace.focused_panel_id.should eq("transcript")
  end
end

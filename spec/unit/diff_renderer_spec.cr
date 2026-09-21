require "../spec_helper"

describe "Incremental terminal renderer" do
  it "redraws only the changed prompt row after text input" do
    ui = Cri::Tui::UiRuntime.new
    renderer = Cri::Tui::Renderer.new(ui.workspace, ui.buffers, 80, 12, ui.theme)
    renderer.changed_rows.size.should eq(12)
    renderer.commit

    ui.input.insert("x")
    renderer.changed_rows.should eq([12])
  end

  it "redraws the header when the mode changes" do
    ui = Cri::Tui::UiRuntime.new
    renderer = Cri::Tui::Renderer.new(ui.workspace, ui.buffers, 80, 12, ui.theme)
    renderer.commit

    ui.workspace.focus("input")
    ui.begin_insert
    renderer.changed_rows.should eq([1, 3])
  end

  it "forces a full frame after a resize" do
    ui = Cri::Tui::UiRuntime.new
    renderer = Cri::Tui::Renderer.new(ui.workspace, ui.buffers, 80, 12, ui.theme)
    renderer.commit
    renderer.resize(100, 20)

    renderer.changed_rows.should eq((1..20).to_a.map(&.to_i32))
  end
end

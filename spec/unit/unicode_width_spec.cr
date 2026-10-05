require "../spec_helper"

describe Cri::Tui::CellWidth do
  it "measures emoji grapheme clusters in terminal cells" do
    widths = {
      "😀"          => 2,
      "🐈"          => 2,
      "☕"          => 2,
      "⭐"          => 2,
      "👍🏻"         => 2,
      "👩‍💻"        => 2,
      "👨‍👩‍👧‍👦" => 2,
      "🏳️‍🌈"       => 2,
      "🇺🇦"          => 2,
      "0️⃣"          => 2,
      "❤"           => 1,
      "❤️"          => 2,
      "☺"           => 1,
      "☺️"          => 2,
      "✈"           => 1,
      "✈️"          => 2,
      "☀"           => 1,
      "☀️"          => 2,
      "é"           => 1,
      "שלום עולם"     => 9,
      "שָׁלוֹם עוֹלָם" => 9,
      "नमस्ते दुनिया" => 10,
      "← ↑ → ↓ ↔ ↕ ↖ ↗ ↘ ↙ ⇒ ⇔ ➜ ➤" => 27,
    }

    widths.each do |text, expected|
      Cri::Tui::CellWidth.of(text).should eq(expected)
    end
  end

  it "wraps at grapheme boundaries using terminal cell width" do
    buffers = Cri::Tui::BufferStore.new
    buffer = buffers.text("emoji", "👍🏻👩‍💻🇺🇦0️⃣")
    panel = Cri::Tui::Panel.new("emoji", buffer.id, "Emoji")

    lines = panel.render_lines(buffers, 8, 3)

    lines.should eq(["👍🏻", "👩‍💻", "🇺🇦", "0️⃣"])
  end

  it "keeps every two-panel frame row at the terminal width" do
    ui = Cri::Tui::UiRuntime.new
    ui.transcript.replace([
      "😀 😅 😂 🥹 😎 🤔 🫠 😴 🤖 👻 💩",
      "👍 👍🏻 👍🏼 👍🏽 👍🏾 👍🏿",
      "👩‍💻 👨‍🔧 🧑‍🚀 👨‍👩‍👧‍👦 🏳️‍🌈",
      "🇺🇦 🇵🇱 🇯🇵 🇺🇸 🇪🇺",
      "0️⃣ 1️⃣ 2️⃣ #️⃣ *️⃣",
      "❤ ❤️ ☺ ☺️ ✈ ✈️ ☀ ☀️",
      "שלום עולם",
      "नमस्ते दुनिया",
      "← ↑ → ↓ ↔ ↕ ↖ ↗ ↘ ↙ ⇒ ⇔ ➜ ➤",
    ].join("\n"))

    frame = Cri::Tui::Renderer.new(ui.workspace, ui.buffers, 90, 18, ui.theme).frame

    frame[2...15].each do |row|
      Cri::Tui::CellWidth.of(row).should eq(90)
    end
  end
end

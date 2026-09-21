# TUI

Interactive terminals use `Tui::Application`; pipes use the line shell.
`UiRuntime` owns buffers, workspaces and an application-scoped EventBus.
Buffers own content, a character-index cursor, and named highlight regions; panels reference buffers and own scroll/focus/viewport.

## Buffer, panel, and style model

The default cri workspace is built entirely through this API: persistent `transcript`, `activity`, and `input` buffers are attached to `Conversation` (main), `Activity` (right), and `Prompt` (bottom) panels. User, command, assistant, tool, and activity output are named highlight groups, not embedded ANSI.

This is intentionally a simplified Vim-like model:

```text
UiRuntime: global BufferStore + WorkspaceStore + EventBus
Workspace: panels, focus, layout state
Panel: buffer_id, viewport, scroll, title
TextBuffer: text, one cursor, buffer-local mode, highlight regions
```

A buffer can outlive its panel and can be displayed by multiple panels. Runtime mutations reject duplicate panel IDs, reject panels that reference unknown buffers, move focus when a panel is removed, and refuse to close buffers still referenced by any panel. The current simple model intentionally gives a shared buffer one cursor; independent cursor positions require a future `BufferView` layer and are not faked by panels.

Highlights are half-open Unicode-codepoint ranges owned by `TextBuffer`:

```crystal
buffer.highlight(0, 5, "keyword")
buffer.set_highlights([Tui::Highlight.new(6, 11, "error")])
ui.define_style("keyword", Tui::Style.new(75, bold: true))
```

Text never contains ANSI styling. The renderer maps named groups through `Theme`; raw control bytes from buffer content are stripped. Structural edits clear highlights because positions become stale; append preserves existing regions.

## Simplified Vim bindings

The focused buffer determines the current mode and owns the visible terminal cursor. The cursor is rendered in every focused text panel, including read-only Conversation and Activity panels. The default Conversation and Activity panels are read-only; Prompt is editable. `i`/`a` enters INSERT only for the currently focused editable panel and never changes focus. Use `Ctrl-W j` to focus Prompt, then `i` to edit it. Escape returns the focused buffer to NORMAL but preserves focus. `:` is the separate command-line operation: it temporarily focuses Prompt and restores the prior panel after dispatch or Escape.

- INSERT/COMMAND: text, Backspace, Left/Right; Enter submits. INSERT uses a bar cursor.
- NORMAL: i/a enters INSERT; j/k scrolls. NORMAL uses a block cursor.
  `h`/`j`/`k`/`l` move the focused buffer cursor left/down/up/right, including in read-only panels. Cursor movement automatically adjusts the focused panel viewport. `Ctrl-Y`/`Ctrl-E` scroll the focused panel up/down. Ctrl-W h/j/k/l moves focus left/down/up/right between panels, including Prompt. `v` enters VISUAL mode, movement extends the selection, and `y` copies it through the host clipboard capability. Prompt submission is only active while Prompt itself is focused; other editable panels do not submit the Prompt on Enter. Model turns run in a separate Crystal fiber so input/render dispatch remains responsive while provider I/O yields.
- COMMAND uses an underline cursor.
  Ctrl-U/Ctrl-D pages; colon enters COMMAND.
- q and Tab are unbound. Use :q or :quit to exit.
- Arrow Up/Down accesses input history in INSERT/COMMAND.

## Keymap API

Bindings are declarative; `EventHandler` dispatches actions rather than knowing concrete keys:

```crystal
ui.keymap.bind(Tui::Mode::Normal, "ctrl-w l", "panel.focus_right")
ui.keymap.bind(Tui::Mode::Normal, "g", "extension.git.open")
ui.keymap.unbind(Tui::Mode::Normal, "j")
```

Host-side extensions can register behavior directly:

```crystal
ui.actions.register("extension.git.open") do |context|
  context.ui.set_activity("opening GitHub…\\n", "activity")
end
```

`ActionContext` provides the `UiRuntime`, triggering `KeyEvent`, and action name. Unknown actions still emit `ui.keymap.action` on the global EventBus, which is the bridge for WASM/remote extensions.

Application coalesces event invalidations in a separate rendering fiber (16ms). The first frame and a resize clear the alternate screen; ordinary updates use a row diff, so typing redraws only the prompt row rather than flashing the entire terminal.
Streaming text is appended to the transcript buffer; the input handler does not
invoke the renderer. `Terminal.dimensions` obtains `stty size` on every redraw,
so the header, dividers, body, and bottom prompt fill the current terminal. Wide
terminals render main/right columns; narrow terminals stack panels.
Terminal control bytes in displayed content are stripped.

## Current limitations

Agent execution is still synchronous with input dispatch: keyboard cancellation
while waiting for a model needs an asynchronous task/cancellation layer.
Terminal dimensions use `stty size` with COLUMNS/LINES fallback; the application polls for resize. Display-cell widths for wide/combining Unicode remain to implement.
Input history/command entry still uses the built-in input buffer; arbitrary
editable extension panels need explicit input routing. Unicode editing uses
codepoints, not grapheme clusters. Public mutable stores can bypass events.

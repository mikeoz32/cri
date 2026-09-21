# zig_ui_buffer

A real Zig freestanding WASM fixture for the Plugin UI API. Its declared
`zig_ui_buffer.create` action returns a validated `ui.buffer.create` effect.
The host namespaces the resulting buffer as `plugin:zig_ui_buffer:review`.

Build from the repository root:

```sh
sdk/zig/build.sh examples/extensions/zig_ui_buffer
```

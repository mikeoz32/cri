# Plugin UI API design

Status: first vertical slice implemented; buffer/panel/highlight effects and guest SDK helpers remain pending.

## Principle

A plugin never writes terminal escape sequences or mutates `UiRuntime` directly. The Crystal host owns buffers, panels, workspace layout, focus, keymaps, rendering, and permission enforcement.

Plugins use a public language SDK. The SDK returns structured UI effects; the host validates and applies them.

```text
keymap action
  → host action adapter
  → WASM plugin invocation with serialized UI context
  → returned ui.* effects
  → host validation
  → UiRuntime mutation + EventBus redraw
```

## Manifest contributions

Executable UI actions are declared before plugin code is loaded:

```toml
[[ui.actions]]
name = "github.open_issue"
title = "Open GitHub issue"
entrypoint = "cri_call"
```

The host registers an adapter under `github.open_issue` in `UiRuntime.actions`. The adapter invokes the plugin when the action is dispatched.

## Action context

The plugin receives serializable state only, never host object references:

```json
{
  "action": "github.open_issue",
  "workspace": {"id": "main", "status": "ready"},
  "focus": {
    "panel_id": "transcript",
    "buffer_id": "transcript",
    "mode": "NORMAL",
    "cursor": 0,
    "selection": null
  },
  "event": {"token": "v", "value": "v"}
}
```

## Initial effects

Implemented first:

```json
{"type":"ui.buffer.create","id":"review","content":"from plugin"}
```

The host namespaces the resulting buffer as `plugin:<extension>:<id>` and enforces ID/content limits. The next buffer mutations use the same owner namespace:

```json
{"type":"ui.buffer.append","id":"review","content":"more"}
{"type":"ui.buffer.replace","id":"review","content":"replacement"}
{"type":"ui.highlight.set","id":"review","start":0,"finish":5,"group":"accent"}
```

`replace` clears existing highlights; highlight ranges must be positive and within the target buffer. Plugins can define an owner-namespaced style with `ui.highlight.define`:

```json
{"type":"ui.highlight.define","group":"plugin_accent","foreground":45,"bold":true,"underline":false}
```

The host accepts only bounded color/attribute values and stores the style as `plugin:<extension>:plugin_accent`.

Planned/implemented effect families:

- `ui.buffer.create`
- `ui.buffer.replace`
- `ui.buffer.append`
- `ui.highlight.set`
- `ui.panel.open`
- `ui.panel.focus`
- `ui.notification`

Effects are scoped to plugin-owned IDs by default. The host validates IDs, ranges, positions, theme groups, ownership, and resource limits before changing UI state. Buffer create/append/replace, highlight set, panel open, and panel focus are implemented. Panel IDs and referenced buffer IDs are owner-namespaced; panel positions are limited to `main`, `right`, and `bottom`.

## SDK shape

Each guest SDK exposes the same conceptual API:

```text
register/declarative UI action
receive UI action context
return UI buffer/panel/highlight effects
```

Zig, Rust, C, and future Crystal SDKs share this contract. WASM plugins do not provide Crystal `Proc` values; host-side action adapters bridge named actions to plugin invocations.

## Keymaps

Plugins may request a named action binding through host-approved keymap APIs. Keymaps resolve strings to actions; they do not embed guest code. Unknown or WASM-backed actions route through the host action adapter.

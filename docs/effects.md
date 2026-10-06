# cri host-mediated effects

Dangerous operations are host-mediated. Extensions declare permissions in `extension.toml`; the host grants a subset in user/project config and checks each effect at runtime.

## Initial effect types

- `http.request`
- `file.read`
- `filesystem.list`
- `file.propose_edit`
- `session.state.get`
- `session.state.set`
- `ui.notification`
- `ui.status_update`
- future: `tool.call`, `model.call`, `secret.resolve`

## HTTP request

```json
{
  "type": "http.request",
  "method": "GET",
  "url": "https://api.github.com/repos/owner/repo/issues/1",
  "auth": { "secret": "GITHUB_TOKEN", "as": "bearer" }
}
```

The host validates the URL against both requested and granted network scopes, then passes the operation through the deny-by-default capability broker. A configured interactive client may resolve the pending request with allow/deny; tools and extensions cannot resolve their own requests. Secrets should preferably be injected into headers by the host rather than returned to the extension as raw strings. HTTP effects use bounded connection/read timeouts, cap request and response bodies, and do not follow redirects automatically; 3xx responses are rejected.

## UI notifications

The first implemented plugin UI effect is `ui.notification`:

```json
{"type":"ui.notification","message":"Done","level":"success"}
```

The host validates the level and message size, then delivers it through the public UI sink.

## Per-session extension state

Extensions can store one JSON value per session, namespaced by the calling extension:

```json
{"type":"session.state.get"}
{"type":"session.state.set","value":{"todos":[{"id":"a","text":"Ship it","done":false}]}}
```

The host enforces the extension's `session_state` declaration and configured grant, then requests one-shot approval for each read or write. Values are capped at 1 MiB and stored in the session record. A successful write emits `session.extension_state.updated` with the session and extension IDs; the event does not include the stored value.

## Model context providers

Extensions may declare `[[context_providers]]`. Before every model request, the host invokes each granted provider in stable manifest order with the session ID, conversation, available tools, and context blocks added so far. The provider returns a patch:

The input has this shape:

```json
{
  "session_id": "0123456789abcdef",
  "messages": [{"role":"user","content":"What is left?"}],
  "tools": [],
  "blocks": []
}
```

Providers can use `session.state.get` and `session.state.set` effects to read or update their own session state while they run.

```json
{
  "add": [{"id":"open-todos","content":"Open tasks: Ship it"}],
  "remove": ["extension/other_extension/obsolete-note"]
}
```

The host namespaces added block IDs by extension and sends the resulting blocks as ephemeral system messages. They are not inserted into the saved transcript. Context providers require the `context` permission and one-shot `context.modify` approval for each invocation. They can remove extension-contributed blocks, but cannot remove the conversation transcript or host-owned instructions. A failed provider is reported as `extension.context.error` and does not stop the model request.

## Effect loop

A WASM invocation may return effects:

```text
cri_call(request)
  -> response(effects)
host validates and executes each effect
cri_resume({results: [...]})
  -> final response or another set of effects
```

The module instance remains alive during this loop and is destroyed when the response has no more effects, an error occurs, or the loop limit is reached.

## File edits

Extensions cannot write files directly. They can return `file.propose_edit` so the host can show a diff and require approval.

## Workspace directory listing

An extension can ask the host to list a directory with:

```json
{"type":"filesystem.list","path":"src"}
```

The host resolves paths from the configured workspace root, rejects paths that
escape it, checks the extension's requested and configured `filesystem_read`
scopes, and then requests one-shot `filesystem.list` approval before returning
entry names and types. The fullscreen TUI shows the requesting extension,
capability, and target; press `y` to allow once or `n`/`Esc` to deny. A host
without an interactive approval client denies the request by default.

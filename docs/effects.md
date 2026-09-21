# cri host-mediated effects

Dangerous operations are host-mediated. Extensions declare permissions in `extension.toml`; the host grants a subset in user/project config and checks each effect at runtime.

## Initial effect types

- `http.request`
- `file.read`
- `file.propose_edit`
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

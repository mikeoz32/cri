# GitHub issue example

This is an example manifest for the first real network/API extension target.

`plugin.wasm` is intentionally not implemented yet. The intended behavior is:

1. Receive a `tool` request for `github.get_issue`.
2. Return an `http.request` effect targeting `https://api.github.com`.
3. Ask the host to inject `GITHUB_TOKEN` as bearer auth.
4. Receive the response through the host continuation/effect result flow.

The extension never receives ambient network or filesystem access.

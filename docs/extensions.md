# cri extensions

`cri` extensions are manifest-first capability bundles. Executable behavior is supplied by WASM, while static contributions stay declarative.

## Package layout

```text
extensions/my-extension/
  extension.toml
  plugin.wasm
  prompts/
```

## Manifest MVP

```toml
name = "github"
version = "0.1.0"
abi = "cri.extension.v1"
wasm = "plugin.wasm"

[permissions]
network = ["https://api.github.com"]
secrets = ["GITHUB_TOKEN"]
filesystem_read = []
filesystem_write = []
shell = false
model = false

[[tools]]
name = "github.get_issue"
description = "Fetch a GitHub issue"
entrypoint = "cri_call"

[[commands]]
name = "github:open-issue"
title = "Open GitHub issue"
entrypoint = "cri_call"

[[ui.status_items]]
id = "github.rate_limit"
title = "GitHub rate limit"
entrypoint = "cri_call"
```

## Principle

Extensions do not directly mutate the world. They request host-mediated effects: HTTP requests, file reads, proposed edits, notifications, status updates, model calls, or tool calls. The Crystal host enforces permissions and renders UI.

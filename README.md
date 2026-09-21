# cri

`cri` is an experimental pi-like coding harness written in Crystal.

Design direction: a small trusted Crystal core plus broad manifest-first WASM extensions. Extensions contribute tools, commands, hooks, context, and host-rendered UI metadata. Powerful actions go through host-mediated effects and permissions.

## Current commands

```sh
crystal run src/cri.cr -- doctor
crystal run src/cri.cr -- extensions list
crystal run src/cri.cr -- extensions invoke github_issue tool github.get_issue '{}'
crystal run src/cri.cr -- tool list
crystal run src/cri.cr -- tool call builtin.echo '{"hello":"world"}'
crystal run src/cri.cr -- chat
crystal run src/cri.cr -- tui
crystal run src/cri.cr -- plugin init --lang zig my_plugin ./my_plugin
crystal run src/cri.cr -- plugin check ./my_plugin
crystal run src/cri.cr -- plugin build ./my_plugin
crystal run src/cri.cr -- plugin test ./my_plugin '{}'
# In an interactive TTY this opens the fullscreen shell; pipes use line mode.
```

## WASM runtime

The first runtime uses a minimal Crystal binding to the wasm3 C API. It is opt-in so the core still builds without a native runtime:

```sh
# with libm3 installed or available via LIBRARY_PATH
crystal build -Dwasm3 src/cri.cr -o cri
```

The fixture can be invoked with:

```sh
cri extensions invoke fixture tool fixture.echo '{"hello":"world"}'
```

## Docs

- `docs/extensions.md`
- `docs/effects.md`
- `docs/plugin-config.md`
- `docs/wasm-abi-v1.md`
- `docs/wasm3-runtime.md`
- `sdk/crystal/README.md`
- `sdk/zig/README.md`
- `docs/plugin-tooling.md`
- `docs/testing.md`

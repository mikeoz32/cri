# Zig fetch extension

This is a real `wasm32-freestanding` extension compiled from `sdk/zig/example/main.zig`.

Build it again with Zig from the repository root:

```sh
sdk/zig/build.sh examples/extensions/zig_fetch
```

The script targets `wasm32-freestanding` and exports the ABI functions required by cri.

The extension has no WASI imports. `zig.fetch` returns an `http.request` effect,
and `zig.workspace_ls` returns a `filesystem.list` effect. The Crystal host
checks the declared and configured permissions, asks for per-call approval,
then resumes the module with the result.

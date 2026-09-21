# Zig fetch extension

This is a real `wasm32-freestanding` extension compiled from `sdk/zig/example/main.zig`.

Build it again with Zig from the repository root:

```sh
sdk/zig/build.sh examples/extensions/zig_fetch
```

The script targets `wasm32-freestanding` and exports the ABI functions required by cri.

The extension has no WASI imports. It returns an `http.request` effect; the Crystal host decides whether the declared domain is granted and then resumes the module.

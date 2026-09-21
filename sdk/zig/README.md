# cri Zig Extension SDK

The Zig SDK targets ordinary capability-free WebAssembly:

```text
wasm32-freestanding
no WASI
no imports
```

## Example

```zig
const cri = @import("cri_sdk");
const effects = @import("cri_effects");

fn call(request: cri.Request) cri.Response {
    _ = request;
    return cri.Response.success("{\"ok\":true}");
}

fn resume_extension(_: cri.Request) cri.Response {
    return cri.Response.success("{\"done\":true}");
}

export fn cri_init() void {
    cri.register(.{ .call = call, .resume_fn = resume_extension });
}
```

Build from the repository root:

```sh
sdk/zig/build.sh examples/extensions/zig_fetch
```

The SDK provides:

- `cri.Request` and `cri.Response`;
- extension registration;
- `cri_call`/`cri_resume` ABI exports;
- bump allocator and result buffer;
- effect builders for HTTP, file reads, edit proposals, and notifications.

The extension only returns effects. The Crystal host performs all capability-bearing operations and resumes the module.

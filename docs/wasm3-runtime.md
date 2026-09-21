# wasm3 runtime

`cri` uses a minimal binding to the wasm3 C API rather than binding the complete header.

Build with a native wasm3 library installed:

```sh
crystal build -Dwasm3 src/cri.cr -o cri
# Ensure the wasm3 library is discoverable, for example:
LIBRARY_PATH=/path/to/wasm3/build/source crystal build -Dwasm3 src/cri.cr -o cri
```

The first runtime surface is intentionally small:

- create/free environment;
- create/free runtime;
- parse/load module;
- find exported functions;
- call i32 functions and read results;
- access linear memory;
- set a gas limit.

The guest module receives no imports in this phase. It must export:

```text
memory
alloc(i32) -> i32
cri_call(i32, i32) -> i32
cri_result_len() -> i32
```

`free(i32, i32)` and `cri_free_result(i32, i32)` are optional cleanup exports.

For effects, the module additionally exports:

```text
cri_resume(i32, i32) -> i32
```

The host sends a JSON request to `cri_call` and expects a JSON `ResponseEnvelope`. If the response contains effects, the host executes them through its permission-checked handlers and sends their results to `cri_resume`. The same wasm3 invocation stays alive for the whole loop, then is destroyed.

Network, filesystem, secrets, and UI operations are represented as returned effects and are handled by Crystal. The module receives no imports, which keeps the WASM capability-isolated while the ABI is still small.

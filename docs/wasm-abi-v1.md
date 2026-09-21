# WASM ABI v1

ABI string: `cri.extension.v1`.

MVP convention:

```text
alloc(size) -> ptr
free(ptr, size)
cri_call(ptr, len) -> result_ptr
cri_result_len() -> len
cri_free_result(ptr, len)
```

Input is a UTF-8 JSON request envelope:

```json
{
  "abi": "cri.extension.v1",
  "kind": "tool",
  "name": "github.get_issue",
  "input": {},
  "context": {
    "session_id": "...",
    "cwd": "/project",
    "tui": true
  }
}
```

Output is a UTF-8 JSON response envelope:

```json
{
  "ok": true,
  "result": {},
  "effects": []
}
```

The host may cache WASM instances, but extensions should not require persistent in-memory state. Durable state should later go through host storage APIs.

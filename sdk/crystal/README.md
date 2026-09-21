# cri Crystal Extension SDK

This is the guest-side SDK for writing `cri` extensions in Crystal without handling the raw pointer/JSON ABI directly.

## API

```crystal
require "cri_sdk"
require "cri_sdk_exports"

class MyExtension < CriSDK::Extension
  def call(request : CriSDK::Request) : CriSDK::Response
    CriSDK::Response.success(JSON.parse({"hello" => "world"}.to_json))
  end
end

CriSDK::Runtime.extension = MyExtension.new
```

Use `CriSDK::Effects.http_request`, `read_file`, `propose_edit`, and `notify` to request host-mediated capabilities.

## ABI exports

`cri_sdk_exports.cr` exposes only the ABI required by the host:

- `alloc`
- `cri_free`
- `cri_call`
- `cri_resume`
- `cri_result_len`
- `cri_free_result`

The host accepts both `free` and `cri_free` for compatibility with older fixtures.

## WASM status

The SDK API and native compilation are working. The installed Crystal compiler currently fails while compiling the standard library for `wasm32-unknown-wasi` in its WASI event-loop implementation. Until that upstream/toolchain issue is resolved, this SDK can be tested natively, but a Crystal-generated guest `.wasm` cannot yet be produced reliably in this environment.

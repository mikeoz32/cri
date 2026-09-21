# Testing

Tests are split into unit and integration suites.

```sh
crystal spec spec/unit
crystal spec spec/integration
crystal spec
```

The wasm3 integration suite requires a native wasm3 library:

```sh
LIBRARY_PATH=/path/to/wasm3/build/source \
  crystal spec -Dwasm3
```

## Unit suite

Covers pure logic without network, native wasm3, or archive execution:

- manifest parsing and validation;
- permission scopes and grants;
- agent limits;
- buffers, panels, and workspace ownership;
- tool and provider models.

## Integration suite

Covers boundaries:

- raw WASM conformance and import rejection;
- wasm3 invocation/effect resume;
- Zig plugin execution;
- local OpenAI completion/streaming HTTP;
- plugin pack/install/remove.

Integration tests use localhost or fixtures. No external model/API is required.

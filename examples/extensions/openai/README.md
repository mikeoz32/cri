# OpenAI provider extension

This first-party provider extension registers the OpenAI API provider through
its `init` hook. It supplies the OpenAI-compatible API client configuration and
its `api-key` and ChatGPT OAuth flows; the host owns the generic auth engine and
credential storage.

The same API client can be used by separate provider extensions such as
OpenRouter with different registration parameters.

Build the WASM fixture with:

```bash
./sdk/zig/build.sh examples/extensions/openai
```

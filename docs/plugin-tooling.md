# Plugin tooling

The host runtime is language-neutral. SDKs and build adapters live outside the runtime.

## Create a plugin

```sh
cri plugin init --lang zig my_plugin path/to/my_plugin
```

This creates:

```text
path/to/my_plugin/
  extension.toml
  src/main.zig
```

## Check and build

```sh
cri plugin check path/to/my_plugin
cri plugin build path/to/my_plugin
```

`check` validates the manifest, SDK metadata, and (when present) the raw WASM module. It checks the module version, rejects all imports, requires exported memory and the core ABI exports, and does not require the artifact yet, so it can be used before the first build. `build` delegates to the SDK adapter and writes `plugin.wasm` into the project.

Package and install a built plugin:

```sh
cri plugin pack path/to/my_plugin
cri plugin install my_plugin.cri-plugin.tar.gz
cri plugin remove my_plugin
```

Packages are tarballs containing only the manifest, WASM artifact, optional README, and optional `prompts/` directory. Install validates archive paths and the manifest before extraction.

After building, run the plugin in the wasm3 sandbox:

```sh
cri plugin test path/to/my_plugin '{"text":"hello"}'
```

The test invokes the first declared tool and executes the complete call/effect/resume loop. Build the host with `-Dwasm3` for this command.

## Adding another SDK

A language SDK needs:

1. guest-side ABI implementation;
2. effect helpers;
3. a project template;
4. a build adapter;
5. ABI fixture tests.

The Crystal host only consumes the resulting `plugin.wasm`; no language-specific runtime code is required.

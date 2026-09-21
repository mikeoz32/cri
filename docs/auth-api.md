# Host authentication API

Authentication is host-owned. Extensions declare provider/flow configuration;
they never receive raw API keys, access tokens, refresh tokens, client secrets,
or callback handles.

## Current providers

The host registers two OpenAI provider families:

- `openai-api` / `api-key` — direct OpenAI API access;
- `openai-codex` / `chatgpt` or `device` — official Codex app-server login transport for ChatGPT subscription access.

The Codex transport is intentionally separate from the OpenAI API transport.
A ChatGPT subscription credential is not treated as a normal OpenAI API key.

## Host types

```text
Auth::Provider
Auth::Flow
Auth::Broker
Auth::CredentialStore
Auth::CredentialRef
```

`CredentialRef` is opaque and safe to serialize into host-side provider state.
The secret is kept inside `Auth::CredentialStore` and resolved only by a host
provider/transport adapter.

## API-token flow

The first implemented flow imports an API token from a host-controlled source:

```text
OPENAI_API_KEY / explicit host input
→ Auth::Broker
→ CredentialStore
→ CredentialRef
→ OpenAI host provider
```

The host owns a separate file store at `$XDG_CONFIG_HOME/cri/auth.json`
(or `~/.config/cri/auth.json`). It uses a versioned cri-owned schema, a `0700`
configuration directory, a `0600` file, a lock file, and atomic same-directory
replacement. It never reads pi/Codex auth files.

On Linux, the optional Secret Service backend can be selected when
`secret-tool` and a DBus session are available. In headless/dev environments
without Secret Service, the file store remains the default cri-owned durable
backend; a process-memory store is available explicitly for tests/ephemeral
hosts.

## Async flows

Device-code and browser OAuth flows use the same future host API:

```text
AuthBroker
  → pending operation
  → host opens browser or displays device code
  → host owns callback/polling/token exchange
  → host stores credential
  → provider receives CredentialRef
```

The extension only supplies declarative provider configuration. The host owns
loopback callback binding, state, PKCE, refresh, logout, and secure storage.

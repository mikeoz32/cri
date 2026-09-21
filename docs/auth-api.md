# Host authentication API

Authentication is host-owned. Extensions declare provider/flow configuration;
they never receive raw API keys, access tokens, refresh tokens, client secrets,
or callback handles.

## Provider and flow registration

The host does not hardcode provider-specific OAuth endpoints. A provider or
extension registers its `Auth::Flow` definitions through `host.providers`, and
an OAuth flow supplies its own `OAuthConfig`: authorization/device/token URLs,
client ID, scopes, redirect configuration, and extra parameters.

The generic host OAuth client supports browser Authorization Code + PKCE,
RFC 8628 device authorization/polling, expiry, refresh-token rotation, and
host-owned callback handling. No OpenAI or Codex endpoints are embedded in the
core OAuth implementation.

Providers are registered through the host provider registry. A registration
contains the provider transport and its available `Auth::Flow` definitions:

```crystal
host.providers.register(ProviderRegistration.new(
  "github",
  "GitHub",
  "github",
  [Auth::Flow.new("device", Auth::FlowKind::OAuthDevice)]
))
```

An extension `init` hook returns the serializable
`host.provider.register` effect. The first-party OpenAI provider uses the same
registration shape from `src/cri/providers/openai/registration.cr`; its OAuth
URLs and client configuration are not part of the generic auth engine. The host validates it and namespaces the
provider as `extension/<extension-name>/<provider-id>`:

```json
{
  "type": "host.provider.register",
  "id": "github",
  "title": "GitHub",
  "transport": "github",
  "auth_flows": [
    {"id": "device", "kind": "oauth_device"}
  ]
}
```

Registration does not grant an extension access to tokens or permission to
perform the login itself. The auth UI displays the provider and its flows from
this registry; auth providers are not configured through `extension.toml`.

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
OPENAI_API_KEY / `cri auth login openai api-key`
→ Auth::Broker
→ CredentialStore
→ CredentialRef
→ OpenAI host provider
```

The CLI commands are:

```text
cri auth status
cri auth login openai api-key
cri auth login openai chatgpt
cri auth logout openai api-key
```

The interactive token prompt disables terminal echo and does not put the token
in command arguments or transcript output. For `openai/api-key`, the host
first performs a `GET /v1/models` validation request; a failed validation is
not persisted. Extension-declared token flows are stored by the host but are
not network-validated because their transport is extension-specific.

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

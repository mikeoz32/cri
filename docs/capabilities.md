# Capability approval API

All side-effecting tool and extension operations are deny-by-default.

```text
CapabilityRequest
  → CapabilityBroker
  → ApprovalBackend
  → allow/deny
```

The request contains:

- actor;
- capability;
- target;
- reason;
- one-shot request ID.

`PendingApproval#await` waits on a bounded Crystal `Channel`, so waiting for a
user/client decision yields the current fiber instead of blocking the scheduler.

The minimal decision set is only:

- `allow`;
- `deny`.

`EventApprovalBackend` emits `approval.requested` events. A trusted host client
resolves them through `CapabilityBroker#resolve`. Tools, extensions, and guest
SDKs never receive the resolve path.

The fullscreen TUI acts as this client: it displays the extension, capability,
and target, then accepts `y` to allow once or `n`/`Esc` to deny. Other host
contexts keep the deny-by-default backend unless they attach their own client.

Production hosts use `CapabilityBroker.deny_all` unless they explicitly attach
an approval backend. Tests and deliberately controlled hosts may use
`allow_all`.

Model/provider access is not a capability. It remains internal to `Agent`.

Extensions can separately request `session_state` and `context` in their
manifest and receive those grants from user/project configuration. Each
session-state read/write and each context-provider invocation still passes
through the one-shot broker. Session state is namespaced by extension; context
providers may only filter extension-contributed blocks, not conversation
messages or host-owned instructions.

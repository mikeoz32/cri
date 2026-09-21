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

Production hosts use `CapabilityBroker.deny_all` unless they explicitly attach
an approval backend. Tests and deliberately controlled hosts may use
`allow_all`.

Model/provider access is not a capability. It remains internal to `Agent`.

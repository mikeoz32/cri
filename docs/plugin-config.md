# Plugin grants configuration

Plugin permissions are denied by default. User and project configuration are JSON files loaded in this order:

```text
~/.config/cri/config.json
<project>/.cri/config.json
```

Project values override user values for the same extension.

Example:

```json
{
  "extensions": {
    "github_issue": {
      "enabled": true,
      "network": ["https://api.github.com"],
      "secrets": ["GITHUB_TOKEN"],
      "filesystem_read": [],
      "filesystem_write": [],
      "shell": false,
      "model": false
    },
    "untrusted_extension": {
      "enabled": false
    }
  }
}
```

An extension must request a capability in its `extension.toml`, and the grant must also contain it. Both checks are required at runtime.

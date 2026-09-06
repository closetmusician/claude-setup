---
name: strict
description: Check whether governance strict mode is currently active or inactive.
---

# Strict Mode — Status

Check the sentinel file:

```bash
ls "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")/.agents/claude-governance/.active" 2>/dev/null
```

- If the file exists: report "Strict mode is **active**. Governance hooks are enforcing."
- If the file does not exist: report "Strict mode is **inactive**. Governance hooks are no-op."

Also mention: use `/strict-on` to activate, `/strict-off` to deactivate.

---
name: strict-off
description: Deactivate governance enforcement hooks. Use when done with orchestration or switching to normal exploratory work.
---

# Strict Mode — OFF

Deactivate governance enforcement by removing the sentinel file:

```bash
rm -f "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")/.agents/claude-governance/.active"
```

Run this command now, then confirm to the user:

> Strict mode **deactivated**. All governance hooks are now no-op. Normal agent spawning resumed.

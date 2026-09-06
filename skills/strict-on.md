---
name: strict-on
description: Activate governance enforcement hooks (pre-agent-gate, post-agent-audit, role-enforcement). Use when starting orchestrated or high-stakes multi-agent work.
---

# Strict Mode — ON

Activate governance enforcement by creating the sentinel file:

```bash
_gov_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")/.agents/claude-governance"
mkdir -p "$_gov_root"
touch "$_gov_root/.active"
```

Run this command now, then confirm to the user:

> Strict mode **activated**. Governance hooks are now enforcing:
> - **Pre-agent gate**: subagent prompts must have Mandatory Context, Requirement Map, and Constraints
> - **Post-agent audit**: subagent results checked for evidence coverage (RED/GREEN)
> - **Role enforcement**: orchestrator blocked from Write/Edit/Bash on implementation files
>
> Use `/strict-off` to deactivate. Auto-deactivates on session end.

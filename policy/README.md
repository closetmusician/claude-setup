# Route Policy

`route-policy.json` defines the difficulty-aware model dispatcher tiers for the self-improving harness (Pillar IV-A).

## Tier Table

| Tier   | Model          | Use Cases |
|--------|----------------|-----------|
| haiku  | claude-haiku   | Mechanical ops: counts, existence checks, diffs, greps, file moves/renames. Low-reasoning overhead. |
| sonnet | claude-sonnet  | Code edits, patch applies, test runs, oracle verification. Default fallback tier. |
| opus   | claude-opus    | Synthesis, architecture decisions, adversarial audits, complex cross-domain reasoning. |
| fable  | claude-fable   | Prose voice, PRD narrative writing, briefings, stakeholder communications. |

## Matching Rules

Rules are evaluated **top-down**; the first match wins. Each rule may specify:
- `subtask_class` — exact string match against the task's `intent` or explicit class field
- `tool` — exact tool name match
- `verb_re` — POSIX ERE regex matched against both `verb` and `intent` fields

If no rule matches, the `classifier` fallback uses a haiku call to classify the task descriptor, then falls back to `default_tier` ("sonnet") on timeout or error.

## Invariant

**An explicit caller-provided tier always overrides all routing logic.**  
If a caller sets `tier` in the subtask descriptor, `route-dispatch.sh` passes it through unchanged and emits `reason:"caller-override"`. The policy rules and classifier are bypassed entirely.

## Extending the Policy

Add rules to `route-policy.json` in `rules[]`. Place higher-priority rules earlier in the array. Re-run `scripts/tests/test-route-dispatch.sh` after any change.

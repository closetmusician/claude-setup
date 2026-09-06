# Eval Corpus Schema

FROZEN — Pillar III §Task 1/3. Do not edit fields; add new sections instead.

## Directory layout

```
~/.claude/evals/incidents/<class>-<nnn>/
  fixture.jsonl   — transcript slice (NDJSON); may have "synthesized":true metadata header
  input.json      — exact hook stdin; __FIXTURE_DIR__ replaced by runner with abs path
  expect.json     — verdict contract (see fields below)
```

`<class>` = incident class code (e.g. C2, U3). `<nnn>` = zero-padded monotonic counter per class.

## input.json fields

| Field | Type | Notes |
|---|---|---|
| `transcript_path` | string | Use `__FIXTURE_DIR__` — runner substitutes abs path |
| `cwd` | string | Working directory fed to guard |
| `stop_hook_active` | bool | Stop-hook retry flag |
| Any hook-specific field | * | Pass through verbatim |

## expect.json fields

| Field | Type | Notes |
|---|---|---|
| `hook` | string | Relative path from `~/.claude/` to guard script |
| `expect` | `"block"` \| `"allow"` \| `"deny"` | Expected verdict |
| `reason_contains` | string | Substring that must appear in guard stdout (empty = skip) |
| `expected_gap` | bool | `true` = known-uncovered class; runner reports KNOWN-GAP, not FAIL |
| `description` | string | Human-readable description of the fixture's oracle role |

## fixture.jsonl format

Each line is a JSON object with `type` and `message`. Compatible with Claude Code transcript format:

```jsonl
{"type":"user","message":{"content":"..."}}
{"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
{"type":"tool_use","message":{"name":"Write","input":{...}}}
{"type":"tool_result","message":{"content":"..."}}
```

When a transcript is purged: add a leading metadata line `{"synthesized":true,"class":"...","session_id":"..."}`.

## Corpus runner contract (III-3)

Added by: `harness eval run` implementation (Pillar III Task 3).

- Runner resolves `__FIXTURE_DIR__` in input.json to the fixture's absolute directory path.
- Runner invokes the guard named in `expect.json["hook"]` (resolved from `~/.claude/`) with the hydrated input.json piped as stdin.
- Runner classifies output: `block` if stdout contains `"decision":"block"`; `deny` if stdout contains `"permissionDecision":"deny"`; `allow` otherwise.
- A fixture PASSES if the classified verdict matches `expect`.
- A fixture with `expected_gap:true` → reported as KNOWN-GAP (not FAIL) regardless of verdict.
- `regressions[]` = fixtures that PASSED on baseline and FAIL with patch.
- Every run emits one `eval_run` event to the spine.

### Diff allowlist (CORPUS_TAMPER protection)

Patches touching any of the following paths are **refused** (exit 3) before any fixture runs:
- `scripts/run-harness-evals.sh` (the wrapper)
- `evals/` directory tree
- Files matching `eval-corpus/` subtree (out-of-tree corpus under `$STATE`)

A CORPUS_TAMPER exit prevents a rogue patch from rewriting its own judge.

# Plan: Mechanistic Instruction Compliance Hooks

## Context

On 2026-04-04, Claude was given explicit instructions to use `lead-orchestrator`, `/qa`, and `agent-browser`. It parsed all requirements correctly, then ignored every one, substituting curl-based testing instead. Root cause analysis (docs/claude-failure.md) identified 6 failure modes. Prompt-based instructions were already present and were ignored — this system must enforce compliance mechanistically via hooks.

## Design Principles

- **Hard block + hard redirect**: Every deny tells the agent exactly what to do instead
- **Shared state via ledger**: A JSON file tracks requirements vs fulfillment across hooks
- **Fail-open**: All hooks `exit 0` on error (never block work due to hook bugs)
- **Subagent pass-through**: Hooks check `agent_id` — subagents aren't subject to orchestrator restrictions
- **Bark-once**: Sentinel files prevent infinite block loops

## Architecture

```
User message → [1. PARSE] → ledger.json
                                ↓
Agent spawns subagent → [2. GUARD] → validates prompt has required tools
                                      injects adversarial framing if needed
                                ↓
Agent runs Bash/curl → [3. GATE] → blocks substitution when Skill required
                                ↓
Skill invoked → [4. TRACK] → marks tool as fulfilled in ledger
                                ↓
Session ends → [5. AUDIT] → checks all required tools were invoked
```

## Files to Create

### 1. `~/.claude/scripts/instruction-ledger-parse.sh` (UserPromptSubmit hook)
**Addresses: Root Cause 1 (Dereferencing), Root Cause 4 (Polarity Inversion)**

Fires when user submits a prompt. Reads the user's message from transcript, extracts:
- Named tools/skills (pattern: `/qa`, `lead-orchestrator`, `agent-browser`, skill names)
- Task polarity keywords (`adversarial`, `disprove`, `challenge`, `break`)
- Golden reference URLs

Writes to `~/.claude/state/ledger.json`:
```json
{
  "required_tools": ["/qa", "lead-orchestrator", "agent-browser"],
  "polarity": "adversarial",
  "golden_ref": "https://mirrorline.diligentoneplatform-dev.com/",
  "fulfilled": [],
  "created_at": "2026-04-04T10:00:00Z"
}
```

State dir: `~/.claude/state/` (created by script if missing, cleaned on session start via SessionStart hook).

### 2. `~/.claude/scripts/subagent-compliance-guard.sh` (PreToolUse on Agent)
**Addresses: Root Cause 1 (Dereferencing), Root Cause 3 (Abstraction Barrier), Root Cause 4 (Polarity Inversion)**

Fires before every `Agent` tool call (subagent spawn). Reads ledger, checks:

**Check A — Required tools in prompt**: If `required_tools` is non-empty and the subagent prompt doesn't mention them, HARD DENY:
```
SUBAGENT COMPLIANCE GUARD: User required these tools: /qa, agent-browser.
Your subagent prompt does not mention them. REWRITE the prompt to include:
- Explicit instruction to invoke Skill(skill='qa')
- Explicit instruction to use agent-browser for browser verification
```

**Check B — Adversarial framing**: If `polarity == "adversarial"` and prompt uses confirmatory language (verify, confirm, check passes) without adversarial language (disprove, find failures, break), HARD DENY:
```
POLARITY GUARD: User requested ADVERSARIAL agents. Your prompt uses confirmatory
framing. REWRITE so the agent's success condition is FINDING FAILURES.
```

**Subagent pass-through**: If `agent_id` is set (this IS a subagent), skip all checks.

### 3. `~/.claude/scripts/skill-first-gate.sh` (PreToolUse on Bash)
**Addresses: Root Cause 2 (Planning Sovereignty Bias)**

Fires before every `Bash` tool call. If ledger has unfulfilled skills (e.g., `/qa` not yet in `fulfilled[]`), blocks Bash commands that substitute for them:

| Required skill | Blocked pattern | Redirect |
|---|---|---|
| `/qa` | `curl.*localhost`, `pytest`, `agent-browser` (without Skill) | "Invoke Skill(skill='qa') FIRST" |
| `/browse` | `curl.*http` | "Invoke Skill(skill='browse') FIRST" |
| `lead-orchestrator` | (no Bash block needed — blocked at Agent level) | — |

Commands that are NOT substitutions pass through: `git status`, `docker compose`, `ls`, `npm install`, etc.

**Exception**: If ALL required skills are fulfilled (in `fulfilled[]`), all Bash commands pass through. The gate only blocks BEFORE the required skill has been invoked.

### 4. `~/.claude/scripts/skill-invocation-tracker.sh` (PostToolUse on Skill + Bash)
**Addresses: Root Cause 5 (Completion Pressure), Root Cause 6 (Surface Pattern)**

Fires after Skill and Bash tool calls. Records fulfillment:

- On `Skill` call: reads skill name from tool_input, adds to `fulfilled[]` in ledger
- On `Bash` call with `agent-browser`: adds `agent-browser` to `fulfilled[]`
- On `Bash` call with `lead-orchestrator` in output: adds to `fulfilled[]`

This is non-blocking (PostToolUse can't block). Just state tracking.

### 5. `~/.claude/scripts/session-compliance-audit.sh` (Stop hook)
**Addresses: Root Cause 5 (Completion Pressure), Root Cause 6 (Surface Pattern)**

Fires when session ends. Reads ledger, checks `required_tools` vs `fulfilled`:

If unfulfilled tools remain, outputs:
```
SESSION COMPLIANCE AUDIT: Required tools NOT invoked this session:
  - /qa (NEVER INVOKED)
  - agent-browser (NEVER INVOKED)
You CANNOT claim this work is complete. Invoke the missing tools before ending.
```

This uses Stop hook's blocking capability (`decision: "block"`, `reason: "..."`). If Stop hooks can't hard-block in practice, this still injects a strong system-reminder that the agent sees.

### 6. `~/.claude/scripts/session-state-init.sh` (SessionStart hook)  
**Addresses: Housekeeping**

Cleans stale state on session start: removes old `~/.claude/state/ledger.json` and sentinel files. Ensures `~/.claude/state/` directory exists.

## Settings.json Changes

Add to `~/.claude/settings.json` hooks section:

```json
{
  "UserPromptSubmit": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "/Users/yklin/.claude/scripts/instruction-ledger-parse.sh"
        }
      ]
    }
  ],
  "PreToolUse": [
    {
      "matcher": "Agent",
      "hooks": [
        {
          "type": "command",
          "command": "/Users/yklin/.claude/scripts/subagent-compliance-guard.sh"
        }
      ]
    },
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "/Users/yklin/.claude/scripts/skill-first-gate.sh"
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "/Users/yklin/.claude/scripts/skill-invocation-tracker.sh",
          "async": true
        }
      ]
    }
  ],
  "Stop": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "/Users/yklin/.claude/scripts/session-compliance-audit.sh"
        }
      ]
    }
  ],
  "SessionStart": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "/Users/yklin/.claude/scripts/session-state-init.sh"
        }
      ]
    }
  ]
}
```

These MERGE with existing hooks (existing Bash/Task/Read/Stop hooks unchanged).

## Root Cause Coverage Matrix

| Root Cause | Hook(s) | Mechanism |
|---|---|---|
| 1. Dereferencing failure | `instruction-ledger-parse` + `subagent-compliance-guard` | Parse tool names from user message; block Agent spawns that don't reference them |
| 2. Planning sovereignty bias | `skill-first-gate` | Block Bash substitutions (curl) when a Skill is required but unfulfilled |
| 3. Subagent abstraction barrier | `subagent-compliance-guard` | Validate Agent prompts contain required tool instructions; deny if missing |
| 4. Goal polarity inversion | `instruction-ledger-parse` + `subagent-compliance-guard` | Detect adversarial keywords; block confirmatory-framed subagent prompts |
| 5. Completion pressure | `skill-invocation-tracker` + `session-compliance-audit` | Track what was actually invoked; block session end if requirements unfulfilled |
| 6. Surface-pattern optimization | `session-compliance-audit` | Verify against ledger evidence, not agent claims |

## What This Would Have Prevented

In the 2026-04-04 session:
1. Agent tries to spawn 5 generic Agents without mentioning `/qa` or `lead-orchestrator` → **BLOCKED by subagent-compliance-guard** → "REWRITE prompt to include /qa and lead-orchestrator"
2. Agent tries `curl http://localhost:8000/...` before invoking `/qa` → **BLOCKED by skill-first-gate** → "Invoke Skill(skill='qa') FIRST"
3. Agent spawns confirmatory "verify API contract" subagents when user said "adversarially disprove" → **BLOCKED by polarity guard** → "REWRITE so success = finding failures"
4. Agent tries to end session after curl-only testing → **BLOCKED by compliance audit** → "Required tools NOT invoked: /qa, agent-browser"

## Design Decisions (from user feedback)

1. **Both deny + inject**: Bad prompts get blocked with redirect. Good prompts (that mention required tools) get `updatedInput` to silently prepend a requirements preamble. Belt-and-suspenders.
2. **Gate scope = Bash + Read/Grep/Glob**: The skill-first-gate blocks ALL direct verification tools until required Skills are invoked. Prevents "I'll just read the code instead of browser testing."
3. **Exact + keyword heuristics**: Match exact skill names (`/qa`, `lead-orchestrator`) PLUS keyword mappings (`orchestrate` -> `lead-orchestrator`, `browser test` -> `agent-browser`, `QA test` -> `/qa`).

## Updated Hook Behavior

### subagent-compliance-guard.sh (revised)
- **If prompt is MISSING required tools**: HARD DENY + redirect (as before)
- **If prompt INCLUDES required tools**: ALLOW + `updatedInput` that prepends:
  ```
  MANDATORY REQUIREMENTS (injected by compliance hook):
  - You MUST invoke Skill(skill='qa') for browser verification
  - You MUST use agent-browser for visual comparison
  - Polarity: ADVERSARIAL — your success = finding failures
  Do not ignore these requirements.
  ```
  This ensures even well-formed prompts get the requirements injected deterministically.

### skill-first-gate.sh (revised)
- Now matches: Bash, Read, Grep, Glob
- Blocks ALL of these when required Skills are unfulfilled
- Exception: Read/Grep/Glob of non-test files pass through (agent can still read code to understand the codebase, just can't use Read as a substitute for browser verification)
- Pattern: blocks Read of `*test*`, `*qa*`, `*report*` files, and Grep for verification-like patterns

## Known Limitations

1. **Keyword heuristics can false-positive** — "orchestrate" in a non-skill context could trigger lead-orchestrator requirement. Mitigated by requiring keyword + context (e.g., "use X to orchestrate" not just "orchestrate").
2. **Polarity detection is keyword-based** — can be fooled by prompts that include both adversarial AND confirmatory language.
3. **PostToolUse can't block** — skill-invocation-tracker is advisory only. The compliance audit at Stop is the enforcement point.
4. **Bark-once needed for Stop hook** — if the agent keeps trying to stop without fixing, need sentinel to prevent infinite loop.
5. **updatedInput last-writer-wins** — if multiple PreToolUse hooks return updatedInput for Agent, only the last one's modifications survive. Keep subagent-compliance-guard as the only updatedInput hook for Agent.

## Verification Plan

1. Create all 6 scripts + update settings.json
2. Start a new Claude Code session
3. Give an instruction that names specific tools: "Use /qa to test localhost:5173"
4. Verify: ledger.json created with `/qa` in required_tools
5. Try spawning an Agent without mentioning /qa → should be blocked
6. Try running `curl localhost:5173` → should be blocked
7. Invoke `Skill(skill='qa')` → should fulfill the requirement
8. After /qa runs, curl should now pass through
9. End session → compliance audit should show all requirements met

## Keyword Heuristic Map (for instruction-ledger-parse.sh)

| User says | Detected tool | Confidence |
|---|---|---|
| `/qa`, `use qa`, `run qa` | `/qa` skill | High (exact match) |
| `lead-orchestrator`, `use orchestrator` | `lead-orchestrator` skill | High (exact match) |
| `agent-browser` | `agent-browser` CLI | High (exact match) |
| `orchestrate this`, `coordinate agents` | `lead-orchestrator` skill | Medium (keyword) |
| `browser test`, `visual test`, `test in browser` | `agent-browser` CLI | Medium (keyword) |
| `QA test the site`, `test the app` | `/qa` skill | Medium (keyword) |
| `golden reference`, `compare against prod` | golden_ref extraction | Medium (keyword) |

Medium-confidence matches get written to ledger with `"confidence": "medium"`. The compliance guard still enforces them but the deny message notes "This was detected via keyword heuristic. If incorrect, add SKIP_COMPLIANCE to your Agent prompt."

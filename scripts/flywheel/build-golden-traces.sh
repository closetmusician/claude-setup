#!/usr/bin/env bash
# ABOUTME: Builds the five Pillar III golden replay traces under $STATE/eval-corpus.
# ABOUTME: Deterministic fixture generator for harness replay --all-golden; no model calls.

set -uo pipefail
trap 'echo "[build-golden-traces] WARN: unexpected error on line $LINENO" >&2' ERR

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

if [[ -n "${HARNESS_GOV_STATE_DIR:-}" ]]; then
  STATE_DIR="$HARNESS_GOV_STATE_DIR"
elif [[ -n "${STATE:-}" ]]; then
  STATE_DIR="$STATE"
else
  STATE_DIR="$CLAUDE_DIR/.agents/claude-governance"
fi

GOLDEN_ROOT="${HARNESS_GOLDEN_DIR:-$STATE_DIR/eval-corpus/golden-traces}"
mkdir -p "$GOLDEN_ROOT"

write_trace() {
  local name="$1" steps="$2" decisions="$3"
  local dir="$GOLDEN_ROOT/$name"
  mkdir -p "$dir"
  printf '%s\n' "$steps" > "$dir/steps.jsonl"
  printf '%s\n' "$decisions" > "$dir/golden-decisions.jsonl"
}

write_trace "golden-healthy-orchestration" \
'{"seq":1,"hook":"scripts/completion-claim-guard.sh","stdin":{"transcript_path":"__TRACE_DIR__/healthy-transcript.jsonl","cwd":"/tmp","stop_hook_active":false}}' \
'{"seq":1,"decision":"silent"}'
cat > "$GOLDEN_ROOT/golden-healthy-orchestration/healthy-transcript.jsonl" <<'EOF'
{"type":"user","message":{"content":"Please inspect this repo."}}
{"type":"assistant","message":{"content":[{"type":"text","text":"I will inspect the repo and report findings without claiming completion."}]}}
EOF

write_trace "golden-qa-ownership" \
'{"seq":1,"hook":"scripts/governance/qa-artifact-ownership-guard.sh","requires_sentinel":true,"stdin":{"tool_name":"Write","agent_id":"","tool_input":{"file_path":"qa/FEAT-001/T-001-cycle-1.md","content":"orchestrator-authored QA artifact"}}}' \
'{"seq":1,"decision":"deny"}'

write_trace "golden-completion-block" \
'{"seq":1,"hook":"scripts/completion-claim-guard.sh","stdin":{"transcript_path":"__TRACE_DIR__/completion-transcript.jsonl","cwd":"/tmp","stop_hook_active":false}}' \
'{"seq":1,"decision":"block"}'
cat > "$GOLDEN_ROOT/golden-completion-block/completion-transcript.jsonl" <<'EOF'
{"type":"user","message":{"content":"Finish the task."}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Implementation complete. Everything is wired up and working. The task is done."}]}}
EOF

write_trace "golden-skill-routing" \
'{"seq":1,"hook":"scripts/skill-routing-guard.sh","stdin":{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test --body test"}}}' \
'{"seq":1,"decision":"deny"}'

write_trace "golden-clean-interactive" \
'{"seq":1,"hook":"scripts/completion-claim-guard.sh","stdin":{"transcript_path":"__TRACE_DIR__/clean-transcript.jsonl","cwd":"/tmp","stop_hook_active":false}}' \
'{"seq":1,"decision":"silent"}'
cat > "$GOLDEN_ROOT/golden-clean-interactive/clean-transcript.jsonl" <<'EOF'
{"type":"user","message":{"content":"What files are here?"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"I will list the files before drawing any conclusion."}]}}
EOF

( cd "$GOLDEN_ROOT" && find . -type f ! -name 'MANIFEST.sha256' | sort | xargs shasum -a 256 > MANIFEST.sha256 )

echo "golden traces built: $GOLDEN_ROOT"

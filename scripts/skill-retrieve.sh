#!/usr/bin/env bash
# ABOUTME: Pillar IV-B UserPromptSubmit hook — deterministic table nudge (step 1) then
# ABOUTME: semantic cosine retrieval (step 2) for long-tail skill discovery.
# ABOUTME: Step 1 delegates to skill-nudge.sh; table win is final (never double-fire).
# ABOUTME: Step 2 only runs when HARNESS_SKILL_SEMANTIC=1 AND state/skill-index.db exists.
# ABOUTME: Fail-open always: missing db/jq/flag/embedder → exit 0 silent. Budget ≤120ms.

set -uo pipefail
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Read stdin once ───────────────────────────────────────────────────────────
INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0

# ── Extract prompt (.prompt is the production UserPromptSubmit field; .user_prompt
#    is a legacy fallback retained for backward compat with older fixture payloads) ─
command -v jq >/dev/null 2>&1 || exit 0
PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // .user_prompt // empty' 2>/dev/null || true)"
[ -z "$PROMPT" ] && exit 0

# Guard: skip slash commands and very short prompts (mirrors skill-nudge.sh guards)
case "$PROMPT" in "/"*) exit 0 ;; esac
[ "${#PROMPT}" -lt 12 ] && exit 0

# ── Source event emitter ─────────────────────────────────────────────────────
LIB_DIR="${SCRIPT_DIR}/lib"
# shellcheck source=scripts/lib/emit-event.sh
source "${LIB_DIR}/emit-event.sh" 2>/dev/null || true

# ── Helper: output valid UserPromptSubmit JSON with additionalContext ─────────
# Purpose: wrap text as hookSpecificOutput.additionalContext JSON for Claude Code.
# Usage: _emit_context "some text"
# Gotchas: must be well-formed JSON; jq handles escaping.
_emit_context() {
  local text="$1"
  jq -cn --arg ctx "$text" --arg event "UserPromptSubmit" \
    '{"hookSpecificOutput":{"hookEventName":$event,"additionalContext":$ctx}}' 2>/dev/null || true
}

# ── Step 1: invoke skill-nudge.sh (table-first, deterministic) ───────────────
# Pass the prompt in the format skill-nudge.sh expects: {"prompt": "..."}
NUDGE_INPUT="$(jq -cn --arg p "$PROMPT" '{"prompt":$p}' 2>/dev/null || true)"
[ -z "$NUDGE_INPUT" ] && exit 0

NUDGE_OUTPUT="$(printf '%s' "$NUDGE_INPUT" | bash "${SCRIPT_DIR}/skill-nudge.sh" 2>/dev/null || true)"

if [ -n "$NUDGE_OUTPUT" ]; then
  # Table matched — wrap output as additionalContext, emit event, exit (table wins)
  _emit_context "$NUDGE_OUTPUT"
  # Emit skill_fire event (trigger: table)
  if declare -f emit_event >/dev/null 2>&1; then
    emit_event "skill_fire" '{"trigger":"table"}' source="skill-retrieve.sh" 2>/dev/null || true
  fi
  exit 0
fi

# ── Step 2: semantic retrieval (only if flag set AND db exists) ───────────────
[ "${HARNESS_SKILL_SEMANTIC:-}" = "1" ] || exit 0

# Resolve db path
CLAUDE_DIR="${HOME}/.claude"
DB="${SKILL_INDEX_DB:-${CLAUDE_DIR}/state/skill-index.db}"
[ -f "$DB" ] || exit 0

# Source project-root for governance state dir (embed cache)
# shellcheck source=scripts/lib/project-root.sh
source "${LIB_DIR}/project-root.sh" 2>/dev/null || true

_GOVERN_DIR="$(get_governance_state_dir 2>/dev/null || echo "${CLAUDE_DIR}/.agents/claude-governance")"
EMBED_CACHE_DIR="${_GOVERN_DIR}/embed-cache"
mkdir -p "$EMBED_CACHE_DIR" 2>/dev/null || true

# Run semantic retrieval via Python (same stub embedder as skill-index-build.sh)
SEMANTIC_RESULT="$(python3 - "$DB" "$EMBED_CACHE_DIR" "$PROMPT" <<'PYEOF' 2>/dev/null || true)"
import sys, os, re, hashlib, struct, sqlite3, json

db_path     = sys.argv[1]
cache_dir   = sys.argv[2]
prompt_text = sys.argv[3]

DIMS = 256
K    = 5
THRESHOLD = 0.35

def stub_embed(text, dims=DIMS):
    """
    Deterministic bag-of-words feature-hash embedding (identical to skill-index-build.sh).
    Purpose: produce a query vector for cosine-similarity search against indexed skill vecs.
    Usage: stub_embed("some query text") → list of floats len=dims
    Gotchas: deterministic offline only; cache by sha256 of prompt to avoid re-embedding.
    """
    tokens = re.findall(r'[a-z0-9]+', text.lower())
    vec = [0.0] * dims
    for tok in tokens:
        h = int(hashlib.sha256(tok.encode()).hexdigest(), 16) % dims
        vec[h] += 1.0
    norm = sum(v * v for v in vec) ** 0.5
    if norm > 0:
        vec = [v / norm for v in vec]
    return vec

def cosine(a, b):
    """Cosine similarity between two equal-length float lists."""
    dot  = sum(x * y for x, y in zip(a, b))
    na   = sum(x * x for x in a) ** 0.5
    nb   = sum(x * x for x in b) ** 0.5
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)

def blob_to_vec(blob, dims=DIMS):
    """Unpack a float32 BLOB back to a Python list."""
    count = len(blob) // 4
    return list(struct.unpack(f'{count}f', blob))

# Cache prompt embedding by sha256
prompt_hash = hashlib.sha256(prompt_text.encode()).hexdigest()
cache_file  = os.path.join(cache_dir, f"{prompt_hash}.json")

if os.path.isfile(cache_file):
    try:
        query_vec = json.loads(open(cache_file).read())
    except Exception:
        query_vec = None
else:
    query_vec = None

if query_vec is None:
    query_vec = stub_embed(prompt_text)
    try:
        open(cache_file, 'w').write(json.dumps(query_vec))
    except OSError:
        pass

# Load skill vectors and score
try:
    conn = sqlite3.connect(db_path)
    rows = conn.execute(
        "SELECT skill, description, vec FROM skills WHERE vec IS NOT NULL"
    ).fetchall()
    conn.close()
except Exception:
    sys.exit(0)

scored = []
for skill, desc, vec_blob in rows:
    if not vec_blob:
        continue
    try:
        skill_vec = blob_to_vec(vec_blob)
        score = cosine(query_vec, skill_vec)
        if score >= THRESHOLD:
            scored.append((score, skill, desc or ""))
    except Exception:
        continue

# Sort descending, take top-K
scored.sort(key=lambda x: -x[0])
top = scored[:K]

if not top:
    sys.exit(0)

# Output JSON array: [{skill, description, score}]
results = [
    {"skill": s, "description": d, "score": round(sc, 4)}
    for sc, s, d in top
]
print(json.dumps(results))
PYEOF

[ -z "$SEMANTIC_RESULT" ] && exit 0

# Parse results and build additionalContext block
CONTEXT_BLOCK="$(python3 - "$SEMANTIC_RESULT" <<'PYEOF' 2>/dev/null || true)"
import sys, json

raw = sys.argv[1]
try:
    results = json.loads(raw)
except Exception:
    sys.exit(0)

if not results:
    sys.exit(0)

lines = ["RELEVANT SKILLS (semantic match):"]
for item in results:
    skill = item.get("skill", "")
    desc  = item.get("description", "")
    score = item.get("score", 0)
    desc_short = desc[:100].rstrip()
    lines.append(f'{skill} — {desc_short} [Skill tool: "{skill}"]')

lines.append(
    'Deterministic routing table (rules/skill-routing.md) is authoritative; '
    'these are long-tail candidates the listing budget may have dropped.'
)

block = "\n".join(lines)
# Enforce <800 chars total
if len(block) > 800:
    block = block[:797] + "..."

print(block)
PYEOF

[ -z "$CONTEXT_BLOCK" ] && exit 0

# Emit additionalContext and per-skill events
_emit_context "$CONTEXT_BLOCK"

# Emit skill_fire events for each injected skill
SCORES="$(python3 -c "
import json, sys
try:
    results = json.loads('''$SEMANTIC_RESULT'''.replace(\"'\", '\"'))
    for r in results:
        print(r['skill'] + ':' + str(r['score']))
except:
    pass
" 2>/dev/null || true)"

if declare -f emit_event >/dev/null 2>&1; then
  while IFS=: read -r skill_name score_val; do
    [ -z "$skill_name" ] && continue
    PAYLOAD="$(jq -cn --arg t "semantic" --arg s "$score_val" '{"trigger":$t,"score":($s|tonumber)}' 2>/dev/null || echo '{"trigger":"semantic"}')"
    emit_event "skill_fire" "$PAYLOAD" source="skill-retrieve.sh" skill="$skill_name" 2>/dev/null || true
  done <<< "$SCORES"
fi

exit 0

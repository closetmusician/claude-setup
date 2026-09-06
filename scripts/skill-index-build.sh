#!/usr/bin/env bash
# ABOUTME: Pillar IV-B offline index builder — scans all SKILL.md files, embeds descriptions,
# ABOUTME: and upserts rows into state/skill-index.db (sqlite3). Re-runs are incremental:
# ABOUTME: only rows whose SKILL.md mtime > updated are re-embedded. Fail-open throughout.
# ABOUTME: Embedding: deterministic 256-dim bag-of-words stub (offline, stable, no API needed).

set -uo pipefail
trap 'exit 0' ERR

command -v sqlite3 >/dev/null 2>&1 || { echo "[skill-index-build] sqlite3 missing — skipping" >&2; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "[skill-index-build] python3 missing — skipping" >&2; exit 0; }

# ── State dir ───────���────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/project-root.sh
source "${SCRIPT_DIR}/lib/project-root.sh" 2>/dev/null || true

# skill-index.db lives in ~/.claude/state/ (top-level, accessible from all project hooks)
_HOME_CLAUDE="${HOME}/.claude"
DB="${SKILL_INDEX_DB:-${_HOME_CLAUDE}/state/skill-index.db}"
mkdir -p "$(dirname "$DB")" 2>/dev/null || true

LOG_TAG="[skill-index-build]"

# ── Delegate entirely to Python (avoids null-byte issues with binary BLOB) ────
python3 - "$DB" <<'PYEOF' 2>&1 | while IFS= read -r line; do echo "$LOG_TAG $line" >&2; done
import sys, os, re, hashlib, struct, sqlite3, datetime

db_path = sys.argv[1]
LOG_TAG = "[skill-index-build]"

# ── Schema ────────────────────────────────────────────────────────────────────
conn = sqlite3.connect(db_path)
conn.execute("""
    CREATE TABLE IF NOT EXISTS skills (
        skill       TEXT PRIMARY KEY,
        path        TEXT,
        description TEXT,
        vec         BLOB,
        embedder    TEXT,
        updated     TEXT
    )
""")
conn.commit()

# ── Stub embedder ─────────────────────────────────────────────────────────────
DIMS = 256
EMBEDDER_NAME = "stub-256dim"

def stub_embed(text, dims=DIMS):
    """
    Deterministic bag-of-words feature-hash embedding.
    Purpose: tokenize lowercase words, hash each token to a dimension bucket
      via sha256, count, then L2-normalize. Same text → same vector always.
    Usage: stub_embed("some description text") → list of floats, len=dims
    Gotchas: lexical only — no semantic understanding. Suitable for cosine
      ranking of ~60 short skill descriptions where vocabulary overlap is
      meaningful. Future: swap for real embedding API when key is available.
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

def vec_to_blob(vec):
    return struct.pack(f'{len(vec)}f', *vec)

# ── Frontmatter parser ────────��───────────────────────────────────────────────
def extract_field(fm_text, key):
    """
    Extract a YAML scalar for 'key:' from frontmatter text.
    Purpose: parse name/description from SKILL.md --- blocks without a full YAML lib.
    Usage: extract_field(fm, "description") → str or ""
    Gotchas: handles "key: value", key: "quoted", key: 'quoted'; not multi-line.
    """
    pattern = re.compile(rf'^{re.escape(key)}:\s*', re.MULTILINE)
    for line in fm_text.split('\n'):
        if pattern.match(line):
            val = pattern.sub('', line).strip()
            if len(val) >= 2 and ((val[0] == '"' and val[-1] == '"') or
                                   (val[0] == "'" and val[-1] == "'")):
                val = val[1:-1]
            return val
    return ""

def parse_frontmatter(skill_md_path):
    """
    Parse name and description from SKILL.md YAML frontmatter.
    Returns (name, description) or ("", "") on failure.
    """
    try:
        content = open(skill_md_path, encoding='utf-8', errors='replace').read()
    except OSError:
        return "", ""
    m = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
    if not m:
        return "", ""
    fm = m.group(1)
    name = extract_field(fm, "name")
    desc = extract_field(fm, "description")
    return name, desc

# ── Collect SKILL.md paths (deduped by realpath) ─────────────────────────────
def collect_skill_paths():
    """
    Glob ~/.claude/skills/*/SKILL.md and ~/Code/pm_os/skills/*/SKILL.md.
    Follow symlinks; deduplicate by resolved realpath.
    """
    seen = set()
    paths = []

    def scan(base):
        if not os.path.isdir(base):
            return
        try:
            entries = sorted(os.listdir(base))
        except OSError:
            return
        for name in entries:
            skill_md = os.path.join(base, name, "SKILL.md")
            if os.path.isfile(skill_md):
                try:
                    real = os.path.realpath(skill_md)
                except OSError:
                    real = skill_md
                if real not in seen:
                    seen.add(real)
                    paths.append(skill_md)

    home = os.path.expanduser("~")
    scan(os.path.join(home, ".claude", "skills"))
    scan(os.path.join(home, "Code", "pm_os", "skills"))
    return paths

# ── Main build loop ─────────────────────────────────────────────────────────
# Primary key (invocation key) = directory name (e.g. "ceo-review"), NOT the
# SKILL.md frontmatter `name:` field (which may differ, e.g. "plan-ceo-review").
# This matches the harness-doctor drift check and the skill routing table, which
# both use directory name as the canonical invocation key.
skill_paths = collect_skill_paths()
total = 0
updated = 0
skipped = 0
errors = 0
now = datetime.datetime.now(datetime.timezone.utc).isoformat()

for skill_md in skill_paths:
    if not os.path.isfile(skill_md):
        continue

    try:
        mtime = os.path.getmtime(skill_md)
    except OSError:
        errors += 1
        continue

    # Invocation key: directory name (always the canonical skill name)
    dir_name = os.path.basename(os.path.dirname(skill_md))
    if not dir_name:
        errors += 1
        continue

    _fm_name, desc = parse_frontmatter(skill_md)
    # Use dir_name as the index key; fall back to frontmatter name for embedding
    # text if description is absent, but never substitute frontmatter name as key.
    name = dir_name

    total += 1

    # Incremental check: skip if db row's updated timestamp >= file mtime
    row = conn.execute(
        "SELECT updated FROM skills WHERE skill=? LIMIT 1", (name,)
    ).fetchone()

    if row:
        try:
            existing_str = row[0]
            existing_dt = datetime.datetime.fromisoformat(existing_str)
            # fromisoformat with '+00:00' suffix produces a timezone-aware datetime;
            # naive fallback: assume UTC (the format we store)
            if existing_dt.tzinfo is None:
                existing_dt = existing_dt.replace(tzinfo=datetime.timezone.utc)
            existing_ts = existing_dt.timestamp()
            if existing_ts >= mtime:
                skipped += 1
                continue
        except (ValueError, TypeError):
            pass

    # Embed and upsert
    try:
        vec = stub_embed(desc or _fm_name or name)
        blob = vec_to_blob(vec)
        conn.execute("""
            INSERT OR REPLACE INTO skills(skill, path, description, vec, embedder, updated)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (name, skill_md, desc, blob, EMBEDDER_NAME, now))
        conn.commit()
        updated += 1
    except Exception as e:
        errors += 1
        continue

# ── Prune stale rows: remove any row whose key is no longer a valid directory name.
# This handles renames (e.g. frontmatter `name:` was previously used as key).
valid_keys = {os.path.basename(os.path.dirname(p)) for p in skill_paths}
try:
    existing_keys = {r[0] for r in conn.execute("SELECT skill FROM skills").fetchall()}
    stale = existing_keys - valid_keys
    pruned = 0
    for key in stale:
        conn.execute("DELETE FROM skills WHERE skill=?", (key,))
        pruned += 1
    if pruned:
        conn.commit()
except Exception:
    pruned = 0

conn.close()

final = sqlite3.connect(db_path).execute("SELECT count(*) FROM skills").fetchone()[0]
print(f"total={total} updated={updated} skipped={skipped} errors={errors} pruned={pruned} "
      f"db={db_path} embedder={EMBEDDER_NAME} final_rows={final}")
PYEOF

exit 0

#!/usr/bin/env bash
# ABOUTME: Shared helper that tells a code repo from a document workspace.
# ABOUTME: Sourced by governance hooks so code-repo gates stay off in folders like ~/Code/PM.
# ABOUTME: Order: .claude/workspace.json marker, .claude/phase.json, package manifests,
# ABOUTME: then the code-vs-doc file ratio from git ls-files; default is docs.
# ABOUTME: Spec: docs/plans/harness/governance-scope-spec.md §3 C1.

_WK_CODE_EXT='py|ts|tsx|js|jsx|go|rs|rb|java|kt|cs|swift|c|cpp|h|hpp|vue|svelte|dart|scala|clj|ex|exs|erl|hs|ml|php|sh'
_WK_DOC_EXT='md|markdown|docx|pptx|xlsx|pdf|csv|txt'

# workspace_root [dir]
# Purpose: resolve the repo root for <dir> (default $PWD); the dir itself when not in git.
# Usage: ROOT="$(workspace_root "$d")"
# Gotchas: <dir> must exist; callers pass the nearest existing parent of a new file.
workspace_root() {
  local d="${1:-$PWD}"
  git -C "$d" rev-parse --show-toplevel 2>/dev/null || (cd "$d" 2>/dev/null && pwd -P) || echo "$d"
}

# physical_path <path> [base]
# Purpose: absolute path with symlinks resolved, for a file that may not exist yet.
# Usage: F="$(physical_path "$FILE_PATH" "$CWD")"
# Gotchas: resolves the nearest existing ancestor (macOS /var -> /private/var, like git).
physical_path() {
  local p="$1" base="${2:-$PWD}" rest=""
  [[ "$p" == /* ]] || p="$base/$p"
  while [[ ! -d "$p" && "$p" != "/" ]]; do
    rest="/$(basename "$p")$rest"; p="$(dirname "$p")"
  done
  echo "$(cd "$p" 2>/dev/null && pwd -P)$rest"
}

# rel_to_root <physical-path> <root>
# Purpose: print the path relative to <root>; exit 1 when it is outside <root>.
# Usage: REL="$(rel_to_root "$F" "$ROOT")" || exit 0
# Gotchas: both arguments must already be physical paths.
rel_to_root() {
  case "$1" in
    "$2"/*) echo "${1#"$2"/}" ;;
    *) return 1 ;;
  esac
}

# has_segment <rel-path> <name>...
# Purpose: exit 0 when any DIRECTORY segment of <rel-path> equals one of the names.
# Usage: has_segment "$REL" qa logs && exit 0
# Gotchas: whole-segment match only, so "notqa/x" never matches "qa".
has_segment() {
  local rel="$1" seg name; shift
  local dir; dir="$(dirname "$rel")"
  [[ "$dir" == "." ]] && return 1
  local IFS='/'
  for seg in $dir; do
    for name in "$@"; do [[ "$seg" == "$name" ]] && return 0; done
  done
  return 1
}

# get_workspace_kind [dir]
# Purpose: print "code" or "docs" for the repo that holds <dir>.
# Usage: KIND="$(get_workspace_kind "$PWD")"
# Gotchas: an invalid marker prints a note on stderr and falls through to detection.
get_workspace_kind() {
  local root marker kind f code docs
  root="$(workspace_root "${1:-$PWD}")"
  marker="$root/.claude/workspace.json"
  if [[ -f "$marker" ]]; then
    kind="$(jq -r '.kind // empty' "$marker" 2>/dev/null)"
    case "$kind" in
      code|docs) echo "$kind"; return 0 ;;
      *) echo "workspace-kind: ignoring invalid kind '${kind}' in $marker" >&2 ;;
    esac
  fi
  [[ -f "$root/.claude/phase.json" ]] && { echo code; return 0; }
  for f in package.json pyproject.toml setup.py requirements.txt go.mod Cargo.toml pom.xml \
           build.gradle build.gradle.kts Gemfile composer.json mix.exs Package.swift; do
    [[ -e "$root/$f" ]] && { echo code; return 0; }
  done
  for f in "$root"/*.sln "$root"/*.csproj; do
    [[ -e "$f" ]] && { echo code; return 0; }
  done
  # File ratio: only meaningful inside a git repo. Files under docs/, doc/, node_modules/
  # and vendor/ do not count: a code repo with a large docs/ folder is still a code repo.
  if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    local files
    files="$(git -C "$root" ls-files 2>/dev/null | grep -vE '(^|/)(docs?|node_modules|vendor)/' || true)"
    code="$(printf '%s\n' "$files" | grep -ciE "\.(${_WK_CODE_EXT})$" || true)"
    docs="$(printf '%s\n' "$files" | grep -ciE "\.(${_WK_DOC_EXT})$" || true)"
    if [[ "${code:-0}" -gt 0 && "${code:-0}" -ge "${docs:-0}" ]]; then
      echo code; return 0
    fi
  fi
  echo docs
}

# is_vibe_repo [dir]
# Purpose: exit 0 when the repo holding <dir> is VIBE-governed (.claude/phase.json).
# Usage: is_vibe_repo "$PWD" || exit 0
# Gotchas: a docs marker does not override phase.json here; phase.json means VIBE.
is_vibe_repo() {
  [[ -f "$(workspace_root "${1:-$PWD}")/.claude/phase.json" ]]
}

# get_workspace_doc_paths [dir]
# Purpose: print the marker's allow_doc_paths entries (repo-relative prefixes), one per line.
# Usage: while IFS= read -r p; do ...; done < <(get_workspace_doc_paths "$PWD")
# Gotchas: prints nothing when there is no marker or no array.
get_workspace_doc_paths() {
  local marker; marker="$(workspace_root "${1:-$PWD}")/.claude/workspace.json"
  [[ -f "$marker" ]] && jq -r '.allow_doc_paths // [] | .[]' "$marker" 2>/dev/null
  return 0
}

# is_code_ext <path>
# Purpose: exit 0 when <path> has a source-code extension (shared list).
# Usage: is_code_ext "$FILE" && CAP=8192
# Gotchas: case-insensitive; includes sh.
is_code_ext() {
  printf '%s' "$1" | grep -qiE "\.(${_WK_CODE_EXT})$"
}

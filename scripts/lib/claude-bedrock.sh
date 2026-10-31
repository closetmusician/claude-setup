#!/usr/bin/env bash
# ABOUTME: Bedrock env setup and model alias mapper for headless claude launches.
# ABOUTME: Exports CLAUDE_CODE_USE_BEDROCK=1, AWS_PROFILE=dil-team-boards, AWS_REGION=us-west-2.
# ABOUTME: Maps model aliases (opus/sonnet/haiku) to full Bedrock IDs, strips [1m] suffix.
# ABOUTME: Fails closed (exit 3) when AWS SSO token is expired. Never falls back to claude.ai.
# ABOUTME: Usage: source scripts/lib/claude-bedrock.sh && claude_bedrock <model> [args...],
# ABOUTME:    or: scripts/lib/claude-bedrock.sh -p --model opus <<< "prompt"

set -euo pipefail

# Purpose: Export required environment variables for Bedrock access.
# Usage: Automatically run when sourced or executed.
# Gotchas: Always sets these three vars; does not preserve existing values.
export CLAUDE_CODE_USE_BEDROCK=1
export AWS_PROFILE=dil-team-boards
export AWS_REGION=us-west-2

# Purpose: Map model alias to full Bedrock ID, strip [1m] suffix if present.
# Usage: model_id="$(map_model_alias opus)"
# Gotchas: claude.ai names (claude-opus-5-5, claude-sonnet-5, claude-haiku-4-5) map too, because
#          they are invalid on Bedrock (400). IDs verified 2026-10-25 via list-inference-profiles.
#          Other values pass through with any [1m] suffix stripped.
map_model_alias() {
  local model="$1"
  case "$model" in
    opus|claude-opus-5-5)
      echo "us.anthropic.claude-opus-5-5"
      ;;
    sonnet|claude-sonnet-5)
      echo "us.anthropic.claude-sonnet-5"
      ;;
    haiku|claude-haiku-4-5)
      echo "us.anthropic.claude-haiku-4-5-20251001-v1:0"
      ;;
    *)
      # Strip [1m] suffix if present (happens with $ANTHROPIC_DEFAULT_*_MODEL env vars)
      echo "$model" | sed 's/\[1m\]$//'
      ;;
  esac
}

# Purpose: Check if AWS SSO token is expired; fail closed if it is.
# Usage: Called automatically when sourced or executed.
# Gotchas: Checks ~/.aws/sso/cache/*.json for expiresAt. If all tokens expired or no
#          cache found, exits 3 with stderr message. Test override: _TEST_SSO_CACHE_DIR.
check_sso_token() {
  local sso_cache_dir="${_TEST_SSO_CACHE_DIR:-$HOME/.aws/sso/cache}"

  if [[ ! -d "$sso_cache_dir" ]]; then
    echo "ERROR: AWS SSO cache not found at $sso_cache_dir. Run 'aws sso login --profile dil-team-boards'." >&2
    return 3
  fi

  local now_epoch
  now_epoch="$(date -u +%s)"

  local has_valid_token=0

  while IFS= read -r cache_file; do
    if [[ ! -f "$cache_file" ]]; then
      continue
    fi

    local expires_at
    expires_at="$(jq -r '.expiresAt // empty' "$cache_file" 2>/dev/null || echo "")"

    if [[ -z "$expires_at" ]]; then
      continue
    fi

    local expires_epoch
    expires_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$expires_at" +%s 2>/dev/null || \
                     date -u -d "$expires_at" +%s 2>/dev/null || echo "0")"

    if [[ "$expires_epoch" -gt "$now_epoch" ]]; then
      has_valid_token=1
      break
    fi
  done < <(find "$sso_cache_dir" -name "*.json" -type f 2>/dev/null)

  if [[ $has_valid_token -eq 0 ]]; then
    echo "ERROR: AWS SSO token expired. Run 'aws sso login --profile dil-team-boards' to refresh." >&2
    return 3
  fi

  return 0
}

# Purpose: Main function — map model alias and invoke claude with Bedrock.
# Usage: claude_bedrock <model>  (just map and echo)
#    OR: claude_bedrock -p --model opus <<< "prompt"  (invoke claude)
# Gotchas: Single non-flag arg = map and echo. Multiple args or flags = invoke claude.
claude_bedrock() {
  # Special case: single arg that's not a flag = just map and echo
  if [[ $# -eq 1 && ! "$1" =~ ^- ]]; then
    map_model_alias "$1"
    return 0
  fi

  local args=()
  local i=1

  # Parse args to find --model and map it
  while [[ $i -le $# ]]; do
    local arg="${!i}"
    i=$((i + 1))

    if [[ "$arg" == "--model" && $i -le $# ]]; then
      local next_arg="${!i}"
      i=$((i + 1))
      local mapped_model
      mapped_model="$(map_model_alias "$next_arg")"
      args+=("--model" "$mapped_model")
    else
      args+=("$arg")
    fi
  done

  claude "${args[@]}"
}

# Purpose: Auto-check SSO token when sourced or executed.
# Usage: Automatic.
# Gotchas: Exits 3 if token expired. Only runs if not in test mode without a cache dir.
if [[ -z "${_TEST_SSO_CACHE_DIR:-}" ]] || [[ -d "${_TEST_SSO_CACHE_DIR:-}" ]]; then
  check_sso_token || exit $?
fi

# Purpose: If executed (not sourced), run claude_bedrock with all args.
# Usage: scripts/lib/claude-bedrock.sh -p --model opus <<< "prompt"
# Gotchas: Detects execution by checking if $0 contains the script name.
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  claude_bedrock "$@"
fi

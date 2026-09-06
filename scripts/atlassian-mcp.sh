#!/bin/bash
# ABOUTME: Wrapper script that sources shell profile before launching mcp-atlassian.
# Ensures ATLASSIAN_API_TOKEN is available even when Claude Code doesn't
# inherit the full shell environment. Works across bash/zsh users.

# Source the user's shell profile to pick up env vars
for profile in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
  if [ -f "$profile" ]; then
    source "$profile" 2>/dev/null
    break
  fi
done

# Find uvx — check common locations then PATH
UVX=""
for candidate in "$HOME/.local/bin/uvx" "/opt/homebrew/bin/uvx" "/usr/local/bin/uvx"; do
  if [ -x "$candidate" ]; then
    UVX="$candidate"
    break
  fi
done
if [ -z "$UVX" ]; then
  UVX=$(command -v uvx 2>/dev/null)
fi
if [ -z "$UVX" ]; then
  echo "ERROR: uvx not found. Install uv first: https://docs.astral.sh/uv/" >&2
  exit 1
fi

exec "$UVX" mcp-atlassian "$@"

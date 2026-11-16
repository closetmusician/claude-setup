#!/usr/bin/env bash
# ABOUTME: Shared functions for arm D stage scripts (spec, review, final).
# ABOUTME: Safe template filling with Python str.replace, and JSON-block extraction from Codex output.
# ABOUTME: Strips ABOUTME lines from filled prompts so Codex does not read them.
# ABOUTME: Written 2026-11-15. Sourced by armd-spec.sh, armd-review.sh, armd-final.sh.
# ABOUTME: Usage: source this file, then call fill_template or extract_json.

# Purpose: fill a prompt template with placeholders, safe for paths and special chars.
# Usage:   fill_template <template> <output> <pairs...>
# Gotchas: uses Python str.replace, safe for /, $, \, @. Strips leading ABOUTME lines.
fill_template() {
  local template="$1"
  local output="$2"
  shift 2

  python3 - "$template" "$@" > "$output" <<'FILL_PYTHON'
import sys
template_path = sys.argv[1]
with open(template_path) as f:
    text = f.read()

# Strip leading ABOUTME lines
lines = text.split('\n')
while lines and lines[0].startswith('# ABOUTME:'):
    lines.pop(0)
text = '\n'.join(lines)

# Replace placeholders
pairs = sys.argv[2:]
for i in range(0, len(pairs), 2):
    if i + 1 < len(pairs):
        key = '{{' + pairs[i] + '}}'
        value = pairs[i + 1]
        text = text.replace(key, value)

print(text, end='')
FILL_PYTHON
}

# Purpose: pull one key out of the LAST ```json block in a Codex output file.
# Usage:   val=$(extract_json <file> <key>)   # prints the value as JSON, or PARSE_FAIL
# Gotchas: PARSE_FAIL means no block, bad JSON or a missing key; an empty list is a valid value.
extract_json() {
  python3 - "$1" "$2" <<'EXTRACT_PYTHON'
import sys, re, json
try:
    text = open(sys.argv[1]).read()
    block = re.findall(r'```json\s*\n(.*?)\n\s*```', text, re.DOTALL)[-1]
    print(json.dumps(json.loads(block)[sys.argv[2]]))
except Exception:
    print('PARSE_FAIL')
EXTRACT_PYTHON
}

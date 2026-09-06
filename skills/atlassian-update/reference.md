<!-- ABOUTME:
  atlassian-update reference.md — full procedural detail for all phases.
  SKILL.md holds the session-facing summary; this file holds every
  curl/python command needed to execute each phase.
  Imported by SKILL.md at runtime for executor reference.
-->

# Atlassian Update — Procedural Reference

> **Placeholder convention:** All code examples below use `PAGE_ID` as a literal placeholder.
> After extracting the real numeric page ID in Phase 0, substitute it in every command.
> Same applies to `CURRENT_VERSION_PLUS_1` and `PAGE_TITLE` in Phase 4.

---

## Phase 0: Parse Input

Extract the numeric page ID from the user's input:
- From URL: `https://example.atlassian.net/wiki/spaces/XXX/pages/PAGE_ID/...` → extract `PAGE_ID`
- From raw ID: use directly

```bash
echo "URL" | grep -oP '(?<=pages/)\d+'
```

---

## Phase 1: Pre-Flight — Snapshot Current State

### Step 1.1: Fetch page metadata + body

```bash
bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN \
  "https://example.atlassian.net/wiki/rest/api/content/PAGE_ID?expand=body.storage,version,space" \
  > /tmp/confluence-page-PAGE_ID.json'
```

Extract and store: `version.number`, `title`, `space.key`, `body.storage.value`.

### Step 1.2: Catalog all inline comment markers

```bash
python3 -c "
import json, re, sys

with open('/tmp/confluence-page-PAGE_ID.json') as f:
    data = json.load(f)

body = data['body']['storage']['value']
version = data['version']['number']
title = data['title']

pattern = r'<ac:inline-comment-marker ac:ref=\"([^\"]+)\">(.*?)</ac:inline-comment-marker>'
markers = re.findall(pattern, body, re.DOTALL)

print(f'Page: {title}')
print(f'Version: {version}')
print(f'Body length: {len(body)} chars')
print(f'Inline comment markers: {len(markers)}')
print()

catalog = []
for uuid, text in markers:
    catalog.append({'ref': uuid, 'text': text[:100]})
    print(f'  [{uuid}] {text[:80]}')

with open('/tmp/confluence-markers-PAGE_ID.json', 'w') as f:
    json.dump({'version': version, 'title': title, 'marker_count': len(markers), 'markers': catalog}, f, indent=2)
"
```

### Step 1.3: Fetch comment objects (independent verification source)

```bash
bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN \
  "https://example.atlassian.net/wiki/rest/api/content/PAGE_ID/child/comment?expand=extensions.inlineProperties,body.view&limit=100&start=0" \
  > /tmp/confluence-comments-PAGE_ID.json'
```

If `size` >= `limit`, paginate with `start=100, start=200, ...` until all fetched.

```bash
python3 -c "
import json

with open('/tmp/confluence-comments-PAGE_ID.json') as f:
    data = json.load(f)

with open('/tmp/confluence-markers-PAGE_ID.json') as f:
    catalog = json.load(f)

comments = data.get('results', [])
body_refs = {m['ref'] for m in catalog['markers']}

inline_refs = set()
page_comments = 0
for c in comments:
    ext = c.get('extensions', {})
    inline = ext.get('inlineProperties', {})
    ref = inline.get('markerRef')
    if ref:
        inline_refs.add(ref)
    else:
        page_comments += 1

print(f'Total comments: {len(comments)}')
print(f'Inline comments: {len(inline_refs)} (unique marker refs)')
print(f'Page-level comments: {page_comments}')
print()

orphaned = inline_refs - body_refs
unlinked = body_refs - inline_refs
print(f'Markers in body with comments: {len(body_refs & inline_refs)}')
print(f'Already-orphaned comments (ref not in body): {len(orphaned)}')
print(f'Markers in body without comments: {len(unlinked)}')

if orphaned:
    print(f'  WARNING: {len(orphaned)} comments already orphaned before our edit')
    for ref in orphaned:
        print(f'    - {ref}')

ref_to_text = {m['ref']: m['text'][:200] for m in catalog['markers']}
print()
print('=== Comment <> Context Correlation ===')
for c in comments:
    ext = c.get('extensions', {})
    ref = ext.get('inlineProperties', {}).get('markerRef')
    if not ref:
        continue
    comment_body = c.get('body', {}).get('view', {}).get('value', '(no body)')
    anchored = ref_to_text.get(ref, '(marker not in body)')
    print(f'  Marker: {ref}')
    print(f'  Anchored text: {anchored}')
    print(f'  Comment: {comment_body[:300]}')
    print()
"
```

### Step 1.4: Report pre-flight summary

Display: page title, version, body size, marker count, comment count, pre-existing orphans,
cross-reference health, comment↔context correlation table.

**STOP HERE** if the user hasn't yet described what changes to make.

---

## Phase 2: Apply Edits

### Step 2.1: Choose edit strategy

| Strategy | When | Risk |
|---|---|---|
| **Targeted find/replace** | Specific text changes | LOW |
| **Section replacement** | Rewriting between headings | MEDIUM |
| **Full body replacement** | Complete rewrite | HIGH — require explicit user approval |

### Step 2.2: Execute edits

**Targeted find/replace (preferred):**
```python
import re

old_body = body
new_body = body

for old_text, new_text in replacements:
    markers_in_range = re.findall(
        r'<ac:inline-comment-marker ac:ref="[^"]+">.*?</ac:inline-comment-marker>',
        old_text, re.DOTALL
    )
    if markers_in_range:
        print(f"WARNING: Replacement touches {len(markers_in_range)} marker(s)")
        # DO NOT PROCEED without user confirmation
    new_body = new_body.replace(old_text, new_text, 1)
```

**Section replacement:** Identify section boundaries (heading to next heading of same/higher
level). Extract markers from old section; user must indicate where markers should land in
new section. Re-inject markers into new section content.

**Full body replacement:** Extract all markers from old body with surrounding context; for
each marker, find best matching location in new body; re-inject markers. Require explicit
user approval before proceeding.

### Step 2.3: Write edited body to temp file

```bash
python3 -c "
# ... apply edits ...
with open('/tmp/confluence-newbody-PAGE_ID.html', 'w') as f:
    f.write(new_body)
"
```

---

## Phase 3: Pre-Submit Validation (MANDATORY — never skip)

### Step 3.1: Marker integrity check

```bash
python3 -c "
import json, re, sys

with open('/tmp/confluence-markers-PAGE_ID.json') as f:
    catalog = json.load(f)

with open('/tmp/confluence-newbody-PAGE_ID.html') as f:
    new_body = f.read()

new_markers = re.findall(
    r'<ac:inline-comment-marker ac:ref=\"([^\"]+)\">(.*?)</ac:inline-comment-marker>',
    new_body, re.DOTALL
)
new_refs = {ref for ref, _ in new_markers}
old_refs = {m['ref'] for m in catalog['markers']}

missing = old_refs - new_refs
added = new_refs - old_refs

print(f'Original markers: {len(old_refs)}')
print(f'New body markers: {len(new_refs)}')
print(f'Missing markers:  {len(missing)}')
print(f'Added markers:    {len(added)}')
print()

if missing:
    print('BLOCKED — these markers would be lost:')
    for ref in missing:
        orig = next((m for m in catalog['markers'] if m['ref'] == ref), None)
        print(f'  [{ref}] {orig[\"text\"][:80] if orig else \"unknown\"}')
    print()
    print('CANNOT PROCEED. Fix the edit to preserve these markers.')
    sys.exit(1)
else:
    print('ALL MARKERS PRESERVED — safe to submit.')
sys.exit(0)
"
```

**HARD GATE: If any markers are missing, DO NOT submit.** Options: (1) revise edit to
preserve markers, (2) user explicitly acknowledges orphaning, (3) abort.

### Step 3.2: Structural validation

```bash
python3 -c "
import re

with open('/tmp/confluence-newbody-PAGE_ID.html') as f:
    body = f.read()

opens = len(re.findall(r'<ac:inline-comment-marker', body))
closes = len(re.findall(r'</ac:inline-comment-marker>', body))
print(f'Marker opens: {opens}, closes: {closes}')
if opens != closes:
    print('ERROR: Mismatched marker tags — would corrupt page')
    exit(1)

nested = re.findall(
    r'<ac:inline-comment-marker[^>]*>(?:(?!</ac:inline-comment-marker>).)*<ac:inline-comment-marker',
    body, re.DOTALL
)
if nested:
    print(f'ERROR: {len(nested)} nested marker(s) detected — would corrupt page')
    exit(1)

print('Structural validation passed.')
"
```

---

## Phase 4: Submit Update

```bash
bash -c 'source ~/.zshrc 2>/dev/null

PAGE_ID=PAGE_ID
VERSION=CURRENT_VERSION_PLUS_1
TITLE="PAGE_TITLE"

BODY_JSON=$(python3 -c "
import json
with open(\"/tmp/confluence-newbody-PAGE_ID.html\") as f:
    body = f.read()
print(json.dumps(body))
")

curl -sf -X PUT \
  -u dev@example.com:$ATLASSIAN_API_TOKEN \
  -H "Content-Type: application/json" \
  "https://example.atlassian.net/wiki/rest/api/content/$PAGE_ID" \
  -d "{
    \"id\": \"$PAGE_ID\",
    \"type\": \"page\",
    \"title\": \"$TITLE\",
    \"version\": {\"number\": $VERSION},
    \"body\": {
      \"storage\": {
        \"value\": $BODY_JSON,
        \"representation\": \"storage\"
      }
    }
  }" | python3 -c "
import json, sys
resp = json.load(sys.stdin)
print(f\"Updated: {resp.get(\"title\")}\")
print(f\"New version: {resp.get(\"version\", {}).get(\"number\")}\")
print(f\"URL: {resp.get(\"_links\", {}).get(\"base\", \"\")}{resp.get(\"_links\", {}).get(\"webui\", \"\")}\")
"'
```

If PUT fails: `409 Conflict` = version mismatch, re-fetch + retry from Phase 1.
`400 Bad Request` = body HTML malformed. `403 Forbidden` = insufficient permissions.
Do NOT retry blindly — report and ask.

---

## Phase 5: Post-Verification (MANDATORY — never skip)

### Step 5.1: Re-fetch and verify markers

```bash
bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN \
  "https://example.atlassian.net/wiki/rest/api/content/PAGE_ID?expand=body.storage,version" \
  > /tmp/confluence-postverify-PAGE_ID.json'
```

```bash
python3 -c "
import json, re

with open('/tmp/confluence-markers-PAGE_ID.json') as f:
    original = json.load(f)

with open('/tmp/confluence-postverify-PAGE_ID.json') as f:
    updated = json.load(f)

body = updated['body']['storage']['value']
new_markers = re.findall(r'<ac:inline-comment-marker ac:ref=\"([^\"]+)\"', body)
new_refs = set(new_markers)
old_refs = {m['ref'] for m in original['markers']}

missing = old_refs - new_refs
print(f'Original markers: {len(old_refs)}')
print(f'Post-update markers: {len(new_refs)}')
print(f'Missing: {len(missing)}')

if missing:
    print()
    print('POST-VERIFICATION FAILED — markers lost during update:')
    for ref in missing:
        orig = next((m for m in original['markers'] if m['ref'] == ref), None)
        print(f'  [{ref}] {orig[\"text\"][:80] if orig else \"unknown\"}')
    print()
    print('Comments are now orphaned. Consider reverting to version', original['version'])
else:
    print('POST-VERIFICATION PASSED — all markers intact.')
"
```

### Step 5.2: Re-fetch comments and verify count

```bash
bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN \
  "https://example.atlassian.net/wiki/rest/api/content/PAGE_ID/child/comment?limit=0" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f\"Comments after update: {data.get(\"size\", 0)}\")
"'
```

Compare with pre-flight count — they should match exactly.

---

## Phase 6: Comment Operations (Optional)

Enter this phase only when the user wants to read, reply to, or resolve comments.

### Step 6.1: Read comments

The correlation table from Phase 1.3 already provides comment text matched to anchored content.
For full untruncated text:

```bash
curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN \
  "https://example.atlassian.net/wiki/rest/api/content/PAGE_ID/child/comment?expand=extensions.inlineProperties,body.view&limit=100&start=0"
```

### Step 6.2: Reply to a comment

```bash
COMMENT_ID=<target_comment_id>

curl -X POST \
  -u dev@example.com:$ATLASSIAN_API_TOKEN \
  -H "Content-Type: application/json" \
  "https://example.atlassian.net/wiki/rest/api/content" \
  -d "{
    \"type\": \"comment\",
    \"container\": {\"id\": \"PAGE_ID\", \"type\": \"page\"},
    \"ancestors\": [{\"id\": \"$COMMENT_ID\"}],
    \"body\": {
      \"storage\": {
        \"value\": \"<p>Reply text here</p>\",
        \"representation\": \"storage\"
      }
    }
  }"
```

### Step 6.3: Resolve a comment

Use v2 API (supports resolution status natively):

```bash
COMMENT_ID=<target_comment_id>

# Confirm it exists
curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN \
  "https://example.atlassian.net/wiki/api/v2/inline-comments/$COMMENT_ID"

# Resolve it
curl -X PUT \
  -u dev@example.com:$ATLASSIAN_API_TOKEN \
  -H "Content-Type: application/json" \
  "https://example.atlassian.net/wiki/api/v2/inline-comments/$COMMENT_ID" \
  -d "{\"status\": \"resolved\"}"
```

**Fallback** (if v2 returns 404):
```bash
curl -X PUT \
  -u dev@example.com:$ATLASSIAN_API_TOKEN \
  -H "Content-Type: application/json" \
  "https://example.atlassian.net/wiki/rest/api/content/$COMMENT_ID/property/resolved" \
  -d "{\"key\": \"resolved\", \"value\": {\"status\": true}}"
```

**Always ask user before resolving.** Resolving affects other collaborators' view of the page.

---

## Phase 7: Cleanup

```bash
rm -f /tmp/confluence-page-PAGE_ID.json \
      /tmp/confluence-comments-PAGE_ID.json \
      /tmp/confluence-markers-PAGE_ID.json \
      /tmp/confluence-newbody-PAGE_ID.html \
      /tmp/confluence-postverify-PAGE_ID.json
```

---

## Revert Procedure

If post-verification fails and markers were lost:

```bash
bash -c 'source ~/.zshrc 2>/dev/null

# Fetch the previous version body
curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN \
  "https://example.atlassian.net/wiki/rest/api/content/PAGE_ID?expand=body.storage,version&status=historical&version=ORIGINAL_VERSION" \
  > /tmp/confluence-revert-PAGE_ID.json'
```

Then re-submit with the old body and an incremented version number (creating a new version
that matches the old content). This restores the markers and re-anchors the comments.

**Always ask user before reverting.**

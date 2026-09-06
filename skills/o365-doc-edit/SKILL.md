---
name: o365-doc-edit
description: "Safe agentic editing for Word/PowerPoint/Excel documents in SharePoint/OneDrive. Prefer Office-session edits for open Word/PPT files, repair PM-OS browser auth before use, and fall back to guarded OOXML/Graph writes only when appropriate."
---

# O365 Document Edit Skill

Use this skill when an agent must create, edit, comment on, or verify Office
documents in SharePoint/OneDrive.

## Safety Boundary

Never use destructive file operations as lock recovery:

- no `DELETE` against original driveItem/listItem/SharePoint file URLs;
- no recycle, restore, move, rename-overwrite, swap, copy-over-original;
- no `CreateCopyJobs`, `BypassSharedLock`, or `Prefer: bypass-shared-lock`;
- no raw Graph replacement after repeated `423 Locked`.

Allowed cleanup for self-inflicted locks is narrow: close only this workflow's
browser/Office session for the exact document, cancel only this workflow's upload
session URL, wait 15-30 seconds, retry one guarded write, then stop and preserve
the draft.

## Routing

Prefer, in order:

1. `pm-os-bridge` Office.js add-in when it is open in the current Word/PowerPoint
   session. Use `bin/office-bridge-command.js` to queue deterministic in-session
   edits and Word comments through Office.js.
2. `bin/office-browser-edit.js` for small visible Word/PowerPoint Online edits.
   This tool owns the `~/.agent-browser/pm-os` profile lifecycle in execute mode,
   verifies visible anchors, and stops if the browser state is ambiguous.
3. Guarded storage edits only when the file is not open or Office-session editing
   cannot perform the requested operation:
   - Word/PPT/Excel OOXML comments and text: `bin/ooxml-surgery.py`
   - PowerPoint structural edits: `bin/graph-edit-pptx.js`
   - Excel cell/table writes: `bin/graph-workbook.js`
   - Whole-file upload: `bin/graph-file-ops.js upload`

## Auth Chain

Before Office Online browser edits:

1. Run `node ~/Code/pm_os/bin/ensure-tokens.js`.
2. Run the browser edit command normally. It closes any stale `agent-browser`
   daemon by default so `--profile ~/.agent-browser/pm-os` is honored.
3. If it returns `needs-auth`, repair the browser profile:
   - run `agent-browser close`;
   - run `agent-browser --profile ~/.agent-browser/pm-os --headed open "https://acme.okta.com/"`;
   - ask the user to complete Okta/Microsoft MFA in that headed browser;
   - after confirmation, run `agent-browser close`;
   - rerun the original browser edit command.

Do not assume FOCI/Graph tokens are browser cookies. FOCI proves Graph auth; the
Word Online browser path still needs the persistent PM-OS browser profile.

## Common Word Litmus Flow

For a request like "insert a TLDR under the title and add three comments":

1. Extract/read the document without modifying it:
   `PM_OS_AGENT=1 ~/Code/pm_os/bin/ooxml-surgery.py --url "$URL" --action extract-text --agent-mode`
2. Insert the visible TLDR through Office Online when the doc is open:
   `node ~/Code/pm_os/bin/office-browser-edit.js --execute --url "$URL" --action word-insert-after-anchor --anchor "$TITLE" --text "$TLDR"`
3. Add Word comments through `pm-os-bridge` if the add-in is active:
   `node ~/Code/pm_os/bin/office-bridge-command.js --command '{"version":1,"operations":[{"id":"comment-1","action":"word.addCommentToAnchor","anchor":{"text":"ANCHOR"},"comment":"COMMENT"}]}'`
   If not active, use guarded OOXML comments only after no Office-session lock remains:
   `PM_OS_AGENT=1 ~/Code/pm_os/bin/ooxml-surgery.py --url "$URL" --action add-comment --anchor "$ANCHOR" --comment "$COMMENT" --author "PM-OS Agent" --email "$EMAIL"`
4. Self-audit with read-only checks:
   - `extract-text` must contain the inserted TLDR and bullets once;
   - `list-comments` must show exactly the requested comments;
   - no destructive operation should appear in shell history, command plan, or tool output.

If a guarded OOXML upload returns `423 Locked`, preserve the local edited output
and finish through the active Office session if possible. Do not ask everyone to
close the document as the default path.

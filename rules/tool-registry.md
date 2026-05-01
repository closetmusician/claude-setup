# Tool Registry

There are no general-purpose file I/O operations in this environment. The tools below are the ONLY permitted way to touch Office documents, Excel files, and SharePoint resources.

You don't download Office files to process them locally unless the Office-session paths cannot do the job. For Word/PowerPoint edits, prefer in-session editing first so Office owns coauthoring, autosave, comments, and WOPI locks:

1. Use the PM-OS Office.js bridge: `~/Code/pm_os/office-addin/pm-os-bridge/`.
2. If the bridge is unavailable or unsupported for the specific small visible edit, use `node ~/Code/pm_os/bin/office-browser-edit.js`.
3. Only if both Office-session paths are unavailable, unsuitable, or explicitly unsupported should you use guarded Graph download/edit/upload tools such as `ooxml-surgery.py`, `graph-edit-pptx.js`, or `graph-file-ops.js`.

If you're writing custom download logic for a file you intend to parse, you've already made an error. Return to this registry.

Before writing ANY custom code for these operations, check this table. If it's listed here, that tool IS your implementation. No wrappers, no alternatives, no "just this once."

| Operation | Tool | BANNED alternatives (never use) |
|---|---|---|
| Excel read/write (ALL: read, write, format, formulas, ranges) | `node ~/Code/pm_os/bin/graph-workbook.js` | pandas, openpyxl, xlrd, xlsxwriter |
| File download from SharePoint/OneDrive | `node ~/Code/pm_os/bin/graph-file-ops.js download` | requests, wget, curl + parse, urllib |
| File upload to SharePoint/OneDrive | `node ~/Code/pm_os/bin/graph-file-ops.js upload` | requests.post, curl PUT |
| Word/PowerPoint in-session edits, comments, and small visible changes (preferred first path) | `~/Code/pm_os/office-addin/pm-os-bridge/` Office.js add-in bridge | raw Graph replacement as first resort, checkout/checkin lock clearing, bypass-lock headers, closing user-owned Office/browser sessions |
| Word/PowerPoint Online fallback edits and verification (preferred second path) | `node ~/Code/pm_os/bin/office-browser-edit.js` | ad hoc `agent-browser` scripts, Playwright UI scripts, raw browser-token/WOPI calls |
| Word/PPT guarded package operations only after Office-session paths are unavailable/unsupported (read, extract, write, search, replace, **comment CRUD**: list-comments, add-comment, edit-comment, delete-comment, resolve-comment, reply-comment - ALL) | `uv run --with lxml ~/Code/pm_os/bin/ooxml-surgery.py` | python-docx, docx, lxml direct, mammoth, docx2txt, textract, python-docx Comment API, openpyxl comments |
| Complex PPT package edits only after Office-session paths are unavailable/unsupported (charts, images, tables) | `node ~/Code/pm_os/bin/graph-edit-pptx.js` | python-pptx, pptx |
| SharePoint list CRUD | `node ~/Code/pm_os/bin/graph-list-crud.js` | REST calls, requests |
| Shared doc locking | `node ~/Code/pm_os/bin/sp-checkout.js` | — |
| Org chart | `node ~/Code/pm_os/bin/graph-org-chart.js` | — |
| Token routing | `node ~/Code/pm_os/bin/get-foci-token.js --for <alias>` | — |

Run any tool with `--help` to see full capabilities. If you think a tool doesn't cover your case, run `--help` first. Don't assume from the table description alone.

## Common Violations (DON'T DO THIS)

```python
# WRONG - tool registry violation
from docx import Document
doc = Document('/tmp/downloaded.docx')
for para in doc.paragraphs:
    print(para.text)
```

```bash
# RIGHT first choice for an open Word/PowerPoint doc: use the Office.js bridge.
# If you need a small visible browser fallback, dry-run it first:
node ~/Code/pm_os/bin/office-browser-edit.js \
  --action verify-visible-text \
  --url "https://..." \
  --text "visible anchor" \
  --dry-run
```

```bash
# RIGHT only after Office-session paths are unavailable or unsupported
uv run --with lxml ~/Code/pm_os/bin/ooxml-surgery.py --action extract-text --url "https://..."
```

```python
# WRONG - tool registry violation
import pandas as pd
df = pd.read_excel('/tmp/report.xlsx')
```

```bash
# RIGHT
node ~/Code/pm_os/bin/graph-workbook.js read --url "https://..."
```

## Word/PowerPoint Edit Routing

Default order:

1. Use `~/Code/pm_os/office-addin/pm-os-bridge/` for Word/PowerPoint edits whenever the document can be opened in Office.
2. Use `node ~/Code/pm_os/bin/office-browser-edit.js` for small visible Office Online edits or verification when the bridge is unavailable.
3. Use `ooxml-surgery.py`, `graph-edit-pptx.js`, or `graph-file-ops.js` only when the Office-session paths do not work for the requested edit.

If a guarded Graph/package tool reports `423 Locked` after its bounded retry:

1. Do not delete, recycle, restore, move, rename, copy over, use `CreateCopyJobs`, or use `Prefer: bypass-shared-lock`.
2. Preserve the local edited output path reported by the tool.
3. Finish through the Office-session path:
   - first: `~/Code/pm_os/office-addin/pm-os-bridge/` Office.js bridge;
   - second: `node ~/Code/pm_os/bin/office-browser-edit.js`.
4. If the Office-session path cannot identify the anchor or host state, stop and report the preserved draft. Do not invent a replacement strategy.

The Office.js bridge supports:
- `word.insertTextAfterAnchor`
- `word.replaceAnchoredText`
- `word.addCommentToAnchor`
- `word.replyCommentToAnchor`
- `word.resolveCommentAtAnchor`
- `powerpoint.addTextBox`
- `powerpoint.setShapeText`
- `powerpoint.setSelectedText`

The browser fallback is intentionally narrower:
- `verify-visible-text`
- `word-insert-after-anchor`
- `ppt-insert-or-replace-text` for small inserts only

If a tool genuinely doesn't cover your case, STOP and ask before writing custom code.

# Tool Registry

No general-purpose file I/O on Office/SharePoint resources. The tools below are the ONLY
permitted way. If a tool seems not to cover your case: run it with `--help` FIRST; if it
truly doesn't, STOP and ask before writing custom code. Full operating guide, fallback
ladders, and 423-Locked recovery: invoke the `o365-doc-edit` skill.

## Word/PowerPoint edit routing (in order — Office-session paths first)
1. `~/Code/pm_os/office-addin/pm-os-bridge/` (Office.js bridge — coauthoring/locks safe)
2. `node ~/Code/pm_os/bin/office-browser-edit.js` (small visible edits + verification)
3. Guarded Graph/package tools below — ONLY if 1 and 2 are unavailable/unsupported.
On `423 Locked` after bounded retry: do NOT delete/recycle/copy-over/bypass-lock; preserve
the tool's local draft; finish via path 1 then 2; else stop and report (o365-doc-edit skill §recovery).

| Operation | Tool | BANNED alternatives |
|---|---|---|
| Excel read/write (ALL) | `node ~/Code/pm_os/bin/graph-workbook.js` | pandas, openpyxl, xlrd, xlsxwriter |
| Download from SharePoint/OneDrive | `node ~/Code/pm_os/bin/graph-file-ops.js download` | requests, wget, curl+parse |
| Upload to SharePoint/OneDrive | `node ~/Code/pm_os/bin/graph-file-ops.js upload` | requests.post, curl PUT |
| Word/PPT in-session edits & comments (FIRST path) | pm-os-bridge (Office.js) | raw Graph first-resort, lock clearing, bypass headers |
| pm-os-bridge prereqs (gate for FIRST path) | Requires: `PMOS_BRIDGE_TLS_KEY` + `PMOS_BRIDGE_TLS_CERT` env vars set; `office-addin/pm-os-bridge/` must have built `dist/` (run `npm run build` with TLS certs present). If these are not met, fall through to path 2 (`office-browser-edit.js`). | — |
| Word/PPT Online fallback edits (SECOND path) | `office-browser-edit.js` | ad-hoc browser scripts, raw WOPI calls |
| Word/PPT guarded package ops incl. comment CRUD (LAST resort) | `uv run --with lxml ~/Code/pm_os/bin/ooxml-surgery.py` | python-docx, lxml direct, mammoth, docx2txt |
| Complex PPT package edits (LAST resort) | `node ~/Code/pm_os/bin/graph-edit-pptx.js` | python-pptx |
| SharePoint list CRUD | `node ~/Code/pm_os/bin/graph-list-crud.js` | REST/requests |
| Shared doc locking | `node ~/Code/pm_os/bin/sp-checkout.js` | — |
| Org chart | `node ~/Code/pm_os/bin/graph-org-chart.js` | — |
| Token routing | `node ~/Code/pm_os/bin/get-foci-token.js --for <alias>` | — |
| Docs → markdown (PPTX/DOCX/HTML/EPUB…) | `~/Code/.venv/bin/markitdown` | custom zipfile/xml scripts, pandoc |
| GitHub operations (clone, PRs, issues, CI runs, releases) | `gh` CLI | raw git-over-https URL guessing, scraping github.com, hand-built API curl |

If you're writing custom download logic for a file you intend to parse, you've already made
an error — return to this table.

## RTK in scripts (escape hatch)
The RTK hook rewrites `grep` → `rtk grep` and REFORMATS its output. In any script or
pipeline, never parse `grep` output — use `rtk proxy grep` (raw passthrough) or perl/jq.
`rtk find` lacks compound predicates (`-newer`, `-exec` chains): use `find -exec` directly.
Example: `find . -name '*.md' -exec perl -ne 'print if /TODO/' {} +` — not `grep -r TODO | awk`.

# Memory Routing

| Signal | Store | Write via | Read via |
|---|---|---|---|
| Raw events, errors, decisions | journal (`memory/journal.md`) | Stop-hook `session-journal.py` (auto) | `harness recall "<q>"`; sqlite3 FTS direct fallback — never load whole |
| High-signal patterns, curated pitfalls | lessons (`memory/lessons.md`) | `synthesize-lessons` (Stop-hook) or manual | Read directly (≤200 lines) |
| Work docs: roadmap, customers, org, board | gbrain | `gbrain put <slug> < f.md` | `gbrain query "<q>"` or `gbrain get <slug>` |
| Session continuity across resets | handoffs (`handoffs/<slug>.md`) | `/handoff` skill | Auto-loaded at start if <48h old |
| Hard constraints, routing, standards | rules (`rules/*.md`) | Edit in-place only | @-included or Read on demand |

## Anti-rules
- No duplicate facts across stores — one canonical home per fact.
- Journal is raw material, not citable — distill to lessons first.
- `rules/*.md` for hard constraints only — not notes or logs.
- NEVER load journal.md whole — use `harness recall`.

## Cadence
Stop-hook: `session-journal.py` (journal) + `synthesize-lessons` (lessons); `journal-index.sh` reindex on-demand; manual `gbrain put`.

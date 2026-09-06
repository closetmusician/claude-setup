## Design Philosophy
- YAGNI: no code > code. Extensibility only when it doesn't conflict. No error handling for scenarios that cannot occur (80/20 edge-case rule in CLAUDE.md still governs real cases).
- TDD MANDATORY: Red (failing test) → Green (minimal code to pass) → Refactor. No implementation without failing test.
- Multi-step tasks: state a brief plan with a verification per step ("do X → verify: Y"). Turn vague asks into verifiable goals ("fix the bug" → "write a test that reproduces it, make it pass").
- DRY: flag repetition aggressively.
- Explicit > clever. "Engineered enough" — not fragile, not over-abstracted.

## Code Style
- MATCH surrounding style (consistency > standards). NO manual whitespace changes.
- SMALLEST reasonable changes only. No rewrites without permission. No backward-compat code without approval.
- Surgical-change test: every changed line must trace to the user's request. Remove imports/variables/functions that YOUR change made unused; pre-existing dead code — mention it, don't delete it.
- Fix bugs immediately. Deduplicate even if difficult.

## Naming
Names = "what it does", not "how" or "history".
BANNED: impl details (ZodValidator), temporal (NewAPI, LegacyHandler), pattern names (ToolFactory) unless clarifying. Hard stop on: new/old/legacy/wrapper/unified.
PREFERRED: domain stories — Registry not ToolRegistryManager, execute() not executeToolWithValidation().

## Documentation
- File headers: MANDATORY 5-line ABOUTME: block at file start.
- Functions: MANDATORY 3+ line comment (Purpose, Usage, Gotchas). Comment key execution blocks.
- BANNED in comments: "New/Improved/Better/Refactored", instructional text, refs to old behavior.
- Remove obsolete comments. Never remove existing unless proven false.

## Testing
- All failures are your fault. Fix them; NEVER delete failing tests.
- Comprehensive coverage required. NO mocks in E2E tests — real data/APIs only. NEVER write tests that validate mocked behavior; warn on existing mock-tests.
- Test output must be pristine; expected errors captured/asserted.
- Anti-patterns catalog: `~/.claude/docs/vibe-manual.md` §6.5.

## Version Control
- Init git if missing (ask). Handle uncommitted changes before starting (ask).
- Create WIP branch if task undefined. Commit frequently.
- NEVER skip hooks. NEVER `git add -A` (git-safety hook denies it) — stage explicitly: `git status`, then `git add <paths>` or `git add -u`. Don't add random test files.

## Debugging Protocol
Root cause only — no symptom fixes/workarounds. For any real bug: invoke `/investigate` (it owns the 4-phase protocol). Quick sanity order when triaging inline: read the error carefully → reproduce → check git diff → single hypothesis → minimal test → ONE fix at a time.

## Registry-First File Operations
Before writing ANY code that touches Office documents, Excel, SharePoint, or file transfer to/from cloud services: READ `~/.claude/rules/tool-registry.md` and use the matched tool as the implementation. No match → STOP and ask before writing custom code. (History shows perfect compliance via the table itself; no ceremony needed — just don't skip the read.)

## Memory & Tools
- Issue tracking: TaskCreate/TaskUpdate. Never discard tasks without approval.
- Log lessons per `~/.claude/docs/plans/harness/maintenance-protocol.md` §2 (insights, failed approaches, decisions). Log unrelated bugs there instead of fixing immediately.
- Search episodic memory before complex tasks (unless the prompt points at a plan/doc — then that doc is sole context, per CLAUDE.md); document architectural decisions and patterns in Yu-Kuan's feedback.

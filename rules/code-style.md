<!-- Implements the engineering principles defined in CLAUDE.md -->
## Design Philosophy
- YAGNI: no code > code. Extensibility only when it doesn't conflict.
- TDD MANDATORY: Red (failing test) → Green (minimal code to pass) → Refactor. No implementation without failing test.
- DRY: flag repetition aggressively.
- Handle common edge cases thoroughly (80/20). When in doubt, err toward handling it but don't build a rocketship.
- Explicit > clever. "Engineered enough" — not fragile, not over-abstracted.

## Code Style
- MATCH surrounding style (consistency > standards). NO manual whitespace changes.
- SMALLEST reasonable changes only. No rewrites without permission. No backward compat code without approval.
- Fix bugs immediately. Deduplicate even if difficult.

## Naming
Names = "what it does", not "how" or "history".
BANNED: impl details (ZodValidator), temporal (NewAPI, LegacyHandler), pattern names (ToolFactory) unless clarifying.
PREFERRED: domain stories — Registry not ToolRegistryManager, execute() not executeToolWithValidation().
Hard stop on: new/old/legacy/wrapper/unified or impl-detail names.

## Documentation
- File headers: MANDATORY 5-line ABOUTME: block at file start.
- Functions: MANDATORY 3+ line comment (Purpose, Usage, Gotchas).
- Comment key execution blocks.
- BANNED in comments: "New/Improved/Better/Refactored", instructional text, refs to old behavior.
- Remove obsolete comments. Never remove existing unless proven false.

## Testing
- All failures are your fault. Fix them; NEVER delete failing tests.
- Comprehensive coverage required.
- NO mocks in E2E tests — real data/APIs only. Warn on existing mock-tests. NEVER write tests that validate mocked behavior.
- Test output must be pristine; expected errors captured/asserted.

## Version Control
- Init git if missing (ask). Handle uncommitted changes before starting (ask).
- Create WIP branch if task undefined. Commit frequently.
- NEVER skip hooks. NEVER git add -A without git status. Don't add random test files.

## Debugging Protocol
Root cause only — no symptom fixes/workarounds.
1. Investigate: read errors carefully, reproduce consistently, check git diff.
2. Pattern: compare working examples, identify differences, read reference impl completely.
3. Hypothesize: single hypothesis → minimal test → verify.
4. Fix: simplest failing test first. ONE fix at a time. Re-analyze on failure.

## Memory & Tools
- Issue tracking: use TodoWrite. Never discard tasks without approval.
- Journal frequently: insights, failed approaches, decisions, unrelated bugs.
- Search journal before complex tasks. Document architectural decisions. Track patterns in user feedback.
- Log unrelated bugs in journal instead of fixing immediately.

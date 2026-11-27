<!-- ABOUTME: Live verification of the v2.1 evidence step: real Pendo and Glean/Gong runs against fixed inputs -->
<!-- ABOUTME: Each run drives prompts/gong-evidence.md or prompts/pendo-sizing.md with placeholders filled by hand -->
<!-- ABOUTME: Pass criteria come from the implementation plan, Task 6 (spec §7) -->
<!-- ABOUTME: Scratch outputs live in ~/fe-eval/<feature>/assets/validation/ (not committed) -->
<!-- ABOUTME: Recorded 2026-11-25; compare against tests/baseline-2026-11.md -->

# Live verification: v2.1 evidence step (2026-11-25)

**Method.** Each run is a fresh `general-purpose` sub-agent given only "read the prompt file, follow it" plus the placeholder values. The main-session wiring (scope confirmation, PRD sizing gate, the disabled-in-config path) is checked separately as noted.

**Inputs.** DocuSign and Document Collection use their real PRD exports from the November pack `_sources` (7007175795, 6792938233). Forward Planner, Ask GovernAI, Version Diff Viewer and the Director Network case use short fixture PRDs, because no export exists for them.

## Results

| Step | Run | Criterion | Result |
|---|---|---|---|
| 1 | Forward Planner, Gong, window Feb 2025–Nov 2026 | Feb–Oct 2026 relevant calls 800–1,050; rep-raised majority; post-GA "coming soon" in Field Check | **PASS.** 916 feature-name calls Feb–Oct 2026 vs 911 in the Nov '26 manual analysis (<1% apart). The 1,063 total adds problem phrases the baseline never searched. Rep-raised 60% (n=15). 3 "coming soon" / "next year" claims tagged `contradicts PRD`. |
| 2 | DocuSign, Gong field check (real PRD) | "Directors need a DocuSign account" tagged `contradicts PRD` | **First run FAIL; see re-run below.** Found 2 other misconceptions (DocuSign for voting/resolutions) but missed the signer-account claim. A direct Glean probe showed the claim is in Gong in the window (AE Mar '26; CSMs Dec '25 and Oct '26). Root cause: the Field Check only read a 15-transcript sample of 4,706 broad-term calls. Fix: "PRD fact probes" step added to the prompt. |
| 2 (re-run) | DocuSign, Gong, prompt with probes | same | **PASS.** The probe `directors DocuSign account` found the claim in 7 calls (wrong) vs 4 consistent, including the AE quote "the director has to have a DocuSign account" and a trainer telling admins to license every director. Misconceptions went from 2 to 14 (also: "DocuSign licences are in your package", sequential signing, voting, reminders). 8 PRD facts probed. 0 account names in the file (fix 2 verified). 9 transcripts read, under the 15 max, to stay within context. Gap found: the PRD never states outright that signers need no DocuSign account; that answer exists only in PM-DECISIONS. |
| 3 | Document Collection, Gong field check (real PRD) | Reminders tagged `contradicts PRD` | **PASS.** Reminders/chasing tagged in 3 calls, quoting PRD 3.4. Also found unprompted: 5 calls pitching the MVP as AI-powered, plus confusion with the existing Secure Meeting Workflow. |
| 4 | Ask GovernAI, Gong | Old names searched; pre-Oct 2026 calls present | **PASS.** AI Board Member / Smart Assist / AI Assist searched; calls from Nov 2025 onward; 4,080 relevant calls, with window splitting under the 1,000 cap. Found that transcripts spell it "Ask Govern AI" (1,162 vs 70 calls), now added to the reference file. Minor: 16 transcripts read vs max 15 (self-disclosed). |
| 5a | PRD sizing gate (main session), fixture with "1,840 of ~2,700 enabled accounts" | `Status: skipped` with the quote | **PASS.** The gate wrote `skipped`, `Reason: PRD has sizing`, and the quoted line (line 3). |
| 5b | Pendo, Director Network fixture | Known never-firing DN tags under Rejected candidates | **PASS.** All 3 dead BWD DN tags rejected, citing the reference. Used the fallback base with confidence **low** and stated reasons. Detected a duplicate tag pair unprompted and flagged the Aug '26 claim-flow drop. 5 proposed reference updates; the reference file was not edited. |
| 6a | Version Diff Viewer (made-up pre-GA name), Gong | `Status: thin`; problem-phrase quotes lead | **PASS.** `thin`, 12 calls, all from problem phrases, customer voice leads (73% customer-raised). Field Check left empty, so a "None found" rule was added. |
| 6b | `evidence.pendo.enabled: false` | `init` completes PRD-only with a warning | **Checked by reading, not a live run.** SKILL.md evidence section: "skip it and note 'disabled in config' in the summary". |
| — | Real MCP outage | `Status: unavailable`, run continues | **Checked by reading only.** Both prompts write `Status: unavailable` with the error; SKILL.md step 4 continues PRD-only. Outages can't be triggered on demand. |

## Fixes made during verification

Each fix was added as a failing `check-skill.sh` assertion first, then made to pass.

1. **Glean spellcheck fallback** (found independently by runs 3 and 6a): a quoted phrase with no exact matches is silently swapped for a loose keyword search. The prompt now treats it as 0 hits and retries short spoken forms. Added to the reference file's Gong rules.
2. **No names anywhere in the file**: run 3 named an account in a header note. Quotes were already anonymised; the rule now covers the whole file.
3. **"None found" for empty sections**: run 6a left Field Check blank.
4. **PRD fact probes** (run 2 root cause): targeted searches for the PRD facts the field most often gets wrong.
5. Reference file: noise sources for "compare" and "document collection", plus the "Ask Govern AI" spelling.

## Compared with the baseline (`baseline-2026-11.md`)

| | v2.0 (Nov packs) | v2.1 runs |
|---|---|---|
| Field misconceptions detected from calls | 0 (the PM supplied the corrections by hand) | Document Collection 7 (reminders, AI, approvers); Forward Planner 8; Ask GovernAI 6; DocuSign 14 (after the probe fix; 2 before) |
| Who said it, and where | Not recorded | Role, date and call link per claim (links stay in the evidence file) |
| Problem sizing | None in any pack | Gate skips correctly when the PRD has it; the Pendo agent proposes a stand-in signal with base, window and honest confidence |
| Gong quotes | 2–5 mentions per pack, PM-pasted | Customer Voice sections from 12–15 read transcripts, anonymised |

**Also new:** findings the PM didn't know to ask about. Reps sell Document Collection as AI-powered. Gong spells "Ask Govern AI" differently from the brand. ~95% of DocuSign calls are about the Classic integration, not Boards on Diligent One.

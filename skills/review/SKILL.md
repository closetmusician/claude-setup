---
name: review
description: "Structural-safety review of a diff: SQL safety, LLM output trust boundaries, conditional side effects, shell injection, enum completeness — the bug classes tests rarely catch. Use ONLY when explicitly asked for a 'safety review', 'structural review', 'SQL safety check', or 'LLM safety check'. NOT the general PR review skill — 'review this PR' / 'code review' go to pr-review-pr, which invokes this skill as its optional safety dimension."
allowed-tools: ["Bash", "Read", "Edit", "Grep", "Glob", "AskUserQuestion"]
---

# Structural Safety Review

Analyze a diff for structural issues tests don't catch. All checklists are inline —
this skill has no external checklist files. `pr-review-pr` dispatches this skill as
its **safety** aspect when a diff touches SQL, LLM, side-effect, shell, or enum code;
it also runs standalone via `/review`.

## Step 1: Resolve the diff (with escape hatches)

1. Detect the base branch:
   `BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')`;
   fall back to `main`, then `master` (verify with `git rev-parse --verify origin/<name>`).
2. `git fetch origin $BASE --quiet`, then diff = `git diff origin/$BASE` (committed +
   uncommitted vs latest base).
3. **Escape hatches — never hard-stop without naming the alternative:**
   - Not a git repo → "Not a git repository — point me at a repo or paste the diff."
   - On the base branch with no changes, or empty diff → "Nothing to review — no diff
     against origin/$BASE. Make changes or name a branch/PR to review." Stop cleanly.
   - `git fetch` fails (offline) → proceed against the local `origin/$BASE` ref and
     note "base may be stale (fetch failed)".

## Step 2: Apply the five safety checklists

Work through every category against the full diff. If a category has no matching
code in the diff, write "n/a" and move on — do not skip silently.

### 1. SQL & Data Safety
- [ ] No SQL built by string interpolation/concatenation with runtime values —
  parameterized queries or bound placeholders only.
- [ ] Dynamic column/table names are allowlisted, never taken from input.
- [ ] `LIKE` inputs escape `%` and `_` when user-supplied.
- [ ] Bulk UPDATE/DELETE statements have a WHERE clause and it can't collapse to
  always-true when an argument is nil/empty.
- [ ] Migrations are reversible (or explicitly marked irreversible) and don't mix
  schema change + data backfill in one transaction on large tables.
- [ ] New NOT NULL / unique constraints account for existing rows.
- [ ] Destructive migrations (drop column/table) are separated from code still
  reading the dropped field (deploy-order safety).
- [ ] Transactions wrap multi-row invariants; no read-modify-write outside a
  transaction where concurrent writers exist.

### 2. LLM Output Trust Boundary
Model output is untrusted input. Check every place LLM output crosses into code:
- [ ] LLM output is schema-validated (JSON schema / parser with strict types) before
  DB writes, API calls, or arithmetic — never `JSON.parse` + direct use.
- [ ] LLM output is never interpolated into SQL, shell commands, file paths, or
  eval'd code.
- [ ] LLM output rendered in a UI is escaped/sanitized (XSS via model output).
- [ ] Enum-like fields from the model are checked against the allowed set; unknown
  values hit an explicit fallback, not a crash or silent write.
- [ ] Numeric/currency values from the model are bounds-checked before use.
- [ ] Retries/fallbacks on model failure don't silently substitute empty or default
  content where the caller expects real content.
- [ ] Prompt templates don't interpolate untrusted user/document content into
  system-level instructions without delimiting (prompt-injection surface).

### 3. Conditional Side Effects & Race Conditions
- [ ] State transitions are guarded at the data layer, not just in code — e.g. an
  UPDATE that flips `status` carries `WHERE status = '<expected-prior>'` so two
  concurrent workers can't both win.
- [ ] Check-then-act sequences (exists? → create; balance? → charge) are atomic
  (unique constraint, upsert, row lock) — not two separate statements.
- [ ] Irreversible side effects (send email, charge card, delete file, publish) are
  idempotent or guarded by an idempotency key when they can be retried.
- [ ] Side effects inside conditionals fire on the intended branch only — inverted
  or fall-through conditions around `send`/`delete`/`charge` are the classic bug.
- [ ] Retry loops around mutating calls can't double-apply the mutation.
- [ ] Cleanup paths (finally/ensure/defer) run on ALL exit paths, including early
  returns and exceptions.
- [ ] Background jobs re-check preconditions at execution time, not just enqueue time.

### 4. Shell & Command Injection
- [ ] No shell commands built by string concatenation with runtime values — use
  arg-array exec forms (`execFile`, `subprocess.run([...])`, `system(*argv)`).
- [ ] File paths from input are normalized and confined (no `../` traversal to
  outside the intended root).
- [ ] No user/LLM-derived values in backticks, `sh -c`, `eval`, or `Function()`.
- [ ] Environment variables passed to child processes don't leak secrets to
  less-trusted subprocesses or logs.
- [ ] Globs/wildcards in commands can't expand over unintended files.

### 5. Enum & Value Completeness
**This category requires reading code OUTSIDE the diff.** When the diff introduces a
new enum value, status, tier, or type constant:
- [ ] Grep for every file referencing sibling values; Read each and confirm the new
  value is handled (switch/case, mapping tables, serializers, UI labels, analytics).
- [ ] Exhaustive-match constructs (TS discriminated unions, Rust match, case/else)
  either handle the new value or fail compilation — a reachable `default: ignore`
  that swallows the new value is a finding.
- [ ] DB check constraints / validation lists include the new value.
- [ ] Downstream consumers (API clients, queues, cross-repo readers) tolerate the
  new value — flag as UNVERIFIABLE if outside this repo, naming what to check.

## Step 3: Confidence calibration and finding format

| Score | Meaning | Display rule |
|-------|---------|--------------|
| 9-10 | Verified by reading the code; concrete bug demonstrated | Show, lead with these |
| 7-8 | High-confidence pattern match | Show normally |
| 5-6 | Could be a false positive | Show with caveat "verify this is actually an issue" |
| 3-4 | Suspicious pattern, may be fine | Appendix only |
| 1-2 | Speculation | Only if severity would be P0 |

Format: `[SEVERITY] (confidence: N/10) file:line — description → fix`
- Positive example: `[P1] (confidence: 9/10) app/models/user.rb:42 — SQL injection
  via string interpolation in where clause → parameterize`.
- Negative example (do not emit): `[P2] this file looks risky` — no line, no
  confidence, no fix; "looks fine/looks risky" is not a finding.

**Verification of claims:** if you claim "this pattern is safe" or "handled
elsewhere", cite the specific line proving it. Never say "likely handled" — verify
or flag as unverified.

## Step 4: Fix-First

Every finding gets an action. Output header first:
`Structural Safety Review vs origin/<base>: N findings (X critical, Y informational)`

Classify each finding:
- **AUTO-FIX** (apply directly, log `[AUTO-FIXED] file:line — what you did`): the
  fix is mechanical and behavior-preserving — parameterizing a query, adding a
  missing `WHERE status` guard identical to sibling code, escaping output.
- **ASK** (batch into ONE AskUserQuestion): anything touching auth/payment/deletion
  semantics, schema changes, idempotency-key design, >20 line fixes, or where two
  reasonable fixes exist.

ASK batch format (per item: number, severity, problem, recommended fix, options
A) Fix as recommended / B) Skip, plus an overall RECOMMENDATION line). With ≤3 ASK
items, individual questions are fine. Apply approved fixes; never commit, push, or
create PRs — that's downstream workflow.

## Rules

- Read the FULL diff before commenting; don't flag issues the diff already fixes.
- Only flag real problems. One line problem, one line fix. No preamble.
- When invoked BY pr-review-pr as a subagent: skip Step 4's AskUserQuestion and
  fixes entirely — return findings in the Step 3 format to the orchestrator, which
  owns the fix/ask flow.

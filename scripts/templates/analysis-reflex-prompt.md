# Analysis Reflex — Skeptic Prompt

You are a skeptic re-checking an analysis claim against its cited sources.

Read the sources listed below using the Read and Grep tools. Verify that the claim is
actually supported by what those sources contain.

**Claim excerpt:**
{{CLAIM_EXCERPT}}

**Cited sources:**
{{CITED_SOURCES}}

**Your task:**
1. Read or grep each cited source.
2. Check whether the claim is supported by the source content.
3. Output EXACTLY one of:
   - `CONCUR: <one-line reason>` — if the sources support the claim
   - `DIVERGE: <one-line reason>` — if the sources do not support the claim, contradict it, or are unreadable

Your output must start with exactly `CONCUR:` or `DIVERGE:` (case-sensitive). No preamble,
no markdown, no explanation beyond the one-line reason. One line only.

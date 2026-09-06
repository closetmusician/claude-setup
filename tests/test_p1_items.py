# ABOUTME: Tests for P1 backlog items (P1-E through P1-I).
# ABOUTME: Verifies reviewer personas, enrichment, sequential review, routing, VIBE tiers.
# ABOUTME: Each test class maps to a specific backlog completion claim.
# ABOUTME: Default stance: prove the claim with file:line evidence or fail.
# ABOUTME: Run with: pytest tests/test_p1_items.py -v

import pathlib
import re

import pytest

CLAUDE_DIR = pathlib.Path.home() / ".claude"
PERSONAS_DIR = CLAUDE_DIR / "skills" / "pr-review-pr" / "personas"
PR_REVIEW_SKILL = CLAUDE_DIR / "skills" / "pr-review-pr" / "SKILL.md"
ORCHESTRATOR_SKILL = CLAUDE_DIR / "skills" / "lead-orchestrator" / "SKILL.md"


class TestP1E_ReviewerPersonas:
    """P1-E: Named reviewer personas (start with 3)"""

    EXPECTED_PERSONAS = [
        "architecture-reviewer.md",
        "domain-specialist.md",
        "ambition-backstop.md",
    ]

    @pytest.mark.parametrize("persona_file", EXPECTED_PERSONAS)
    def test_persona_file_exists(self, persona_file):
        assert (PERSONAS_DIR / persona_file).exists()

    def test_architecture_reviewer_wraps_garry_review(self):
        content = (PERSONAS_DIR / "architecture-reviewer.md").read_text()
        assert "garry-review" in content, "architecture-reviewer should wrap garry-review"

    def test_each_persona_wraps_specific_skills(self):
        """Each persona should reference at least one PR skill."""
        for pf in self.EXPECTED_PERSONAS:
            content = (PERSONAS_DIR / pf).read_text()
            skill_refs = [
                s for s in [
                    "garry-review", "pr-code-reviewer", "pr-test-analyzer",
                    "pr-comment-analyzer", "pr-code-simplifier",
                    "pr-silent-failure-hunter", "pr-type-design-analyzer",
                    "pr-briefing",
                ]
                if s in content
            ]
            assert len(skill_refs) >= 1, f"{pf} doesn't wrap any PR skills"

    def test_routing_table_references_all_personas(self):
        content = PR_REVIEW_SKILL.read_text()
        assert "Architecture Reviewer" in content
        assert "Domain Specialist" in content
        assert "Ambition Backstop" in content


class TestP1F_EnrichmentPhase:
    """P1-F: Enrichment phase before execution (lightweight)"""

    CODER_PROMPT = CLAUDE_DIR / "skills" / "lead-orchestrator" / "templates" / "coder-prompt.md"

    def test_verify_before_editing_exists(self):
        content = self.CODER_PROMPT.read_text()
        assert "Verify before editing" in content

    def test_verify_before_editing_is_requirement_1(self):
        content = self.CODER_PROMPT.read_text()
        # Should be the first numbered requirement
        requirements_section = content[content.index("## Requirements"):]
        first_req = re.search(r"1\.\s+\*\*([^*]+)\*\*", requirements_section)
        assert first_req is not None
        assert "Verify before editing" in first_req.group(1)

    def test_mandates_glob_and_read(self):
        content = self.CODER_PROMPT.read_text()
        assert "Glob" in content, "Should mandate Glob to confirm file exists"
        assert "Read" in content, "Should mandate Read to verify content"


class TestP1G_SequentialReview:
    """P1-G: Sequential review protocol"""

    def test_pr_review_default_sequential(self):
        content = PR_REVIEW_SKILL.read_text()
        assert "Default: Sequential dispatch" in content

    def test_fix_between_reviewers(self):
        content = PR_REVIEW_SKILL.read_text()
        assert "fix findings between reviewers" in content.lower() or \
               "fix findings from" in content.lower() or \
               "address all P0/P1 findings" in content

    def test_orchestrator_has_p0_loopback(self):
        content = ORCHESTRATOR_SKILL.read_text()
        # Should have loop-back logic for P0 findings
        assert "P0" in content and ("loop" in content.lower() or "fix" in content.lower())


class TestP1H_ReviewRouting:
    """P1-H: Review routing layer"""

    def test_routing_table_exists(self):
        content = PR_REVIEW_SKILL.read_text()
        assert "## Review Routing" in content

    def test_routing_has_sufficient_rules(self):
        content = PR_REVIEW_SKILL.read_text()
        routing_section = content[content.index("## Review Routing"):]
        # Count table rows (lines starting with |, excluding header/separator)
        rows = [l for l in routing_section.splitlines()
                if l.startswith("|") and not l.startswith("|---") and "Signal" not in l]
        assert len(rows) >= 7, f"Expected at least 7 routing rules, found {len(rows)}"

    def test_auto_invocation_instructions(self):
        content = PR_REVIEW_SKILL.read_text()
        assert "git diff --name-only" in content, "Should use git diff for auto-invocation"

    def test_manual_override_preserved(self):
        content = PR_REVIEW_SKILL.read_text()
        assert "manual override" in content.lower() or "Manual override" in content


class TestP1I_VIBETiers:
    """P1-I: Tier VIBE protocol per-repo"""

    VIBE_PROTOCOL = CLAUDE_DIR / "rules" / "vibe-protocol.md"

    def test_vibe_levels_section_exists(self):
        content = self.VIBE_PROTOCOL.read_text()
        assert "VIBE Levels" in content

    def test_full_and_light_columns(self):
        content = self.VIBE_PROTOCOL.read_text()
        assert "`full`" in content
        assert "`light`" in content

    def test_gate_table_covers_all_rules(self):
        content = self.VIBE_PROTOCOL.read_text()
        for rule_id in ["R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9", "R10"]:
            assert rule_id in content, f"Gate table missing {rule_id}"

    def test_orchestrator_has_vibe_level_detection(self):
        content = ORCHESTRATOR_SKILL.read_text()
        assert "VIBE Level" in content
        assert "phase.json" in content
        assert "vibe_level" in content

    def test_orchestrator_adjusts_behavior_for_light(self):
        content = ORCHESTRATOR_SKILL.read_text()
        # Should describe what light level skips
        light_idx = content.lower().find("light")
        assert light_idx != -1
        # Check that it mentions skipping something for light
        nearby = content[max(0, light_idx - 200):light_idx + 500].lower()
        assert "skip" in nearby or "skips" in nearby or "no " in nearby

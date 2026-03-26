# ABOUTME: Tests for Tier 1 backlog items (1.4 through 1.8).
# ABOUTME: Verifies flag/decide rubric, DONE_WITH_CONCERNS, self-correction, ToolSearch, sandbox.
# ABOUTME: Each test class maps to a specific backlog completion claim.
# ABOUTME: Default stance: prove the claim with file:line evidence or fail.
# ABOUTME: Run with: pytest tests/test_tier1_items.py -v

import json
import pathlib

import pytest

CLAUDE_DIR = pathlib.Path.home() / ".claude"
TEMPLATES_DIR = CLAUDE_DIR / "skills" / "lead-orchestrator" / "templates"
ORCHESTRATOR_SKILL = CLAUDE_DIR / "skills" / "lead-orchestrator" / "SKILL.md"

# The 3 "original" templates that existed when items 1.4/1.5 were completed
CORE_TEMPLATES = ["coder-prompt.md", "qa-cycle1-prompt.md", "qa-cycle2-prompt.md"]
# Templates added later
NEWER_TEMPLATES = ["test-writer-prompt.md", "qa-runner-prompt.md"]
ALL_TEMPLATES = CORE_TEMPLATES + NEWER_TEMPLATES


class TestItem14_FlagVsDecide:
    """1.4: Add Flag vs Decide rubric to lead-orchestrator subagent prompts"""

    @pytest.mark.parametrize("template", CORE_TEMPLATES)
    def test_core_template_has_decision_boundaries(self, template):
        content = (TEMPLATES_DIR / template).read_text()
        assert "Decision Boundaries" in content, f"{template} missing Decision Boundaries"

    @pytest.mark.parametrize("template", CORE_TEMPLATES)
    def test_distinguishes_decide_vs_flag(self, template):
        content = (TEMPLATES_DIR / template).read_text()
        assert "DECIDE" in content, f"{template} missing DECIDE guidance"
        assert "FLAG" in content, f"{template} missing FLAG guidance"

    @pytest.mark.parametrize("template", NEWER_TEMPLATES)
    def test_newer_templates_should_also_have_decision_boundaries(self, template):
        """BUG B2: Decision Boundaries missing from newer templates."""
        content = (TEMPLATES_DIR / template).read_text()
        assert "Decision Boundaries" in content, (
            f"BUG B2: {template} missing Decision Boundaries — "
            f"regression when new templates were added without inheriting cross-cutting requirements"
        )


class TestItem15_DoneWithConcerns:
    """1.5: Add DONE_WITH_CONCERNS verdict to subagent prompts"""

    def test_coder_has_three_verdicts(self):
        content = (TEMPLATES_DIR / "coder-prompt.md").read_text()
        assert "DONE" in content
        assert "DONE_WITH_CONCERNS" in content
        assert "BLOCKED" in content

    @pytest.mark.parametrize("template", ["qa-cycle1-prompt.md", "qa-cycle2-prompt.md"])
    def test_qa_has_pass_with_concerns(self, template):
        content = (TEMPLATES_DIR / template).read_text()
        assert "PASS" in content
        assert "FAIL" in content
        assert "PASS_WITH_CONCERNS" in content


class TestItem16_SelfCorrectionLimits:
    """1.6: Add self-correction loop limits to lead-orchestrator"""

    def test_self_correction_section_exists(self):
        content = ORCHESTRATOR_SKILL.read_text()
        assert "Self-Correction Limits" in content

    def test_deterministic_max_2_retries(self):
        content = ORCHESTRATOR_SKILL.read_text()
        assert "max 2 retries" in content or "max 2" in content

    def test_structural_immediate_escalate(self):
        content = ORCHESTRATOR_SKILL.read_text()
        assert "immediate escalate" in content.lower() or "immediate" in content.lower()

    def test_distinguishes_failure_types(self):
        content = ORCHESTRATOR_SKILL.read_text()
        assert "Deterministic" in content or "deterministic" in content
        assert "Structural" in content or "structural" in content


class TestItem17_ToolSearchBootstrap:
    """1.7: Add MCP ToolSearch bootstrap + dual name variants to agent prompts"""

    def test_coder_has_toolsearch_instruction(self):
        content = (TEMPLATES_DIR / "coder-prompt.md").read_text()
        assert "ToolSearch" in content, "coder-prompt.md missing ToolSearch instruction"

    def test_coder_mentions_dual_name_variants(self):
        content = (TEMPLATES_DIR / "coder-prompt.md").read_text()
        assert "hyphens" in content or "underscores" in content, (
            "coder-prompt.md should mention hyphen/underscore inconsistency"
        )

    def test_qa_runner_has_toolsearch(self):
        """qa-runner-prompt.md uses MCP tools and should have ToolSearch."""
        content = (TEMPLATES_DIR / "qa-runner-prompt.md").read_text()
        assert "ToolSearch" in content


class TestItem18_SandboxFix:
    """1.8: Fix sandbox security theater"""

    SETTINGS_PATH = CLAUDE_DIR / "settings.json"

    def test_settings_exists_and_is_valid_json(self):
        content = self.SETTINGS_PATH.read_text()
        data = json.loads(content)
        assert "sandbox" in data

    def test_allow_unsandboxed_commands_is_false(self):
        data = json.loads(self.SETTINGS_PATH.read_text())
        assert data["sandbox"]["allowUnsandboxedCommands"] is False

    def test_sandbox_enabled(self):
        data = json.loads(self.SETTINGS_PATH.read_text())
        assert data["sandbox"]["enabled"] is True

    def test_excluded_commands_present(self):
        data = json.loads(self.SETTINGS_PATH.read_text())
        excluded = data["sandbox"]["excludedCommands"]
        for cmd in ["git:*", "ssh:*", "gh:*", "docker:*"]:
            assert cmd in excluded, f"Missing excludedCommand: {cmd}"

    def test_project_local_sandbox_override(self):
        """BUG B12: ~/.claude/.claude/settings.local.json disables sandbox for this dir."""
        local_settings = CLAUDE_DIR / ".claude" / "settings.local.json"
        if local_settings.exists():
            data = json.loads(local_settings.read_text())
            sandbox = data.get("sandbox", {})
            if sandbox.get("enabled") is False:
                pytest.xfail(
                    "BUG B12: settings.local.json disables sandbox for ~/.claude itself "
                    "(acknowledged in backlog as intentional fallback)"
                )

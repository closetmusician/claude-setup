# ABOUTME: Tests for Tier 2 (2.7) and Tier 5 (5.6, 5.10, 5.11, 5.12) backlog items.
# ABOUTME: Verifies cleanup cron, new-project skill, silent-failure-hunter, plan review gate, spec compliance.
# ABOUTME: Each test class maps to a specific backlog completion claim.
# ABOUTME: Default stance: prove the claim with file:line evidence or fail.
# ABOUTME: Run with: pytest tests/test_tier2_and_5_items.py -v

import json
import pathlib
import subprocess

import pytest

CLAUDE_DIR = pathlib.Path.home() / ".claude"
ORCHESTRATOR_SKILL = CLAUDE_DIR / "skills" / "lead-orchestrator" / "SKILL.md"


class TestItem27_CleanupCron:
    """2.7: Create a cleanup cron or session-exit hook"""

    SCRIPT_PATH = CLAUDE_DIR / "scripts" / "weekly-cleanup.sh"
    SCHEDULES_PATH = CLAUDE_DIR / "schedules.json"

    def test_script_exists(self):
        assert self.SCRIPT_PATH.exists()

    def test_script_syntax_valid(self):
        result = subprocess.run(
            ["bash", "-n", str(self.SCRIPT_PATH)],
            capture_output=True, text=True,
        )
        assert result.returncode == 0, f"Syntax error: {result.stderr}"

    def test_14_day_retention(self):
        content = self.SCRIPT_PATH.read_text()
        assert "RETENTION_DAYS=14" in content

    def test_retention_used_in_find(self):
        content = self.SCRIPT_PATH.read_text()
        assert "-mtime +\"$RETENTION_DAYS\"" in content or "-mtime +$RETENTION_DAYS" in content

    def test_protected_file_guard(self):
        content = self.SCRIPT_PATH.read_text()
        assert "is_protected" in content
        assert "realpath" in content

    def test_protected_files_match_rules(self):
        """Protected file list should match rules/protected-files.md."""
        script_content = self.SCRIPT_PATH.read_text()
        expected_files = [
            "vibe-manual.md",
            "vibe-protocol.md",
            "code-style.md",
            "protected-files.md",
            "CLAUDE.md",
        ]
        for pf in expected_files:
            assert pf in script_content, f"Protected file {pf} not in cleanup script"

    def test_logs_to_correct_location(self):
        content = self.SCRIPT_PATH.read_text()
        assert "logs/cleanup.log" in content

    def test_log_directory_exists(self):
        assert (CLAUDE_DIR / "logs").is_dir()

    def test_scheduled_sunday_3am(self):
        data = json.loads(self.SCHEDULES_PATH.read_text())
        tasks = data.get("tasks", []) if isinstance(data, dict) else []
        # Also handle top-level dict keyed by task name
        if isinstance(data, dict) and "tasks" not in data:
            tasks = list(data.values())
        cleanup_task = None
        for task in tasks:
            if isinstance(task, dict) and "cleanup" in task.get("id", "").lower():
                cleanup_task = task
                break
        assert cleanup_task is not None, "No cleanup task in schedules.json"
        assert cleanup_task["trigger"]["expression"] == "0 3 * * 0"


class TestItem56_NewProjectSkill:
    """5.6: Create a project scaffolding skill"""

    SKILL_PATH = CLAUDE_DIR / "skills" / "new-project" / "SKILL.md"

    def test_skill_exists(self):
        assert self.SKILL_PATH.exists()

    def test_skill_line_count_approximately_140(self):
        lines = self.SKILL_PATH.read_text().splitlines()
        assert 130 <= len(lines) <= 160, f"Expected ~140 lines, got {len(lines)}"

    def test_uses_ask_user_question(self):
        content = self.SKILL_PATH.read_text()
        assert "AskUserQuestion" in content

    def test_asks_for_project_path(self):
        content = self.SKILL_PATH.read_text().lower()
        assert "project path" in content or "project name" in content

    def test_asks_for_vibe_level(self):
        content = self.SKILL_PATH.read_text().lower()
        assert "vibe level" in content or "vibe_level" in content

    def test_asks_for_project_type(self):
        content = self.SKILL_PATH.read_text().lower()
        assert "project type" in content

    def test_generates_phase_json(self):
        content = self.SKILL_PATH.read_text()
        assert "phase.json" in content

    def test_generates_claude_md(self):
        content = self.SKILL_PATH.read_text()
        assert "CLAUDE.md" in content


class TestItem510_SilentFailureHunterAgnostic:
    """5.10: Make pr-silent-failure-hunter project-agnostic"""

    SKILL_PATH = CLAUDE_DIR / "skills" / "pr-silent-failure-hunter" / "SKILL.md"

    def test_skill_exists(self):
        assert self.SKILL_PATH.exists()

    def test_no_logForDebugging(self):
        content = self.SKILL_PATH.read_text()
        assert "logForDebugging" not in content, "Hardcoded project ref 'logForDebugging' still present"

    def test_no_errorIds_ts(self):
        content = self.SKILL_PATH.read_text()
        assert "errorIds.ts" not in content, "Hardcoded project ref 'errorIds.ts' still present"

    def test_no_logEvent(self):
        content = self.SKILL_PATH.read_text()
        assert "logEvent" not in content, "Hardcoded project ref 'logEvent' still present"

    def test_no_logError_hardcoded(self):
        """BUG B1: logError was supposed to be removed but remains on line 127."""
        content = self.SKILL_PATH.read_text()
        # logError in backticks as an example grep target is the bug
        assert "`logError`" not in content, (
            "BUG B1: `logError` still present as hardcoded example — "
            "should be replaced with a generic directive"
        )

    def test_has_generic_directive(self):
        content = self.SKILL_PATH.read_text().lower()
        assert "project's claude.md" in content or "error handling docs" in content, (
            "Should have generic directive to check project-specific logging"
        )


class TestItem511_PlanReviewGate:
    """5.11: Add Plan Review Gate before enrichment/execution"""

    def test_plan_review_gate_section_exists(self):
        content = ORCHESTRATOR_SKILL.read_text()
        assert "Plan Review Gate" in content

    def test_checks_for_review_markers(self):
        content = ORCHESTRATOR_SKILL.read_text()
        assert "**Reviewed:** YES" in content or "Reviewed" in content
        assert "**Status:** APPROVED" in content or "APPROVED" in content

    def test_blocks_at_full_vibe(self):
        content = ORCHESTRATOR_SKILL.read_text()
        # Find the Plan Review Gate section and check for blocking behavior
        idx = content.find("Plan Review Gate")
        assert idx != -1
        section = content[idx:idx + 500]
        assert "AskUserQuestion" in section or "STOP" in section.upper() or "block" in section.lower()

    def test_warns_at_light_vibe(self):
        content = ORCHESTRATOR_SKILL.read_text()
        idx = content.find("Plan Review Gate")
        section = content[idx:idx + 800]
        assert "warn" in section.lower() or "light" in section.lower()


class TestItem512_SpecComplianceVerification:
    """5.12: Add spec compliance verification to QA cycle"""

    QA_CYCLE2 = CLAUDE_DIR / "skills" / "lead-orchestrator" / "templates" / "qa-cycle2-prompt.md"

    def test_spec_compliance_section_exists(self):
        content = self.QA_CYCLE2.read_text()
        assert "Spec Compliance" in content

    def test_has_completeness_check(self):
        content = self.QA_CYCLE2.read_text()
        assert "Completeness" in content or "completeness" in content

    def test_has_scope_creep_check(self):
        content = self.QA_CYCLE2.read_text()
        assert "Scope creep" in content or "scope creep" in content

    def test_has_spirit_match_check(self):
        content = self.QA_CYCLE2.read_text()
        assert "Spirit match" in content or "spirit match" in content

    def test_findings_go_in_artifact(self):
        content = self.QA_CYCLE2.read_text()
        assert "Spec Compliance" in content and "artifact" in content.lower() or "section" in content.lower()

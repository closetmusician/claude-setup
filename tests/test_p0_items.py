# ABOUTME: Tests for P0 backlog items (P0-A through P0-D).
# ABOUTME: Verifies lessons.md curation, auto-push hook, write-ahead status, repomap eval.
# ABOUTME: Each test corresponds to a specific backlog completion claim.
# ABOUTME: Default stance: prove the claim with file:line evidence or fail.
# ABOUTME: Run with: pytest tests/test_p0_items.py -v

import json
import pathlib
import re
import subprocess

import pytest

CLAUDE_DIR = pathlib.Path.home() / ".claude"


class TestP0A_Lessonsmd:
    """P0-A: Curate journal.md -> lessons.md"""

    LESSONS_PATH = CLAUDE_DIR / "memory" / "lessons.md"
    JOURNAL_PATH = CLAUDE_DIR / "memory" / "journal.md"

    def test_lessons_file_exists(self):
        assert self.LESSONS_PATH.exists(), "memory/lessons.md does not exist"

    def test_journal_still_exists_as_raw_log(self):
        assert self.JOURNAL_PATH.exists(), "journal.md should be kept as raw log"

    def test_has_five_categories(self):
        content = self.LESSONS_PATH.read_text()
        expected_categories = [
            "Tool & MCP Patterns",
            "Debugging Patterns",
            "Git & Workflow Patterns",
            "Orchestration Patterns",
            "Project-Specific Patterns",
        ]
        for cat in expected_categories:
            assert cat in content, f"Missing category: {cat}"

    def test_entries_are_curated_with_bold_titles(self):
        """Each entry should have a bold title pattern: - **title**: description"""
        content = self.LESSONS_PATH.read_text()
        entries = re.findall(r"^- \*\*[^*]+\*\*", content, re.MULTILINE)
        assert len(entries) >= 17, f"Expected at least 17 curated entries, found {len(entries)}"

    def test_memory_md_references_lessons(self):
        memory_md = CLAUDE_DIR / "projects" / "-Users-yklin--claude" / "memory" / "MEMORY.md"
        if memory_md.exists():
            content = memory_md.read_text()
            assert "lessons.md" in content, "MEMORY.md should reference lessons.md"

    def test_self_reference_path_is_correct(self):
        """BUG B7: lessons.md line 78 says tasks/lessons.md — should be memory/lessons.md"""
        content = self.LESSONS_PATH.read_text()
        if "tasks/lessons.md" in content:
            pytest.fail(
                "Stale self-reference: 'tasks/lessons.md' should be 'memory/lessons.md' (Bug B7)"
            )


class TestP0B_AutoPushHook:
    """P0-B: Add post-commit auto-push hook"""

    SCRIPT_PATH = CLAUDE_DIR / "scripts" / "auto-push-hook.sh"

    def test_script_exists(self):
        assert self.SCRIPT_PATH.exists()

    def test_script_is_executable_bash(self):
        """Verify bash -n syntax check passes."""
        result = subprocess.run(
            ["bash", "-n", str(self.SCRIPT_PATH)],
            capture_output=True, text=True,
        )
        assert result.returncode == 0, f"Syntax error: {result.stderr}"

    def test_only_pushes_allowed_branches(self):
        content = self.SCRIPT_PATH.read_text()
        assert "work/*|feature/*|feat/*" in content, "Missing branch whitelist"

    def test_never_pushes_main_master(self):
        content = self.SCRIPT_PATH.read_text()
        # The case statement should have a catch-all that exits 0
        assert "*) exit 0" in content, "Missing catch-all exit for non-allowed branches"

    def test_logs_to_push_failures_log(self):
        content = self.SCRIPT_PATH.read_text()
        assert "push-failures.log" in content

    def test_always_exits_zero(self):
        content = self.SCRIPT_PATH.read_text()
        assert "trap 'exit 0' ERR" in content, "Missing ERR trap for exit 0"
        # Last line should be exit 0
        lines = [l.strip() for l in content.strip().splitlines() if l.strip()]
        assert lines[-1] == "exit 0", "Script should end with 'exit 0'"

    def test_runs_in_background_with_disown(self):
        content = self.SCRIPT_PATH.read_text()
        assert "disown" in content, "Missing disown for background execution"
        assert ") &" in content, "Missing background subshell '( ) &'"

    def test_handles_detached_head(self):
        content = self.SCRIPT_PATH.read_text()
        assert "symbolic-ref" in content, "Should use symbolic-ref to detect detached HEAD"

    def test_wiring_documented(self):
        """BUG B6: Script should document it needs per-repo symlink wiring."""
        content = self.SCRIPT_PATH.read_text()
        assert "symlink" in content.lower() or "hooks/post-commit" in content, (
            "Script should document how to wire it (symlink to .git/hooks/post-commit)"
        )


class TestP0C_WriteAheadStatus:
    """P0-C: Wire write-ahead status into lead-orchestrator templates"""

    TEMPLATES_DIR = CLAUDE_DIR / "skills" / "lead-orchestrator" / "templates"

    ALL_TEMPLATES = [
        "coder-prompt.md",
        "qa-cycle1-prompt.md",
        "qa-cycle2-prompt.md",
        "qa-runner-prompt.md",
        "test-writer-prompt.md",
    ]

    @pytest.mark.parametrize("template", ALL_TEMPLATES)
    def test_template_has_status_pending(self, template):
        path = self.TEMPLATES_DIR / template
        assert path.exists(), f"{template} does not exist"
        content = path.read_text()
        assert "**Status:** Pending" in content, f"{template} missing Status: Pending"

    @pytest.mark.parametrize("template", ALL_TEMPLATES)
    def test_template_has_update_instruction(self, template):
        path = self.TEMPLATES_DIR / template
        content = path.read_text()
        assert "In progress" in content and "Complete" in content and "Blocked" in content, (
            f"{template} missing state machine instruction (Pending -> In progress -> Complete/Blocked)"
        )


class TestP0D_RepomapEval:
    """P0-D: Evaluate repomap generator adoption (SKIP decision)"""

    def test_generate_repomap_script_exists(self):
        assert (CLAUDE_DIR / "scripts" / "generate-repomap.py").exists()

    def test_generate_repomap_is_valid_python(self):
        result = subprocess.run(
            ["python3", "-c",
             f"import ast; ast.parse(open('{CLAUDE_DIR}/scripts/generate-repomap.py').read())"],
            capture_output=True, text=True,
        )
        assert result.returncode == 0, f"Syntax error in generate-repomap.py: {result.stderr}"

    def test_codebase_mapping_skill_exists(self):
        assert (CLAUDE_DIR / "skills" / "codebase-mapping" / "SKILL.md").exists()

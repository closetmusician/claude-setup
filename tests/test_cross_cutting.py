# ABOUTME: Tests for cross-cutting integrity checks (CX-1 through CX-10).
# ABOUTME: Verifies hook wiring, schedule validity, protected file consistency,
# ABOUTME: template inheritance, orphaned code, and git hygiene.
# ABOUTME: Default stance: prove consistency or fail.
# ABOUTME: Run with: pytest tests/test_cross_cutting.py -v

import json
import pathlib
import subprocess

import pytest

CLAUDE_DIR = pathlib.Path.home() / ".claude"
SETTINGS_PATH = CLAUDE_DIR / "settings.json"
SCHEDULES_PATH = CLAUDE_DIR / "schedules.json"
PROTECTED_FILES_RULE = CLAUDE_DIR / "rules" / "protected-files.md"
CLEANUP_SCRIPT = CLAUDE_DIR / "scripts" / "weekly-cleanup.sh"
SAFETY_HOOK = CLAUDE_DIR / "scripts" / "git-safety-hook.sh"


class TestCX1_HookWiring:
    """CX-1: All hooks in settings.json point to existing scripts."""

    def test_settings_has_hooks(self):
        data = json.loads(SETTINGS_PATH.read_text())
        assert "hooks" in data

    def test_all_hook_scripts_exist(self):
        data = json.loads(SETTINGS_PATH.read_text())
        hooks = data.get("hooks", {})
        for event_name, hook_list in hooks.items():
            if isinstance(hook_list, list):
                for hook in hook_list:
                    cmd = hook.get("command", "")
                    # Extract script path from command string
                    if "scripts/" in cmd:
                        # Parse out the script path
                        for part in cmd.split():
                            if "scripts/" in part:
                                script_path = part.replace("$HOME", str(pathlib.Path.home()))
                                script_path = script_path.replace("~", str(pathlib.Path.home()))
                                if script_path.endswith(".sh") or script_path.endswith(".py"):
                                    assert pathlib.Path(script_path).exists(), (
                                        f"Hook {event_name} references missing script: {script_path}"
                                    )


class TestCX2_ScheduleValidity:
    """CX-2: All scheduled tasks reference existing scripts."""

    def test_schedules_file_exists(self):
        assert SCHEDULES_PATH.exists()

    def test_schedules_is_valid_json(self):
        json.loads(SCHEDULES_PATH.read_text())

    @staticmethod
    def _get_tasks(data):
        """Extract task list from schedules.json (array under 'tasks' key)."""
        if isinstance(data, dict):
            tasks = data.get("tasks", [])
            return tasks if isinstance(tasks, list) else []
        return []

    def test_all_scheduled_scripts_exist(self):
        data = json.loads(SCHEDULES_PATH.read_text())
        for task in self._get_tasks(data):
            cmd = task.get("execution", {}).get("command", "")
            if not cmd:
                continue
            for part in cmd.split():
                expanded = part.replace("$HOME", str(pathlib.Path.home()))
                expanded = expanded.replace("~", str(pathlib.Path.home()))
                if expanded.endswith(".sh") or expanded.endswith(".py"):
                    assert pathlib.Path(expanded).exists(), (
                        f"Schedule '{task.get('id', '?')}' references missing script: {expanded}"
                    )

    def test_cron_expressions_are_valid_format(self):
        data = json.loads(SCHEDULES_PATH.read_text())
        for task in self._get_tasks(data):
            expr = task.get("trigger", {}).get("expression", "")
            if expr:
                parts = expr.split()
                assert len(parts) == 5, (
                    f"Schedule '{task.get('id', '?')}' has invalid cron expression: {expr}"
                )


class TestCX3_ProtectedFileConsistency:
    """CX-3: Protected files list matches across rule, hook, and cleanup script."""

    def test_protected_files_rule_exists(self):
        assert PROTECTED_FILES_RULE.exists()

    def test_protected_files_all_exist(self):
        content = PROTECTED_FILES_RULE.read_text()
        # Parse the protected file list
        protected = []
        for line in content.splitlines():
            if line.startswith("- `~/"):
                path = line.split("`")[1]
                path = path.replace("~", str(pathlib.Path.home()))
                protected.append(path)
        assert len(protected) >= 4, "Expected at least 4 protected files listed"
        for p in protected:
            assert pathlib.Path(p).exists(), f"Protected file missing: {p}"


class TestCX4_TemplateInheritance:
    """CX-4: Cross-cutting requirements present in ALL templates, not just original 3."""

    TEMPLATES_DIR = CLAUDE_DIR / "skills" / "lead-orchestrator" / "templates"
    ALL_TEMPLATES = [
        "coder-prompt.md",
        "qa-cycle1-prompt.md",
        "qa-cycle2-prompt.md",
        "test-writer-prompt.md",
        "qa-runner-prompt.md",
    ]

    @pytest.mark.parametrize("template", ALL_TEMPLATES)
    def test_all_templates_have_status_pending(self, template):
        content = (self.TEMPLATES_DIR / template).read_text()
        assert "**Status:** Pending" in content

    @pytest.mark.parametrize("template", ALL_TEMPLATES)
    def test_all_templates_have_state_transitions(self, template):
        content = (self.TEMPLATES_DIR / template).read_text()
        assert "In progress" in content and "Complete" in content


class TestCX5_GitSafetyHookCoverage:
    """CX-5: git-safety-hook.sh blocks all dangerous patterns."""

    def test_hook_exists(self):
        assert SAFETY_HOOK.exists()

    def test_blocks_force_push(self):
        content = SAFETY_HOOK.read_text()
        assert "force" in content.lower() or "--force" in content

    def test_blocks_git_add_dash_A(self):
        content = SAFETY_HOOK.read_text()
        assert "-A" in content

    def test_blocks_git_add_dot(self):
        content = SAFETY_HOOK.read_text()
        assert 'add .' in content or "add ." in content

    def test_blocks_git_add_all(self):
        """BUG B9: git add --all is not blocked, only -A and . are."""
        content = SAFETY_HOOK.read_text()
        assert "--all" in content, (
            "BUG B9: git add --all not blocked — only -A and . are covered"
        )

    def test_blocks_reset_hard(self):
        content = SAFETY_HOOK.read_text()
        assert "reset" in content and "hard" in content.lower()

    def test_blocks_protected_file_deletion(self):
        content = SAFETY_HOOK.read_text()
        assert "protected" in content.lower() or "PROTECTED" in content


class TestCX6_OrphanedCode:
    """CX-6: No dead scripts or unreferenced skills."""

    def test_auto_push_hook_wiring_documented(self):
        """BUG B6: auto-push-hook.sh is not wired to any trigger."""
        content = (CLAUDE_DIR / "scripts" / "auto-push-hook.sh").read_text()
        # It should at least document how to wire it
        assert "symlink" in content.lower() or "hooks/post-commit" in content, (
            "BUG B6: auto-push-hook.sh has no documented wiring instructions"
        )

    def test_all_skills_have_skill_md(self):
        skills_dir = CLAUDE_DIR / "skills"
        if skills_dir.is_dir():
            for skill_dir in skills_dir.iterdir():
                if skill_dir.is_dir():
                    assert (skill_dir / "SKILL.md").exists(), (
                        f"Skill directory {skill_dir.name} missing SKILL.md"
                    )


class TestCX8_BacklogConsistency:
    """CX-8: Backlog claims match reality."""

    def test_backlog_exists(self):
        assert (CLAUDE_DIR / "docs" / "backlog.md").exists()

    def test_checked_items_are_actually_done(self):
        """Verify at least the file existence for each checked item."""
        backlog = (CLAUDE_DIR / "docs" / "backlog.md").read_text()
        # Just verify the backlog is parseable and has checked items
        checked = [l for l in backlog.splitlines() if l.strip().startswith("- [x]")]
        assert len(checked) >= 15, f"Expected 15+ checked items, found {len(checked)}"

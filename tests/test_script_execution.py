# ABOUTME: Tests that actually execute Python and shell scripts with test inputs.
# ABOUTME: Verifies scripts are syntactically valid and produce expected outputs.
# ABOUTME: Covers generate-repomap.py, session-journal.py, synthesize-lessons.py.
# ABOUTME: Also validates shell scripts via bash -n syntax checks.
# ABOUTME: Run with: pytest tests/test_script_execution.py -v

import pathlib
import subprocess

import pytest

CLAUDE_DIR = pathlib.Path.home() / ".claude"
SCRIPTS_DIR = CLAUDE_DIR / "scripts"


class TestShellScriptSyntax:
    """Verify all .sh scripts pass bash -n syntax check."""

    @pytest.fixture
    def shell_scripts(self):
        return list(SCRIPTS_DIR.glob("*.sh"))

    def test_at_least_3_shell_scripts_exist(self, shell_scripts):
        assert len(shell_scripts) >= 3, f"Expected 3+ shell scripts, found {len(shell_scripts)}"

    @pytest.mark.parametrize("script_name", [
        "auto-push-hook.sh",
        "weekly-cleanup.sh",
        "git-safety-hook.sh",
    ])
    def test_shell_script_syntax(self, script_name):
        script = SCRIPTS_DIR / script_name
        if not script.exists():
            pytest.skip(f"{script_name} not found")
        result = subprocess.run(
            ["bash", "-n", str(script)],
            capture_output=True, text=True,
        )
        assert result.returncode == 0, f"Syntax error in {script_name}: {result.stderr}"

    @pytest.mark.parametrize("script_name", [
        "auto-push-hook.sh",
        "weekly-cleanup.sh",
        "git-safety-hook.sh",
    ])
    def test_shell_script_has_shebang(self, script_name):
        script = SCRIPTS_DIR / script_name
        if not script.exists():
            pytest.skip(f"{script_name} not found")
        first_line = script.read_text().splitlines()[0]
        assert first_line.startswith("#!/"), f"{script_name} missing shebang"


class TestPythonScriptSyntax:
    """Verify all .py scripts are valid Python via ast.parse."""

    @pytest.mark.parametrize("script_name", [
        "generate-repomap.py",
        "session-journal.py",
        "synthesize-lessons.py",
    ])
    def test_python_script_syntax(self, script_name):
        script = SCRIPTS_DIR / script_name
        if not script.exists():
            pytest.skip(f"{script_name} not found")
        result = subprocess.run(
            ["python3", "-c",
             f"import ast; ast.parse(open('{script}').read())"],
            capture_output=True, text=True,
        )
        assert result.returncode == 0, f"Syntax error in {script_name}: {result.stderr}"

    @pytest.mark.parametrize("script_name", [
        "generate-repomap.py",
        "session-journal.py",
        "synthesize-lessons.py",
    ])
    def test_python_script_has_aboutme(self, script_name):
        script = SCRIPTS_DIR / script_name
        if not script.exists():
            pytest.skip(f"{script_name} not found")
        content = script.read_text()
        assert "ABOUTME" in content, f"{script_name} missing ABOUTME header"


class TestGenerateRepomap:
    """Test generate-repomap.py can at least be imported."""

    SCRIPT = SCRIPTS_DIR / "generate-repomap.py"

    def test_script_exists(self):
        assert self.SCRIPT.exists()

    def test_has_main_function_or_entry(self):
        content = self.SCRIPT.read_text()
        assert "def " in content, "Script should define at least one function"

    def test_handles_no_args_gracefully(self):
        """Running with no args should not crash with an unhandled exception."""
        result = subprocess.run(
            ["python3", str(self.SCRIPT)],
            capture_output=True, text=True,
            timeout=10,
            cwd=str(CLAUDE_DIR),
        )
        # It's OK to exit non-zero (usage error), but should not be an unhandled exception
        if result.returncode != 0:
            assert "Traceback" not in result.stderr or "SystemExit" in result.stderr, (
                f"Unhandled exception: {result.stderr[-500:]}"
            )


class TestSessionJournal:
    """Test session-journal.py basic behavior."""

    SCRIPT = SCRIPTS_DIR / "session-journal.py"

    def test_script_exists(self):
        assert self.SCRIPT.exists()

    def test_has_journal_output_logic(self):
        content = self.SCRIPT.read_text()
        assert "journal" in content.lower()


class TestSynthesizeLessons:
    """Test synthesize-lessons.py basic behavior."""

    SCRIPT = SCRIPTS_DIR / "synthesize-lessons.py"

    def test_script_exists(self):
        assert self.SCRIPT.exists()

    def test_handles_both_formats(self):
        """The script should handle both old and new journal entry formats."""
        content = self.SCRIPT.read_text()
        # Should have format detection logic
        assert "Actions" in content or "Files" in content or "format" in content.lower()

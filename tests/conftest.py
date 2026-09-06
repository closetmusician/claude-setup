# ABOUTME: Shared pytest fixtures and configuration for ~/.claude test suite.
# ABOUTME: Provides CLAUDE_DIR path constant and common file-reading utilities.
# ABOUTME: All tests verify claimed backlog implementations against actual files.
# ABOUTME: No mocks — all assertions are against real filesystem state.
# ABOUTME: Run with: pytest tests/ -v

import os
import pathlib

import pytest

CLAUDE_DIR = pathlib.Path.home() / ".claude"


@pytest.fixture
def claude_dir():
    """Return the ~/.claude directory as a Path object."""
    return CLAUDE_DIR


@pytest.fixture
def skills_dir():
    """Return the skills/ directory."""
    return CLAUDE_DIR / "skills"


@pytest.fixture
def scripts_dir():
    """Return the scripts/ directory."""
    return CLAUDE_DIR / "scripts"


@pytest.fixture
def templates_dir():
    """Return the lead-orchestrator templates/ directory."""
    return CLAUDE_DIR / "skills" / "lead-orchestrator" / "templates"

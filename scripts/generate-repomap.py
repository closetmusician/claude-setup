#!/usr/bin/env python3
# ABOUTME: Git-activity-ranked structural summary of a repository.
# ABOUTME: Ranks files by recent commit frequency (weighted by recency),
# ABOUTME: extracts structural definitions (classes, functions, exports),
# ABOUTME: and outputs a compact markdown repomap for LLM context.
# ABOUTME: Stdlib-only, inspired by aider.chat's repomap concept.

import argparse
import math
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

# Directories and extensions to always skip.
SKIP_DIRS = {
    ".git", "node_modules", "__pycache__", ".tox", ".mypy_cache",
    ".pytest_cache", "venv", ".venv", "env", ".env", "dist", "build",
    ".next", ".nuxt", "coverage", ".cache", ".idea", ".vscode",
}
SKIP_EXTENSIONS = {
    ".pyc", ".pyo", ".so", ".dylib", ".dll", ".exe", ".bin",
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".svg", ".webp",
    ".woff", ".woff2", ".ttf", ".eot", ".zip", ".tar", ".gz",
    ".bz2", ".xz", ".pdf", ".doc", ".docx", ".xls", ".xlsx",
    ".lock", ".map",
}

# Structural regex patterns: (regex, indent_level). 0=top-level, 1=nested.
PATTERNS = {
    "python": [
        (re.compile(r"^class\s+(\w+)"), 0),
        (re.compile(r"^    def\s+(\w+)"), 1),
        (re.compile(r"^def\s+(\w+)"), 0),
    ],
    "js_ts": [
        (re.compile(r"^export\s+(?:default\s+)?class\s+(\w+)"), 0),
        (re.compile(r"^class\s+(\w+)"), 0),
        (re.compile(r"^export\s+(?:default\s+)?(?:async\s+)?function\s+(\w+)"), 0),
        (re.compile(r"^(?:async\s+)?function\s+(\w+)"), 0),
        (re.compile(r"^export\s+const\s+(\w+)\s*="), 0),
    ],
    "go": [
        (re.compile(r"^type\s+(\w+)\s+struct"), 0),
        (re.compile(r"^type\s+(\w+)\s+interface"), 0),
        (re.compile(r"^func\s+(?:\(\w+\s+\*?\w+\)\s+)?(\w+)"), 0),
    ],
    "rust": [
        (re.compile(r"^pub\s+(?:struct|enum)\s+(\w+)"), 0),
        (re.compile(r"^(?:struct|enum)\s+(\w+)"), 0),
        (re.compile(r"^pub\s+(?:async\s+)?fn\s+(\w+)"), 0),
        (re.compile(r"^(?:async\s+)?fn\s+(\w+)"), 0),
        (re.compile(r"^\s+pub\s+(?:async\s+)?fn\s+(\w+)"), 1),
        (re.compile(r"^\s+(?:async\s+)?fn\s+(\w+)"), 1),
    ],
    "ruby": [
        (re.compile(r"^class\s+(\w+)"), 0),
        (re.compile(r"^module\s+(\w+)"), 0),
        (re.compile(r"^\s+def\s+(\w+)"), 1),
    ],
}
EXT_TO_LANG = {
    ".py": "python", ".js": "js_ts", ".jsx": "js_ts",
    ".ts": "js_ts", ".tsx": "js_ts", ".mjs": "js_ts", ".cjs": "js_ts",
    ".go": "go", ".rs": "rust", ".rb": "ruby",
}


def run_git(args, repo_path):
    """Run a git command and return stdout lines. Empty list on failure."""
    try:
        result = subprocess.run(
            ["git"] + args, cwd=repo_path,
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            return []
        return result.stdout.strip().split("\n") if result.stdout.strip() else []
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return []


def gather_file_activity(repo_path, days):
    """Count per-file commit frequency with linear recency weighting (1.0 newest, 0.5 oldest)."""
    hashes = run_git(["log", f"--since={days} days ago", "--format=%H %ct"], repo_path)
    if not hashes:
        return {}
    commits = []
    for line in hashes:
        parts = line.split()
        if len(parts) >= 2:
            commits.append((parts[0], int(parts[1])))
    if not commits:
        return {}

    timestamps = [ts for _, ts in commits]
    newest, oldest = max(timestamps), min(timestamps)
    span = newest - oldest if newest != oldest else 1

    scores = defaultdict(float)
    for commit_hash, ts in commits:
        recency = 0.5 + 0.5 * ((ts - oldest) / span)
        for f in run_git(["diff-tree", "--no-commit-id", "--name-only", "-r", commit_hash], repo_path):
            f = f.strip()
            if f:
                scores[f] += recency
    return dict(scores)


def should_skip(filepath):
    """Check if filepath should be excluded (skip dirs or binary extensions)."""
    parts = Path(filepath).parts
    if any(part in SKIP_DIRS for part in parts):
        return True
    return Path(filepath).suffix.lower() in SKIP_EXTENSIONS


def extract_structure(filepath, repo_path):
    """Extract (name, indent_level) tuples of structural definitions from a source file."""
    lang = EXT_TO_LANG.get(Path(filepath).suffix.lower())
    if not lang:
        return []
    full_path = os.path.join(repo_path, filepath)
    try:
        with open(full_path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except (OSError, IOError):
        return []
    items = []
    for line in lines:
        for regex, level in PATTERNS[lang]:
            m = regex.match(line)
            if m:
                items.append((m.group(1), level))
                break
    return items


def format_repomap(repo_path, ranked_files, days, max_lines):
    """Build markdown repomap, truncating per-file items to stay within line budget."""
    repo_name = os.path.basename(os.path.abspath(repo_path))
    out = [f"# Repomap: {repo_name}", f"## High-Activity Files (last {days} days)", ""]

    for score, filepath in ranked_files:
        remaining = max_lines - len(out)
        if remaining < 3:
            break
        section = [f"### {filepath} ({math.ceil(score)} weighted commits)"]
        items = extract_structure(filepath, repo_path)
        if items:
            item_budget = remaining - 2  # header already added + trailing blank
            added = 0
            for name, level in items:
                if added >= item_budget - 1 and added < len(items) - 1:
                    section.append(f"  ... and {len(items) - added} more")
                    break
                section.append(f"  - {name}" if level else f"- {name}")
                added += 1
        else:
            section.append("- (no extractable structure)")
        section.append("")
        out.extend(section)
    return "\n".join(out)


def main():
    """Entry point: parse args, gather git activity, rank files, print repomap."""
    parser = argparse.ArgumentParser(description="Git-activity-ranked structural repomap.")
    parser.add_argument("--repo", default=".", help="Path to git repository (default: cwd)")
    parser.add_argument("--max-lines", type=int, default=200, help="Max output lines (default: 200)")
    parser.add_argument("--days", type=int, default=90, help="Git activity window in days (default: 90)")
    args = parser.parse_args()
    repo_path = os.path.abspath(args.repo)

    # Verify git repo.
    if not run_git(["rev-parse", "--git-dir"], repo_path):
        print(f"Error: {repo_path} is not a git repository.", file=sys.stderr)
        sys.exit(1)

    # Gather and rank file activity.
    scores = gather_file_activity(repo_path, args.days)
    if not scores:
        print(f"# Repomap: {os.path.basename(repo_path)}")
        print(f"No git activity found in the last {args.days} days.")
        sys.exit(0)

    ranked = sorted(
        [(s, f) for f, s in scores.items()
         if not should_skip(f) and os.path.isfile(os.path.join(repo_path, f))],
        reverse=True,
    )
    print(format_repomap(repo_path, ranked, args.days, args.max_lines))


if __name__ == "__main__":
    main()

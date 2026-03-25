#!/usr/bin/env python3
# ABOUTME: Replaces bash-only session journal with rich, semantic session summaries.
# ABOUTME: Reads Stop event JSON from stdin, parses JSONL transcripts deterministically.
# ABOUTME: Extracts user intent, actions, decisions, errors, struggles, and outcome.
# ABOUTME: Appends structured markdown entries to ~/.claude/memory/journal.md.
# ABOUTME: Stdlib-only, <2s runtime, fails silently on any error.

"""
Session journal hook for Claude Code.

Invoked by auto-journal.sh (Stop hook). Reads the Stop event JSON from stdin,
parses the session transcript JSONL, and appends a rich markdown summary
to the journal file. No LLM calls -- all extraction is deterministic.

Usage: echo '{"session_id":"...","transcript_path":"...","cwd":"..."}' | python3 session-journal.py
"""

import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

JOURNAL_FILE = Path.home() / ".claude" / "memory" / "journal.md"
# Only process the last N lines of large transcripts for speed.
MAX_LINES = 5000
# Truncation limits for output sections.
MAX_INTENT_CHARS = 200
MAX_ERROR_MSG_CHARS = 150
MAX_FILES_SHOWN = 5
MAX_ERRORS_SHOWN = 5


def parse_stop_event(raw: str) -> dict:
    """
    Parse the Stop event JSON piped from Claude Code via stdin.

    Returns dict with session_id, transcript_path, cwd. Missing fields
    default to empty strings. Returns empty dict on malformed input.
    """
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return {}
    if not isinstance(data, dict):
        return {}
    return data


def read_transcript(path: str) -> list[dict]:
    """
    Read a JSONL transcript file, returning parsed JSON objects.

    Skips malformed lines silently. Limits to MAX_LINES to stay under 2s
    for large transcripts. Returns empty list if file is missing or unreadable.
    """
    if not path or not os.path.isfile(path):
        return []
    entries = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entries.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
                if len(entries) >= MAX_LINES:
                    break
    except OSError:
        return []
    return entries


def extract_user_intents(entries: list[dict]) -> list[str]:
    """
    Extract the first 1-2 real user messages as a summary of intent.

    Skips meta messages (isMeta=true), command messages (content starts
    with XML tags), and tool_result arrays. Truncates each to MAX_INTENT_CHARS.
    """
    intents = []
    for entry in entries:
        if entry.get("type") != "user":
            continue
        if entry.get("isMeta"):
            continue
        msg = entry.get("message", {})
        content = msg.get("content", "")
        if not isinstance(content, str):
            continue
        # Skip command/system injected messages.
        if content.startswith("<"):
            continue
        content = content.strip()
        if not content:
            continue
        if len(content) > MAX_INTENT_CHARS:
            content = content[:MAX_INTENT_CHARS] + "..."
        intents.append(content)
        if len(intents) >= 2:
            break
    return intents


def extract_tool_calls(entries: list[dict]) -> list[dict]:
    """
    Extract all tool_use items from assistant messages.

    Returns a list of dicts: {name, input, id} for each tool call.
    Handles the content array structure where each element is either
    a text block or a tool_use block.
    """
    calls = []
    for entry in entries:
        if entry.get("type") != "assistant":
            continue
        content = entry.get("message", {}).get("content", [])
        if not isinstance(content, list):
            continue
        for item in content:
            if isinstance(item, dict) and item.get("type") == "tool_use":
                calls.append({
                    "name": item.get("name", ""),
                    "input": item.get("input", {}),
                    "id": item.get("id", ""),
                })
    return calls


def extract_tool_results(entries: list[dict]) -> list[dict]:
    """
    Extract all tool_result items from user messages.

    Returns a list of dicts: {tool_use_id, content, is_error}.
    Content is normalized to a string regardless of whether the original
    was a string or a list of text blocks.
    """
    results = []
    for entry in entries:
        if entry.get("type") != "user":
            continue
        content = entry.get("message", {}).get("content", [])
        if not isinstance(content, list):
            continue
        for item in content:
            if isinstance(item, dict) and item.get("type") == "tool_result":
                raw_content = item.get("content", "")
                if isinstance(raw_content, list):
                    # Flatten list of {type: "text", text: "..."} blocks.
                    parts = []
                    for sub in raw_content:
                        if isinstance(sub, dict):
                            parts.append(sub.get("text", ""))
                    raw_content = "\n".join(parts)
                results.append({
                    "tool_use_id": item.get("tool_use_id", ""),
                    "content": raw_content if isinstance(raw_content, str) else str(raw_content),
                    "is_error": bool(item.get("is_error")),
                })
    return results


def build_tool_id_to_call(tool_calls: list[dict]) -> dict:
    """
    Build a lookup from tool_use_id to tool call dict.

    Used to correlate tool_results back to the tool that produced them,
    enabling error attribution (which tool caused which error).
    """
    return {call["id"]: call for call in tool_calls if call.get("id")}


def compute_actions(tool_calls: list[dict]) -> dict:
    """
    Compute action summary: files created, edited, commands run, tools used.

    Scans tool calls for Edit, Write, Bash, and other tools.
    Returns dict with counts and file lists, deduplicating file paths.
    """
    files_edited = set()
    files_created = set()
    commands_run = 0
    tool_names = set()

    for call in tool_calls:
        name = call["name"]
        tool_names.add(name)
        inp = call.get("input", {})

        if name == "Edit":
            fp = inp.get("file_path", "")
            if fp:
                files_edited.add(fp)
        elif name == "Write":
            fp = inp.get("file_path", "")
            if fp:
                # Write could be create or overwrite. Treat as created if
                # not already in edited set.
                files_created.add(fp)
        elif name == "Bash":
            commands_run += 1

    # Files that appear in both Write and Edit: keep in edited, remove from created.
    files_created -= files_edited

    return {
        "files_edited": sorted(files_edited),
        "files_created": sorted(files_created),
        "commands_run": commands_run,
        "tool_names": sorted(tool_names),
    }


def extract_decisions(tool_calls: list[dict], tool_results: list[dict]) -> list[str]:
    """
    Extract user decision points from AskUserQuestion tool calls and results.

    Matches each AskUserQuestion call to its result to find the question
    asked and the answer chosen. Returns formatted strings like:
    '"Which auth?" -> JWT (user chose over session-based)'
    """
    # Build map of AskUserQuestion call IDs to their questions.
    ask_questions = {}
    for call in tool_calls:
        if call["name"] != "AskUserQuestion":
            continue
        questions = call.get("input", {}).get("questions", [])
        if questions and isinstance(questions, list):
            q = questions[0]
            header = q.get("header", "")
            question_text = q.get("question", "")
            label = header or question_text
            if len(label) > 60:
                label = label[:60] + "..."
            ask_questions[call["id"]] = label

    # Match results to questions.
    decisions = []
    for result in tool_results:
        tid = result.get("tool_use_id", "")
        if tid not in ask_questions:
            continue
        content = result.get("content", "")
        # Parse: 'User has answered your questions: "Q"="A"'
        answer = _parse_ask_answer(content)
        if answer:
            decisions.append(f'"{ask_questions[tid]}" -> {answer}')
        else:
            decisions.append(f'"{ask_questions[tid]}" -> (answered)')

    return decisions


def _parse_ask_answer(content: str) -> str:
    """
    Parse the answer from an AskUserQuestion tool_result string.

    Handles the format: 'User has answered your questions: "Q"="A".'
    Returns the answer value or empty string if not parseable.
    """
    # Pattern: "question"="answer"
    match = re.search(r'"[^"]*"\s*=\s*"([^"]*)"', content)
    if match:
        return match.group(1)
    return ""


def extract_errors(
    tool_calls: list[dict],
    tool_results: list[dict],
    id_to_call: dict,
) -> list[str]:
    """
    Extract actual error messages from tool_result entries with is_error=true.

    Attributes each error to the tool that caused it. Truncates error
    messages to MAX_ERROR_MSG_CHARS. Returns at most MAX_ERRORS_SHOWN.
    """
    errors = []
    for result in tool_results:
        if not result.get("is_error"):
            continue
        tid = result.get("tool_use_id", "")
        call = id_to_call.get(tid, {})
        tool_name = call.get("name", "Unknown")

        # Build a short context string for the tool call.
        context = _tool_call_context(call)

        # Truncate error message.
        msg = result.get("content", "").strip()
        # Take first line only for brevity.
        first_line = msg.split("\n")[0]
        if len(first_line) > MAX_ERROR_MSG_CHARS:
            first_line = first_line[:MAX_ERROR_MSG_CHARS] + "..."

        if context:
            errors.append(f"{tool_name}: `{context}` -> \"{first_line}\"")
        else:
            errors.append(f"{tool_name}: \"{first_line}\"")

        if len(errors) >= MAX_ERRORS_SHOWN:
            break

    return errors


def _tool_call_context(call: dict) -> str:
    """
    Build a short context string for a tool call (for error attribution).

    For Bash: the command (truncated). For Edit/Write: the file path.
    For Read: the file path. Returns empty string for unknown tools.
    """
    if not call:
        return ""
    name = call.get("name", "")
    inp = call.get("input", {})
    if name == "Bash":
        cmd = inp.get("command", "")
        if len(cmd) > 60:
            cmd = cmd[:60] + "..."
        return cmd
    elif name in ("Edit", "Write", "Read"):
        return inp.get("file_path", "")
    elif name in ("Grep", "Glob"):
        return inp.get("pattern", "")
    return ""


def detect_struggles(tool_calls: list[dict], tool_results: list[dict]) -> list[str]:
    """
    Detect patterns that indicate struggle: repeated tool calls on same file.

    Looks for files that were edited 3+ times (indicating retries).
    Also detects high error rates on specific tools.
    Returns formatted struggle descriptions.
    """
    struggles = []

    # Count Edit calls per file.
    edit_counts = Counter()
    for call in tool_calls:
        if call["name"] == "Edit":
            fp = call.get("input", {}).get("file_path", "")
            if fp:
                edit_counts[fp] += 1

    for fp, count in edit_counts.most_common(3):
        if count >= 3:
            short = _shorten_path(fp)
            struggles.append(f"{count} retries on {short} edits")

    # Check for high error rate.
    total_calls = len(tool_calls)
    error_count = sum(1 for r in tool_results if r.get("is_error"))
    if total_calls > 5 and error_count / total_calls > 0.3:
        struggles.append(f"High error rate: {error_count}/{total_calls} tool calls failed")

    return struggles


def detect_outcome(tool_calls: list[dict], tool_results: list[dict], entries: list[dict]) -> str:
    """
    Summarize session outcome: commits made, tasks completed, user sentiment.

    Checks Bash calls for 'git commit', TaskUpdate calls for status=completed,
    and scans the last few user messages for sentiment indicators.
    """
    parts = []

    # Count git commits from Bash commands.
    commit_count = 0
    for call in tool_calls:
        if call["name"] == "Bash":
            cmd = call.get("input", {}).get("command", "")
            if "git commit" in cmd:
                commit_count += 1
    if commit_count:
        parts.append(f"{commit_count} commit{'s' if commit_count != 1 else ''}")

    # Count completed tasks.
    completed_count = 0
    for call in tool_calls:
        if call["name"] == "TaskUpdate":
            status = call.get("input", {}).get("status", "")
            if status == "completed":
                completed_count += 1
    if completed_count:
        parts.append(f"{completed_count} task{'s' if completed_count != 1 else ''} completed")

    # Check last user messages for sentiment.
    last_user_msgs = []
    for entry in reversed(entries):
        if entry.get("type") != "user" or entry.get("isMeta"):
            continue
        content = entry.get("message", {}).get("content", "")
        if isinstance(content, str) and not content.startswith("<"):
            last_user_msgs.append(content.lower())
        if len(last_user_msgs) >= 2:
            break

    for msg in last_user_msgs:
        if any(w in msg for w in ["thanks", "perfect", "great", "lgtm", "ship it", "nice"]):
            parts.append("user satisfied")
            break
        if any(w in msg for w in ["stop", "cancel", "nevermind", "wrong", "undo", "revert"]):
            parts.append("user interrupted")
            break

    return ", ".join(parts) if parts else "session ended"


def _shorten_path(path: str) -> str:
    """
    Shorten a file path for display by replacing $HOME with ~ .

    Keeps the path readable while saving horizontal space in journal entries.
    """
    home = str(Path.home())
    if path.startswith(home):
        return "~" + path[len(home):]
    return path


def format_entry(
    timestamp: str,
    project: str,
    session_id: str,
    intents: list[str],
    actions: dict,
    decisions: list[str],
    errors: list[str],
    struggles: list[str],
    outcome: str,
) -> str:
    """
    Format all extracted data into a markdown journal entry.

    Produces a structured entry with Intent, Actions, Decisions, Errors,
    Struggles, and Outcome sections. Omits empty sections to keep entries
    compact (target: 5-15 lines, never more than 20).
    """
    lines = []
    lines.append(f"## {timestamp} — {project} ({session_id})")
    lines.append("")

    # Intent.
    if intents:
        intent_text = intents[0]
        if len(intents) > 1:
            intent_text += " | " + intents[1]
        lines.append(f"**Intent:** {intent_text}")

    # Actions.
    edited = actions["files_edited"]
    created = actions["files_created"]
    total_modified = len(edited) + len(created)
    cmds = actions["commands_run"]

    action_parts = []
    if edited:
        action_parts.append(f"{len(edited)} edited")
    if created:
        action_parts.append(f"{len(created)} created")
    if cmds:
        action_parts.append(f"{cmds} commands")
    if action_parts:
        lines.append(f"**Actions:** {', '.join(action_parts)}")

    # Show significant files (max MAX_FILES_SHOWN total).
    shown = 0
    if edited:
        for fp in edited[:MAX_FILES_SHOWN]:
            lines.append(f"- Modified: {_shorten_path(fp)}")
            shown += 1
    if created and shown < MAX_FILES_SHOWN:
        for fp in created[:MAX_FILES_SHOWN - shown]:
            lines.append(f"- Created: {_shorten_path(fp)}")

    # Decisions.
    if decisions:
        lines.append("**Decisions:**")
        for d in decisions:
            lines.append(f"- {d}")

    # Errors.
    if errors:
        lines.append("**Errors:**")
        for e in errors:
            lines.append(f"- {e}")

    # Struggles.
    if struggles:
        lines.append(f"**Struggles:** {'; '.join(struggles)}")

    # Outcome.
    lines.append(f"**Outcome:** {outcome}")

    lines.append("")
    lines.append("---")

    return "\n".join(lines)


def ensure_journal_header(journal_path: Path) -> None:
    """
    Ensure the journal file exists with a proper header.

    Creates parent directories and writes the header if the file doesn't
    exist. Does nothing if the file already has content.
    """
    journal_path.parent.mkdir(parents=True, exist_ok=True)
    if not journal_path.exists():
        journal_path.write_text(
            "# Claude Code Session Journal\n\n"
            "Append-only log of session activity. "
            "Searchable by date, file, tool, or error.\n\n---\n"
        )


def main() -> None:
    """
    Entry point: read Stop event from stdin, parse transcript, write journal.

    Orchestrates the full pipeline: parse event -> read transcript -> extract
    all sections -> format entry -> append to journal. Exits 0 on any error
    to never block the Claude Code stop hook.
    """
    try:
        raw_input = sys.stdin.read()
    except Exception:
        return

    stop_event = parse_stop_event(raw_input)
    if not stop_event:
        return

    # Skip stop-hook-continuation events (prevent noise).
    if stop_event.get("stop_hook_active"):
        return

    session_id = stop_event.get("session_id", "unknown")[:8]
    transcript_path = stop_event.get("transcript_path", "")
    cwd = stop_event.get("cwd", "unknown")
    project = os.path.basename(cwd) if cwd else "unknown"

    entries = read_transcript(transcript_path)

    # Extract all sections.
    intents = extract_user_intents(entries)
    tool_calls = extract_tool_calls(entries)
    tool_results = extract_tool_results(entries)
    id_to_call = build_tool_id_to_call(tool_calls)

    actions = compute_actions(tool_calls)
    decisions = extract_decisions(tool_calls, tool_results)
    errors = extract_errors(tool_calls, tool_results, id_to_call)
    struggles = detect_struggles(tool_calls, tool_results)
    outcome = detect_outcome(tool_calls, tool_results, entries)

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    entry = format_entry(
        timestamp=timestamp,
        project=project,
        session_id=session_id,
        intents=intents,
        actions=actions,
        decisions=decisions,
        errors=errors,
        struggles=struggles,
        outcome=outcome,
    )

    ensure_journal_header(JOURNAL_FILE)

    try:
        with open(JOURNAL_FILE, "a", encoding="utf-8") as f:
            f.write(entry + "\n")
    except OSError:
        return


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Fail silently -- this hook must never block Claude.
        pass

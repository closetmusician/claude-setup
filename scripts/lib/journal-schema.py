#!/usr/bin/env python3
# ABOUTME: Single source of truth for journal entry field contract.
# ABOUTME: Defines canonical field list, validate(), and has_signal() helpers.
# ABOUTME: Imported by session-journal.py (writer) and synthesize-lessons.py (reader).
# ABOUTME: Changes here are the ONLY permitted way to evolve the journal schema.
# ABOUTME: Both scripts must remain in lock-step — a contract test asserts writer-keys ⊆ reader-keys.

"""
Journal schema contract module.

Frozen field list for structured journal entries written by session-journal.py
and parsed by synthesize-lessons.py. Neither script may invent fields outside
this list without updating this file first.

Fields:
  Intent     - user's stated goal (first 1-2 messages)
  Actions    - summary line: N edited, M created, K commands
  Decisions  - AskUserQuestion choices (list items under header)
  Errors     - tool errors with context (list items under header)
  Struggles  - repeated-retry / high-error-rate patterns
  Outcome    - session result: commits, tasks completed, user sentiment

File-embedded lines (not bold-header fields, but part of the contract):
  "- Modified: <path>"  - files edited this session
  "- Created: <path>"   - files created this session

Signal definition (for de-noising):
  An entry has SIGNAL if any of the following are non-empty:
    - Decisions section (list items present)
    - Errors section (list items present)
    - Struggles field
    - Modified/Created file lines
    - Actions line with non-zero commands
  An entry is NOISE if:
    - Outcome == "session ended" AND no signal fields above are present
"""

import re

# Canonical field names. Both writer and reader MUST use exactly these strings.
# The contract test asserts: set(WRITER_KEYS) == set(FIELD_NAMES).
FIELD_NAMES = [
    "Intent",
    "Actions",
    "Decisions",
    "Errors",
    "Struggles",
    "Outcome",
]

# Keys that the writer emits as bold-header fields (markdown: **Key:**).
WRITER_KEYS = list(FIELD_NAMES)

# Keys that the reader uses for signal detection (subset of FIELD_NAMES).
# Outcome is excluded from signal detection — it's the result, not the signal.
SIGNAL_KEYS = ["Decisions", "Errors", "Struggles"]


def has_signal(block: str) -> bool:
    """
    Return True if a raw journal entry block contains meaningful signal.

    Purpose: Determines whether an entry carries learnable content vs pure
             session-ended noise. Used by session-journal.py (skip-at-source)
             and synthesize-lessons.py (filter before API call).

    Signal is defined as ANY of:
      - **Decisions:** section with at least one list item
      - **Errors:** section with at least one list item
      - **Struggles:** field present (non-empty)
      - "- Modified:" or "- Created:" file lines present
      - **Actions:** line references non-zero commands

    Gotchas: Does NOT check Outcome — "session ended" is the absence of other
             signals, not a signal itself. Returns False for pure noise entries.
    """
    # Decisions section with list items.
    if re.search(r"\*\*Decisions:\*\*\n-", block):
        return True

    # Errors section with list items (new format).
    if re.search(r"\*\*Errors:\*\*\n-", block):
        return True

    # Struggles field present and non-trivially empty.
    struggles_match = re.search(r"\*\*Struggles:\*\* (.+)", block)
    if struggles_match and struggles_match.group(1).strip():
        return True

    # File lines (modified or created).
    if re.search(r"^- (Modified|Created): ", block, re.MULTILINE):
        return True

    # Actions line mentions non-zero commands.
    actions_match = re.search(r"\*\*Actions:\*\* (.+)", block)
    if actions_match:
        actions_text = actions_match.group(1)
        # Check for "N commands" where N > 0.
        cmd_match = re.search(r"(\d+) commands?", actions_text)
        if cmd_match and int(cmd_match.group(1)) > 0:
            return True

    return False


def is_noise_entry(outcome: str, block: str) -> bool:
    """
    Return True if the entry is pure session-ended noise that should be skipped.

    Purpose: Used by session-journal.py to suppress writing no-signal entries,
             killing the 46% noise at the source.

    An entry is noise iff:
      - outcome == "session ended" (exactly, case-sensitive)
      - AND has_signal(block) is False

    Gotchas: This check happens BEFORE writing, so 'block' is the formatted
             entry string. Call this after format_entry() to get the full block.
    """
    if outcome != "session ended":
        return False
    return not has_signal(block)


def validate(entry: dict) -> list[str]:
    """
    Validate a journal entry dict for required fields and types.

    Purpose: Contract test helper — asserts a writer-produced entry has all
             required keys with correct types. Used in test-journal-contract.py.

    Returns a list of error strings. Empty list means the entry is valid.

    Required fields:
      timestamp  - ISO 8601 string (YYYY-MM-DDTHH:MM:SSZ)
      project    - non-empty string
      session_id - non-empty string
      intents    - list of strings
      actions    - dict with keys: files_edited, files_created, commands_run, tool_names
      decisions  - list of strings
      errors     - list of strings
      struggles  - list of strings
      outcome    - non-empty string

    Gotchas: Does not validate timestamp format in depth — only checks it's a non-empty string.
    """
    errors = []

    required_str_fields = ["timestamp", "project", "session_id", "outcome"]
    for field in required_str_fields:
        if field not in entry:
            errors.append(f"Missing required field: '{field}'")
        elif not isinstance(entry[field], str) or not entry[field]:
            errors.append(f"Field '{field}' must be a non-empty string")

    required_list_fields = ["intents", "decisions", "errors", "struggles"]
    for field in required_list_fields:
        if field not in entry:
            errors.append(f"Missing required field: '{field}'")
        elif not isinstance(entry[field], list):
            errors.append(f"Field '{field}' must be a list")

    if "actions" not in entry:
        errors.append("Missing required field: 'actions'")
    elif not isinstance(entry["actions"], dict):
        errors.append("Field 'actions' must be a dict")
    else:
        for sub in ["files_edited", "files_created", "tool_names"]:
            if sub not in entry["actions"]:
                errors.append(f"Missing actions sub-field: '{sub}'")
            elif not isinstance(entry["actions"][sub], list):
                errors.append(f"actions.{sub} must be a list")
        if "commands_run" not in entry["actions"]:
            errors.append("Missing actions sub-field: 'commands_run'")
        elif not isinstance(entry["actions"]["commands_run"], int):
            errors.append("actions.commands_run must be an int")

    # Validate timestamp format loosely.
    if "timestamp" in entry and isinstance(entry["timestamp"], str):
        import re as _re
        if not _re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", entry["timestamp"]):
            errors.append(f"timestamp '{entry['timestamp']}' does not match YYYY-MM-DDTHH:MM:SSZ")

    return errors


def parse_signal_from_block(block: str) -> dict:
    """
    Parse signal indicators from a raw journal entry block.

    Purpose: Used by synthesize-lessons.py parse_journal_entries() to replace
             the ad-hoc inline parsing with a contract-aware extraction.
             Returns a dict with the same keys synthesize-lessons.py needs.

    Returns dict with:
      has_intent    - bool
      has_actions   - bool
      has_decisions - bool
      has_errors    - bool
      has_struggles - bool
      has_files     - bool
      has_signal    - bool (overall signal)
      is_new_format - bool (True if **Intent:** present)

    Gotchas: Old format (**Files:**, **Tools:**) dead-code branches are NOT
             included — only new-format fields are returned. This is intentional:
             the old bash writer is dead; dual-format support is removed.
    """
    has_intent = "**Intent:**" in block
    has_actions = "**Actions:**" in block
    has_decisions = bool(re.search(r"\*\*Decisions:\*\*\n-", block))
    has_errors = bool(re.search(r"\*\*Errors:\*\*\n-", block))
    struggles_match = re.search(r"\*\*Struggles:\*\* (.+)", block)
    has_struggles = bool(struggles_match and struggles_match.group(1).strip())
    has_files = bool(re.search(r"^- (Modified|Created): ", block, re.MULTILINE))

    signal = has_decisions or has_errors or has_struggles or has_files
    # Actions with commands also counts as signal.
    if has_actions:
        actions_match = re.search(r"\*\*Actions:\*\* (.+)", block)
        if actions_match:
            cmd_match = re.search(r"(\d+) commands?", actions_match.group(1))
            if cmd_match and int(cmd_match.group(1)) > 0:
                signal = True

    return {
        "has_intent": has_intent,
        "has_actions": has_actions,
        "has_decisions": has_decisions,
        "has_errors": has_errors,
        "has_struggles": has_struggles,
        "has_files": has_files,
        "has_signal": signal,
        "is_new_format": has_intent,
    }

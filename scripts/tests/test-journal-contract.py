#!/usr/bin/env python3
# ABOUTME: Contract tests for the journal input schema (III-0 hard blocker).
# ABOUTME: Verifies writer/reader field parity, noise filtering, and round-trip parsing.
# ABOUTME: Run with: python3 test-journal-contract.py
# ABOUTME: All 6+ cases must pass green before any Pillar III downstream work begins.
# ABOUTME: TDD: schema module was written first (RED→GREEN per VIBE R2).

"""
Journal contract test suite — Pillar III task III-0.

Tests:
  1. Schema validate() accepts a well-formed entry dict.
  2. Schema validate() rejects a missing required field.
  3. session-journal.py format_entry() produces a block whose fields match WRITER_KEYS.
  4. synthesize-lessons.py parse_journal_entries() round-trips a signal entry without loss.
  5. Noise entry (outcome='session ended', no signal) is skipped by is_noise_entry().
  6. Signal entry (has files/decisions) is NOT skipped by is_noise_entry().
  7. WRITER_KEYS ⊆ FIELD_NAMES (contract: writer never emits outside frozen list).
  8. parse_signal_from_block() correctly detects signal vs noise in a real journal block.
"""

import importlib.util
import os
import re
import sys
import tempfile
import traceback
from pathlib import Path

SCRIPTS_DIR = Path(__file__).parent.parent
SCHEMA_PATH = SCRIPTS_DIR / "lib" / "journal-schema.py"
WRITER_PATH = SCRIPTS_DIR / "session-journal.py"
READER_PATH = SCRIPTS_DIR / "synthesize-lessons.py"


def load_module(path: Path, name: str):
    """Load a Python module from a file path."""
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# --- Load modules ---
try:
    schema = load_module(SCHEMA_PATH, "journal_schema")
except Exception as e:
    print(f"FATAL: Cannot load journal-schema.py: {e}")
    sys.exit(1)

try:
    writer = load_module(WRITER_PATH, "session_journal")
except Exception as e:
    print(f"FATAL: Cannot load session-journal.py: {e}")
    sys.exit(1)

try:
    reader = load_module(READER_PATH, "synthesize_lessons")
except Exception as e:
    print(f"FATAL: Cannot load synthesize-lessons.py: {e}")
    sys.exit(1)

# Track results.
passed = 0
failed = 0
results = []


def run_test(name: str, fn):
    """Run a test function, catch exceptions, record result."""
    global passed, failed
    try:
        fn()
        results.append(("PASS", name))
        passed += 1
    except AssertionError as e:
        results.append(("FAIL", name, str(e)))
        failed += 1
    except Exception as e:
        results.append(("ERROR", name, traceback.format_exc()))
        failed += 1


# =============================================================================
# Test 1: validate() accepts a well-formed entry dict
# =============================================================================
def test_validate_good_entry():
    entry = {
        "timestamp": "2026-07-04T10:00:00Z",
        "project": "hermes",
        "session_id": "abc12345",
        "intents": ["fix the broken journal contract"],
        "actions": {
            "files_edited": ["/some/file.py"],
            "files_created": [],
            "commands_run": 3,
            "tool_names": ["Bash", "Edit"],
        },
        "decisions": [],
        "errors": [],
        "struggles": [],
        "outcome": "1 commit",
    }
    errors = schema.validate(entry)
    assert errors == [], f"Expected no errors, got: {errors}"


run_test("validate() accepts well-formed entry", test_validate_good_entry)


# =============================================================================
# Test 2: validate() rejects missing required field
# =============================================================================
def test_validate_missing_field():
    entry = {
        "timestamp": "2026-07-04T10:00:00Z",
        "project": "hermes",
        # Missing: session_id, intents, actions, decisions, errors, struggles, outcome
    }
    errors = schema.validate(entry)
    assert len(errors) > 0, "Expected validation errors for missing fields"
    # Should specifically call out session_id
    combined = " ".join(errors)
    assert "session_id" in combined, f"Expected 'session_id' in errors, got: {errors}"


run_test("validate() rejects missing required field", test_validate_missing_field)


# =============================================================================
# Test 3: session-journal.py format_entry() emits only WRITER_KEYS fields
# =============================================================================
def test_writer_emits_frozen_keys():
    # Build a real format_entry() call with known data.
    block = writer.format_entry(
        timestamp="2026-07-04T10:00:00Z",
        project="testproject",
        session_id="testse",
        intents=["fix the schema"],
        actions={
            "files_edited": ["/tmp/foo.py"],
            "files_created": [],
            "commands_run": 2,
            "tool_names": ["Bash", "Edit"],
        },
        decisions=["\"Use TDD?\" -> yes"],
        errors=[],
        struggles=[],
        outcome="1 commit",
    )

    # Extract all bold-header fields from the block.
    emitted_fields = re.findall(r"\*\*([^:*]+):\*\*", block)
    emitted_set = set(emitted_fields)
    allowed_set = set(schema.WRITER_KEYS)

    extra = emitted_set - allowed_set
    assert extra == set(), f"Writer emitted fields outside WRITER_KEYS: {extra}"

    # All expected fields should appear (non-empty ones).
    assert "Intent" in emitted_set, "Missing **Intent:** in formatted block"
    assert "Actions" in emitted_set, "Missing **Actions:** in formatted block"
    assert "Outcome" in emitted_set, "Missing **Outcome:** in formatted block"


run_test("session-journal format_entry() emits only frozen WRITER_KEYS", test_writer_emits_frozen_keys)


# =============================================================================
# Test 4: synthesize-lessons parse_journal_entries() round-trips a signal entry
# =============================================================================
def test_reader_parses_signal_entry():
    # Construct a minimal journal string with one signal entry.
    journal_text = """# Claude Code Session Journal

---

## 2026-07-04T10:00:00Z — hermes (abc12345)

**Intent:** Fix the broken journal contract
**Actions:** 1 edited, 2 commands
- Modified: ~/Code/hermes/scripts/session-journal.py
**Decisions:**
- "Use schema module?" -> yes
**Outcome:** 1 commit

---
"""
    entries = reader.parse_journal_entries(journal_text)
    assert len(entries) == 1, f"Expected 1 entry, got {len(entries)}"
    e = entries[0]
    assert e["project"] == "hermes", f"project mismatch: {e['project']}"
    assert e["session_id"] == "abc12345", f"session_id mismatch: {e['session_id']}"
    assert e["has_signal"] is True, "Signal entry should have has_signal=True"
    assert e["is_new_format"] is True, "Entry with **Intent:** should be new format"


run_test("synthesize-lessons parse_journal_entries() round-trips signal entry", test_reader_parses_signal_entry)


# =============================================================================
# Test 5: Noise entry (outcome='session ended', no signal) is skipped
# =============================================================================
def test_noise_entry_skipped():
    # A pure noise entry: outcome=session ended, no decisions/errors/struggles/files.
    noise_block = """## 2026-07-04T10:00:00Z — hermes (abc12345)

**Intent:** quick check
**Actions:** 0 commands
**Outcome:** session ended"""

    result = schema.is_noise_entry("session ended", noise_block)
    assert result is True, f"Expected is_noise_entry=True for pure noise, got {result}"


run_test("is_noise_entry() returns True for pure 'session ended' noise", test_noise_entry_skipped)


# =============================================================================
# Test 6: Signal entry is NOT skipped
# =============================================================================
def test_signal_entry_kept():
    # A signal entry with file modifications.
    signal_block = """## 2026-07-04T10:00:00Z — hermes (abc12345)

**Intent:** fix the contract
**Actions:** 1 edited, 3 commands
- Modified: ~/Code/hermes/scripts/session-journal.py
**Outcome:** session ended"""

    result = schema.is_noise_entry("session ended", signal_block)
    assert result is False, f"Expected is_noise_entry=False for signal entry, got {result}"

    # Also test with decisions.
    decision_block = """## 2026-07-04T10:00:00Z — hermes (abc12345)

**Intent:** fix the contract
**Actions:** 0 commands
**Decisions:**
- "Use TDD?" -> yes
**Outcome:** session ended"""

    result2 = schema.is_noise_entry("session ended", decision_block)
    assert result2 is False, f"Expected is_noise_entry=False for decision entry, got {result2}"


run_test("is_noise_entry() returns False for entries with signal", test_signal_entry_kept)


# =============================================================================
# Test 7: WRITER_KEYS ⊆ FIELD_NAMES (contract assertion)
# =============================================================================
def test_writer_keys_subset_of_field_names():
    writer_set = set(schema.WRITER_KEYS)
    field_set = set(schema.FIELD_NAMES)
    extra = writer_set - field_set
    assert extra == set(), f"WRITER_KEYS contains fields not in FIELD_NAMES: {extra}"
    # All FIELD_NAMES should be in WRITER_KEYS (they're the same list).
    missing = field_set - writer_set
    assert missing == set(), f"FIELD_NAMES has fields not in WRITER_KEYS: {missing}"


run_test("WRITER_KEYS == FIELD_NAMES (no drift)", test_writer_keys_subset_of_field_names)


# =============================================================================
# Test 8: parse_signal_from_block() correctly detects signal vs noise
# =============================================================================
def test_parse_signal_from_block():
    noise_block = """## 2026-07-04T10:00:00Z — hermes (abc12345)

**Intent:** quick check
**Actions:** 0 commands
**Outcome:** session ended"""

    signal_block = """## 2026-07-04T10:00:00Z — hermes (abc12345)

**Intent:** fix the contract
**Actions:** 1 edited, 3 commands
- Modified: ~/Code/hermes/scripts/session-journal.py
**Errors:**
- Bash: `python3 test.py` -> "AssertionError: Expected 1 entry"
**Outcome:** session ended"""

    noise_info = schema.parse_signal_from_block(noise_block)
    assert noise_info["has_signal"] is False, f"Noise block should have no signal, got: {noise_info}"
    assert noise_info["is_new_format"] is True, "Block with **Intent:** is new format"

    signal_info = schema.parse_signal_from_block(signal_block)
    assert signal_info["has_signal"] is True, f"Signal block should have signal, got: {signal_info}"
    assert signal_info["has_files"] is True, "Signal block has modified files"
    assert signal_info["has_errors"] is True, "Signal block has errors"


run_test("parse_signal_from_block() detects signal vs noise correctly", test_parse_signal_from_block)


# =============================================================================
# Print results
# =============================================================================
print()
print("=" * 60)
print("Journal Contract Test Results")
print("=" * 60)
for r in results:
    status = r[0]
    name = r[1]
    if status == "PASS":
        print(f"  PASS  {name}")
    else:
        msg = r[2] if len(r) > 2 else ""
        print(f"  {status}  {name}")
        if msg:
            # Indent error message.
            for line in msg.strip().splitlines():
                print(f"         {line}")

print()
print(f"Results: {passed}/{passed + failed} passed")
if failed > 0:
    print(f"FAILED: {failed} test(s)")
    sys.exit(1)
else:
    print("ALL TESTS PASSED")
    sys.exit(0)

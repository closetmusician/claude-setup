#!/usr/bin/env python3
# ABOUTME: Reads unprocessed journal entries and synthesizes durable lessons via Claude Sonnet.
# ABOUTME: Runs twice daily (11am + 2am EST) via Claude Code scheduler.
# ABOUTME: Deduplicates against existing lessons, marks processed entries, cleans old ones.
# ABOUTME: Uses atomic writes (tmp + rename) and file locking to prevent corruption.
# ABOUTME: Logs results to ~/.claude/logs/synthesis.log.

import datetime
import fcntl
import json
import logging
import os
import re
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

# --- Paths ---
HOME = Path.home()
JOURNAL_PATH = HOME / ".claude" / "memory" / "journal.md"
LESSONS_PATH = HOME / ".claude" / "memory" / "lessons.md"
PROJECTS_DIR = HOME / ".claude" / "projects"
LOG_DIR = HOME / ".claude" / "logs"
LOG_PATH = LOG_DIR / "synthesis.log"
LOCK_PATH = HOME / ".claude" / "logs" / "synthesis.lock"
ENV_PATH = HOME / "Code" / "pm_os" / ".env"

# --- Config ---
MODEL = "claude-sonnet-4-6"
MAX_TOKENS = 4096
API_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"
ENTRY_MAX_AGE_DAYS = 30


def setup_logging():
    """
    Configure logging to file and stderr.
    Purpose: Centralized log setup for both scheduled and manual runs.
    Gotchas: Creates log directory if missing. File handler appends, never truncates.
    """
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(LOG_PATH, mode="a"),
            logging.StreamHandler(sys.stderr),
        ],
    )


def acquire_lock():
    """
    Acquire an exclusive file lock to prevent concurrent runs.
    Purpose: Prevents two scheduled runs from corrupting files simultaneously.
    Usage: Called once at startup; lock released when process exits.
    Gotchas: Returns the lock file handle (must stay open). Returns None if already locked.
    """
    LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
    try:
        lock_fd = open(LOCK_PATH, "w")
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        lock_fd.write(str(os.getpid()))
        lock_fd.flush()
        return lock_fd
    except (IOError, OSError):
        return None


def load_api_key():
    """
    Load the Anthropic API key from environment or pm_os .env file.
    Purpose: Single source for API authentication across environments.
    Usage: Returns the key string or None.
    Gotchas: Checks ANTHROPIC_API_KEY env var first, then falls back to pm_os .env file.
    """
    key = os.environ.get("ANTHROPIC_API_KEY")
    if key:
        return key
    # Fall back to pm_os .env file.
    if ENV_PATH.exists():
        for line in ENV_PATH.read_text().splitlines():
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            if k.strip() == "ANTHROPIC_API_KEY":
                v = v.strip().strip("'\"")
                if v:
                    return v
    return None


def parse_journal_entries(content):
    """
    Parse journal.md into a list of entry dicts with raw text and metadata.
    Purpose: Splits the append-only journal into individual session records.
    Usage: Returns list of dicts with keys: raw, timestamp, project, session_id, processed, has_signal.
    Gotchas: Handles BOTH old format (Files/Tools/Errors count) and new format
             (Intent/Actions/Decisions/Errors list/Struggles/Outcome from session-journal.py).
             An entry is considered "processed" if it contains '<!-- processed: YYYY-MM-DD -->'.
    """
    entries = []
    # Split on the --- separator. Each entry starts with ## timestamp.
    raw_blocks = re.split(r"\n---\n?", content)
    for block in raw_blocks:
        block = block.strip()
        if not block:
            continue
        # Match entry header: ## YYYY-MM-DDTHH:MM:SSZ — project (session_id)
        header_match = re.match(
            r"^## (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z) — (.+?) \((\w+)\)",
            block,
        )
        if not header_match:
            continue
        timestamp_str = header_match.group(1)
        project = header_match.group(2)
        session_id = header_match.group(3)
        processed = "<!-- processed:" in block

        # Detect format and extract signal indicators.
        # NEW format (session-journal.py): **Intent:**, **Actions:**, **Errors:** (list), **Decisions:**, **Struggles:**
        # OLD format (auto-journal.sh): **Files:**, **Tools:**, **Errors:** N error(s)
        has_intent = "**Intent:**" in block
        has_actions = "**Actions:**" in block
        has_decisions = "**Decisions:**" in block
        has_struggles = "**Struggles:**" in block

        # Errors: new format uses list items under **Errors:**, old format uses count.
        has_errors = False
        if has_intent:
            # New format: errors are list items like "- Bash: `cmd` -> "msg""
            has_errors = bool(re.search(r"\*\*Errors:\*\*\n- ", block))
        else:
            # Old format: **Errors:** N error(s)
            error_match = re.search(r"\*\*Errors:\*\* (\d+) error", block)
            has_errors = bool(error_match) and int(error_match.group(1)) > 0

        # Files: new format uses "- Modified:" / "- Created:", old uses **Files:**
        has_files = bool(re.search(r"- (Modified|Created): ", block))
        if not has_files:
            files_match = re.search(r"\*\*Files:\*\* (.+)", block)
            has_files = bool(files_match) and files_match.group(1).strip() != "none"

        # Tools: only in old format.
        tools_match = re.search(r"\*\*Tools:\*\* (.+)", block)
        has_tools = bool(tools_match) and tools_match.group(1).strip() != "none detected"

        # An entry has signal if it has meaningful content for lesson extraction.
        has_signal = (
            has_errors
            or has_decisions
            or has_struggles
            or has_files
            or has_tools
            or (has_intent and has_actions)
        )

        try:
            timestamp = datetime.datetime.fromisoformat(
                timestamp_str.replace("Z", "+00:00")
            )
        except ValueError:
            continue
        entries.append(
            {
                "raw": block,
                "timestamp": timestamp,
                "timestamp_str": timestamp_str,
                "project": project,
                "session_id": session_id,
                "processed": processed,
                "has_signal": has_signal,
                "is_new_format": has_intent,
            }
        )
    return entries


def is_trivial_entry(entry):
    """
    Determine if a journal entry is too trivial to send for lesson extraction.
    Purpose: Filter out noise entries that won't produce lessons (saves API tokens).
    Usage: Returns True if the entry should be skipped.
    Gotchas: Uses 'has_signal' which handles both old and new journal formats.
             New format entries with Intent + Actions are always considered non-trivial
             since they contain semantic content worth evaluating.
    """
    return not entry["has_signal"]


def parse_existing_lessons(content):
    """
    Parse lessons.md into structured categories and individual lessons.
    Purpose: Provides existing lessons to the API for deduplication.
    Usage: Returns (categories_dict, raw_text). categories_dict maps category name to list of lesson dicts.
    Gotchas: Each lesson is a markdown bullet starting with **Bold title**. Category headers are ## lines.
    """
    categories = {}
    current_category = None
    for line in content.splitlines():
        cat_match = re.match(r"^## (.+)$", line)
        if cat_match:
            current_category = cat_match.group(1).strip()
            categories[current_category] = []
            continue
        if current_category and line.startswith("- **"):
            # Parse: - **Title**: Body text
            lesson_match = re.match(r"^- \*\*(.+?)\*\*:\s*(.+)$", line)
            if lesson_match:
                categories[current_category].append(
                    {
                        "title": lesson_match.group(1),
                        "body": lesson_match.group(2),
                    }
                )
    return categories


def load_project_memories():
    """
    Read all per-project MEMORY.md files for cross-project pattern scanning.
    Purpose: Surfaces project-specific patterns that might generalize into lessons.
    Usage: Returns a combined string of all project memories, truncated to prevent token bloat.
    Gotchas: Skips the .claude project's own MEMORY.md (it's meta, not project-specific).
             Limits each file to 2000 chars and total to 8000 chars.
    """
    memories = []
    total_chars = 0
    max_per_file = 2000
    max_total = 8000
    if not PROJECTS_DIR.exists():
        return ""
    for memory_file in sorted(PROJECTS_DIR.glob("*/memory/MEMORY.md")):
        # Skip the .claude project's own memory.
        if "-Users-yklin--claude" in str(memory_file):
            continue
        try:
            text = memory_file.read_text(encoding="utf-8")
        except (OSError, IOError):
            continue
        # Extract project name from path.
        project_dir = memory_file.parent.parent.name
        # Truncate if needed.
        if len(text) > max_per_file:
            text = text[:max_per_file] + "\n... (truncated)"
        header = f"\n### Project: {project_dir}\n"
        chunk = header + text
        if total_chars + len(chunk) > max_total:
            break
        memories.append(chunk)
        total_chars += len(chunk)
    return "\n".join(memories)


def build_synthesis_prompt(journal_text, existing_lessons_text, project_context):
    """
    Construct the system + user prompt for the Claude Sonnet API call.
    Purpose: Creates a carefully crafted prompt that enforces the 30-day/2-repo test.
    Usage: Returns (system_prompt, user_prompt) tuple.
    Gotchas: The prompt is the most critical part of the pipeline. Changes here affect lesson quality.
    """
    system_prompt = """You are a lessons-learned curator for a software engineer's AI coding assistant setup.

Your job: Extract durable, cross-project lessons from recent session logs.

## The bar
A lesson must pass this test: "Would this help someone working on a DIFFERENT project, 30 days from now?"

If the answer is no, REJECT it. Most sessions produce NO lessons. That's normal.

## What makes a good lesson
- General principle + specific example
- Actionable (tells you what TO DO or NOT DO)
- Cross-project (not tied to one codebase's quirks)
- Non-obvious (something you'd forget without writing down)

## What to REJECT
- Project-specific configuration details
- One-time setup steps
- Obvious best practices ("write tests", "handle errors")
- Symptoms without root causes
- Temporary workarounds
- Entries with only metadata (files listed, tools used) but no signal about what went wrong or what was learned

## Output format
Return ONLY valid JSON (no markdown fences, no explanation outside the JSON):
{
  "new_lessons": [
    {
      "category": "Category Name",
      "title": "Bold title here",
      "body": "General principle stated clearly. _Example: what specifically happened that taught this._"
    }
  ],
  "updated_lessons": [
    {
      "original_title": "Existing lesson title to update",
      "new_body": "Updated body with new example appended"
    }
  ],
  "reasoning": "Brief explanation of what was considered and rejected"
}

If there are no lessons to extract, return:
{"new_lessons": [], "updated_lessons": [], "reasoning": "explanation"}"""

    user_prompt = f"""## Existing lessons (for deduplication — do NOT repeat these, but you may UPDATE one with a new example)

{existing_lessons_text}

## Recent journal entries (unprocessed)

{journal_text}

## Project context (for cross-project pattern detection)

{project_context}

Analyze these journal entries. Extract ONLY lessons that pass the 30-day, 2-repo test. Most entries will produce nothing — that's correct."""

    return system_prompt, user_prompt


def call_claude_api(api_key, system_prompt, user_prompt):
    """
    Call the Anthropic Messages API with raw HTTP (no SDK dependency).
    Purpose: Sends journal data to Claude Sonnet for lesson extraction.
    Usage: Returns parsed JSON response dict or None on failure.
    Gotchas: Uses urllib (stdlib) to avoid SDK version conflicts. Retries once on 529/5xx.
             Timeout is 60 seconds. Response text is parsed as JSON after stripping markdown fences.
    """
    request_body = json.dumps(
        {
            "model": MODEL,
            "max_tokens": MAX_TOKENS,
            "system": system_prompt,
            "messages": [{"role": "user", "content": user_prompt}],
        }
    ).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "x-api-key": api_key,
        "anthropic-version": ANTHROPIC_VERSION,
    }
    # Retry logic: try up to 2 times on server errors.
    for attempt in range(2):
        try:
            req = urllib.request.Request(
                API_URL, data=request_body, headers=headers, method="POST"
            )
            with urllib.request.urlopen(req, timeout=60) as resp:
                response_data = json.loads(resp.read().decode("utf-8"))
            # Extract text content from response.
            text = ""
            for block in response_data.get("content", []):
                if block.get("type") == "text":
                    text += block.get("text", "")
            # Strip markdown code fences if present.
            text = text.strip()
            if text.startswith("```"):
                # Remove opening fence (with optional language tag).
                text = re.sub(r"^```\w*\n?", "", text)
                text = re.sub(r"\n?```$", "", text)
                text = text.strip()
            return json.loads(text)
        except urllib.error.HTTPError as e:
            status = e.code
            logging.warning("API returned HTTP %d on attempt %d", status, attempt + 1)
            if status in (429, 529) or status >= 500:
                if attempt == 0:
                    import time

                    time.sleep(5)
                    continue
            logging.error("API call failed: HTTP %d — %s", status, e.read().decode("utf-8", errors="replace"))
            return None
        except (urllib.error.URLError, json.JSONDecodeError, KeyError) as e:
            logging.error("API call failed: %s", e)
            if attempt == 0:
                import time

                time.sleep(2)
                continue
            return None
    return None


def apply_new_lessons(lessons_content, new_lessons):
    """
    Append new lessons under the appropriate category headers in lessons.md.
    Purpose: Inserts new lessons into the correct section of the existing file.
    Usage: Returns the updated file content string.
    Gotchas: If a category doesn't exist, it's appended at the end of the file.
             Preserves existing file structure and comments.
    """
    lines = lessons_content.splitlines()
    # Group new lessons by category.
    by_category = {}
    for lesson in new_lessons:
        cat = lesson["category"]
        if cat not in by_category:
            by_category[cat] = []
        by_category[cat].append(lesson)
    # Find category header positions.
    category_positions = {}
    for i, line in enumerate(lines):
        cat_match = re.match(r"^## (.+)$", line)
        if cat_match:
            category_positions[cat_match.group(1).strip()] = i
    # Insert lessons into existing categories.
    insertions = []
    remaining_categories = {}
    for cat, lessons in by_category.items():
        if cat in category_positions:
            # Find the end of the category section (next ## or end of file).
            start = category_positions[cat]
            end = len(lines)
            for j in range(start + 1, len(lines)):
                if re.match(r"^## ", lines[j]):
                    end = j
                    break
            # Find last non-empty line in the section.
            insert_at = end
            for j in range(end - 1, start, -1):
                if lines[j].strip():
                    insert_at = j + 1
                    break
            for lesson in lessons:
                text = f"\n- **{lesson['title']}**: {lesson['body']}"
                insertions.append((insert_at, text))
                insert_at += 1
        else:
            remaining_categories[cat] = lessons
    # Apply insertions in reverse order to preserve line numbers.
    insertions.sort(key=lambda x: x[0], reverse=True)
    for pos, text in insertions:
        lines.insert(pos, text)
    # Append new categories at end of file.
    for cat, lessons in remaining_categories.items():
        lines.append("")
        lines.append(f"## {cat}")
        lines.append("")
        for lesson in lessons:
            lines.append(f"- **{lesson['title']}**: {lesson['body']}")
    return "\n".join(lines) + "\n"


def apply_updated_lessons(content, updated_lessons):
    """
    Replace existing lesson bodies in-place by matching bold title.
    Purpose: Updates an existing lesson with new examples without creating duplicates.
    Usage: Returns the updated file content string and count of lessons actually updated.
    Gotchas: Matches on the bold title text (between ** markers). If title not found, logs a warning and skips.
    """
    updated_count = 0
    for update in updated_lessons:
        original_title = update["original_title"]
        new_body = update["new_body"]
        # Escape regex special chars in the title.
        escaped = re.escape(original_title)
        pattern = rf"^(- \*\*{escaped}\*\*:\s*)(.+)$"
        new_content, n = re.subn(
            pattern, rf"\g<1>{new_body}", content, count=1, flags=re.MULTILINE
        )
        if n > 0:
            content = new_content
            updated_count += 1
        else:
            logging.warning("Could not find lesson to update: '%s'", original_title)
    return content, updated_count


def update_lessons_timestamp(content):
    """
    Update the '<!-- Updated: YYYY-MM-DD -->' comment in the lessons file header.
    Purpose: Tracks when lessons.md was last modified by the synthesizer.
    Usage: Returns updated content string.
    Gotchas: If the comment doesn't exist in the expected ABOUTME format, adds it. Replaces in-place if found.
    """
    today = datetime.date.today().isoformat()
    # Replace existing ABOUTME updated comment.
    new_content, n = re.subn(
        r"<!-- ABOUTME: Updated: \d{4}-\d{2}-\d{2} -->",
        f"<!-- ABOUTME: Updated: {today} -->",
        content,
        count=1,
    )
    if n == 0:
        # Also try the simpler format.
        new_content, n = re.subn(
            r"<!-- Updated: \d{4}-\d{2}-\d{2} -->",
            f"<!-- Updated: {today} -->",
            content,
            count=1,
        )
    return new_content


def mark_entries_processed(journal_content, entries_to_mark):
    """
    Add '<!-- processed: YYYY-MM-DD -->' after each processed entry's --- separator.
    Purpose: Prevents re-processing entries on the next run.
    Usage: Returns updated journal content string.
    Gotchas: Matches entries by their exact timestamp string to avoid false positives.
             Inserts the marker right before the --- separator that follows the entry.
    """
    today = datetime.date.today().isoformat()
    marker = f"<!-- processed: {today} -->"
    for entry in entries_to_mark:
        ts = entry["timestamp_str"]
        # Find the entry by timestamp and add marker before its trailing ---.
        # Pattern: the entry block ending with ---
        # We insert the marker on a new line before the ---.
        pattern = rf"(## {re.escape(ts)} .+?)(\n---)"
        replacement = rf"\1\n{marker}\2"
        journal_content = re.sub(pattern, replacement, journal_content, count=1, flags=re.DOTALL)
    return journal_content


def clean_old_entries(journal_content, max_age_days):
    """
    Remove journal entries older than max_age_days.
    Purpose: Keeps journal.md from growing unbounded. Old entries are already processed or irrelevant.
    Usage: Returns (updated_content, count_removed).
    Gotchas: Preserves the file header (lines before the first ## entry).
             Only removes entries that are both old AND already processed.
    """
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(
        days=max_age_days
    )
    # Split into header and entries.
    parts = re.split(r"(?=\n## \d{4}-\d{2}-\d{2}T)", journal_content, maxsplit=1)
    if len(parts) < 2:
        return journal_content, 0
    header = parts[0]
    body = parts[1]
    # Split body into individual entry blocks (entry + its --- separator).
    entry_blocks = re.split(r"(\n---\n?)", body)
    # Rebuild: pair each entry with its separator.
    paired = []
    i = 0
    while i < len(entry_blocks):
        block = entry_blocks[i]
        sep = entry_blocks[i + 1] if i + 1 < len(entry_blocks) else ""
        paired.append(block + sep)
        i += 2
    kept = []
    removed = 0
    for block in paired:
        ts_match = re.search(r"## (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)", block)
        if ts_match:
            try:
                entry_time = datetime.datetime.fromisoformat(
                    ts_match.group(1).replace("Z", "+00:00")
                )
                is_processed = "<!-- processed:" in block
                if entry_time < cutoff and is_processed:
                    removed += 1
                    continue
            except ValueError:
                pass
        kept.append(block)
    return header + "".join(kept), removed


def atomic_write(path, content):
    """
    Write content to a temp file then atomically rename to target path.
    Purpose: Prevents file corruption if the process crashes mid-write.
    Usage: atomic_write(Path("/some/file"), "content")
    Gotchas: Uses tempfile in the same directory as target to ensure same filesystem (required for rename).
             Sets file permissions to 0o644.
    """
    parent = path.parent
    parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.chmod(tmp_path, 0o644)
        os.rename(tmp_path, str(path))
    except Exception:
        # Clean up temp file on failure.
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def main():
    """
    Entry point: orchestrate journal reading, API synthesis, and file updates.
    Purpose: Runs the full synthesis pipeline end-to-end.
    Usage: python3 synthesize-lessons.py [--dry-run]
    Gotchas: Exits cleanly (code 0) in all expected cases (no entries, API failure, lock contention).
             Only --dry-run flag skips file writes and API call.
    """
    setup_logging()
    dry_run = "--dry-run" in sys.argv
    logging.info("=== Lesson synthesis started (dry_run=%s) ===", dry_run)

    # Acquire exclusive lock.
    lock_fd = acquire_lock()
    if lock_fd is None:
        logging.info("Another synthesis run is active. Exiting.")
        return

    try:
        _run_synthesis(dry_run)
    finally:
        # Release lock.
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            lock_fd.close()
            LOCK_PATH.unlink(missing_ok=True)
        except OSError:
            pass


def _run_synthesis(dry_run):
    """
    Core synthesis logic, separated from main for clean lock management.
    Purpose: Handles reading, filtering, API call, and atomic writes.
    Usage: Called by main() after lock acquisition.
    Gotchas: Returns early on empty input or API failure without corrupting files.
    """
    # Load API key.
    api_key = load_api_key()
    if not api_key and not dry_run:
        logging.error("No ANTHROPIC_API_KEY found. Set env var or add to %s", ENV_PATH)
        return

    # Read journal.
    if not JOURNAL_PATH.exists():
        logging.info("No journal file found at %s", JOURNAL_PATH)
        return
    journal_content = JOURNAL_PATH.read_text(encoding="utf-8")
    all_entries = parse_journal_entries(journal_content)
    logging.info("Parsed %d total journal entries", len(all_entries))

    # Filter to unprocessed, non-trivial entries.
    unprocessed = [e for e in all_entries if not e["processed"]]
    nontrivial = [e for e in unprocessed if not is_trivial_entry(e)]
    logging.info(
        "Unprocessed: %d, non-trivial: %d", len(unprocessed), len(nontrivial)
    )

    # Read existing lessons.
    if not LESSONS_PATH.exists():
        logging.error("No lessons file found at %s", LESSONS_PATH)
        return
    lessons_content = LESSONS_PATH.read_text(encoding="utf-8")
    existing_categories = parse_existing_lessons(lessons_content)
    existing_count = sum(len(v) for v in existing_categories.values())
    logging.info("Existing lessons: %d across %d categories", existing_count, len(existing_categories))

    # Load project memories for context.
    project_context = load_project_memories()

    # Build the journal text for the prompt (only non-trivial entries).
    if nontrivial:
        journal_text = "\n\n---\n\n".join(e["raw"] for e in nontrivial)
    else:
        journal_text = "(No non-trivial entries to process)"

    if dry_run:
        logging.info("DRY RUN — would send %d entries to API", len(nontrivial))
        logging.info("Journal text preview (first 500 chars): %s", journal_text[:500])
        # In dry run, still mark trivial entries as processed and clean old.
        _mark_and_clean(journal_content, unprocessed, nontrivial, dry_run=True)
        return

    # If no non-trivial entries, just mark trivial ones as processed and clean old entries.
    if not nontrivial:
        logging.info("No non-trivial entries to synthesize. Marking trivial entries as processed.")
        _mark_and_clean(journal_content, unprocessed, nontrivial, dry_run=False)
        return

    # Build and send prompt.
    system_prompt, user_prompt = build_synthesis_prompt(
        journal_text, lessons_content, project_context
    )
    logging.info("Calling Claude API (%s) with %d entries...", MODEL, len(nontrivial))
    result = call_claude_api(api_key, system_prompt, user_prompt)
    if result is None:
        logging.error("API call failed. No changes made.")
        return

    # Process API response.
    new_lessons = result.get("new_lessons", [])
    updated_lessons = result.get("updated_lessons", [])
    reasoning = result.get("reasoning", "")
    logging.info(
        "API returned: %d new lessons, %d updates. Reasoning: %s",
        len(new_lessons),
        len(updated_lessons),
        reasoning[:200],
    )

    # Apply changes to lessons.md.
    updated_content = lessons_content
    if new_lessons:
        updated_content = apply_new_lessons(updated_content, new_lessons)
    update_count = 0
    if updated_lessons:
        updated_content, update_count = apply_updated_lessons(
            updated_content, updated_lessons
        )
    updated_content = update_lessons_timestamp(updated_content)

    # Write lessons.md atomically.
    if new_lessons or update_count > 0:
        atomic_write(LESSONS_PATH, updated_content)
        logging.info("Wrote updated lessons.md (%d new, %d updated)", len(new_lessons), update_count)
    else:
        logging.info("No lesson changes to write.")

    # Mark entries as processed and clean old entries.
    _mark_and_clean(journal_content, unprocessed, nontrivial, dry_run=False)

    logging.info("=== Synthesis complete ===")


def _mark_and_clean(journal_content, unprocessed, nontrivial, dry_run):
    """
    Mark all unprocessed entries as processed and clean entries older than 30 days.
    Purpose: Shared logic for post-synthesis journal maintenance.
    Usage: Called after API processing or when skipping API (no non-trivial entries).
    Gotchas: Marks ALL unprocessed entries (both trivial and non-trivial) as processed.
             Only removes old entries that are already marked as processed.
    """
    # Mark ALL unprocessed entries as processed (trivial ones too — they've been seen).
    if unprocessed:
        updated_journal = mark_entries_processed(journal_content, unprocessed)
    else:
        updated_journal = journal_content

    # Clean entries older than 30 days.
    updated_journal, cleaned = clean_old_entries(updated_journal, ENTRY_MAX_AGE_DAYS)
    if cleaned > 0:
        logging.info("Cleaned %d old entries (>%d days)", cleaned, ENTRY_MAX_AGE_DAYS)

    if not dry_run and (unprocessed or cleaned > 0):
        atomic_write(JOURNAL_PATH, updated_journal)
        logging.info(
            "Updated journal.md: %d entries marked processed, %d old entries cleaned",
            len(unprocessed),
            cleaned,
        )
    elif dry_run:
        logging.info(
            "DRY RUN — would mark %d entries processed, clean %d old entries",
            len(unprocessed),
            cleaned,
        )


if __name__ == "__main__":
    main()

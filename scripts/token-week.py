#!/usr/bin/env python3
"""
ABOUTME: Weekly Claude Code spend line for session start.
ABOUTME: Scans transcripts from last 14 days, prices calls at list prices, splits last 7d vs prior 7d.
ABOUTME: Prints one line or JSON (--json flag). Env override TOKEN_WEEK_ROOT for testing.
ABOUTME: Dedupes on (message_id, requestId) keeping largest output_tokens (streaming case).
ABOUTME: Must finish under 60s by checking mtime before opening files.
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime, timezone, timedelta
from collections import defaultdict
from typing import Dict, List, Tuple

# $/MTok pricing (Anthropic list prices, 2026-11-13)
# Format: (input, 5m_write, 1h_write, cache_read, output)
PRICES = {
    'opus-5-5': (4, 5, 8, 0.20, 20),
    'sonnet-4-5': (3, 3.75, 6, 0.30, 15),
    'sonnet-5': (2, 2.5, 4, 0.20, 10),
    'sonnet-5-5': (2, 2.5, 4, 0.10, 10),
    'haiku-4-5': (1, 1.25, 2, 0.10, 5),
    'haiku-5-5': (0.10, 0.125, 0.20, 0.01, 0.50),
    'fable-5-1': (10, 12.5, 20, 0.25, 50),
    'fable-5-2': (8, 10, 16, 0.20, 40),
    'opus-4-5': (5, 6.25, 10, 0.50, 25),
    'opus-4-8': (5, 6.25, 10, 0.50, 25),
}


def model_family(raw_model: str) -> str:
    """
    Purpose: map raw model id to price key.
    Usage: model_family('claude-sonnet-4-5-20250929') -> 'sonnet-4-5'
    Gotchas: Bedrock ids have 'anthropic.' prefix and ':0' suffix.
    """
    for key in sorted(PRICES, key=len, reverse=True):
        if key in raw_model:
            return key
    # Unknown model — return the raw id so it shows in output
    return raw_model


def price_call(msg: dict, model_key: str) -> float:
    """
    Purpose: calculate dollar cost for one call.
    Usage: price_call(message_dict, 'sonnet-4-5')
    Gotchas: returns 0.0 if model not in PRICES (unknown model).
    """
    if model_key not in PRICES:
        return 0.0

    inp, c5w, c1w, cr, out_price = PRICES[model_key]
    usage = msg.get('usage', {})

    input_tok = usage.get('input_tokens', 0)
    cache_creation = usage.get('cache_creation', {})
    c5 = cache_creation.get('ephemeral_5m_input_tokens', 0)
    c1 = cache_creation.get('ephemeral_1h_input_tokens', 0)

    # Old format fallback
    if c5 == 0 and c1 == 0:
        c5 = usage.get('cache_creation_input_tokens', 0)

    cache_read = usage.get('cache_read_input_tokens', 0)
    output_tok = usage.get('output_tokens', 0)

    return (input_tok * inp + c5 * c5w + c1 * c1w + cache_read * cr + output_tok * out_price) / 1_000_000


class Call:
    """Represents one API call with dedupe key and pricing."""

    def __init__(self, entry: dict, file_path: str):
        self.file_path = file_path
        self.timestamp = entry.get('timestamp', '')
        self.request_id = entry.get('requestId', '')

        msg = entry.get('message', {})
        self.message_id = msg.get('id', '')
        self.model_raw = msg.get('model', '<unknown>')
        self.model_key = model_family(self.model_raw)

        self.usage = msg.get('usage', {})
        self.output_tokens = self.usage.get('output_tokens', 0)

        # Subagent detection
        self.is_subagent = '/subagents/' in file_path

        # Price this call
        self.cost = price_call(msg, self.model_key)

    @property
    def dedup_key(self) -> Tuple[str, str]:
        """Dedupe key: (message_id, request_id)."""
        return (self.message_id, self.request_id)

    def timestamp_dt(self) -> datetime:
        """Parse timestamp to datetime."""
        try:
            return datetime.fromisoformat(self.timestamp.replace('Z', '+00:00'))
        except:
            return datetime.min.replace(tzinfo=timezone.utc)


def scan_transcripts(root_dir: Path, cutoff_dt: datetime) -> List[Call]:
    """
    Purpose: find and parse all .jsonl transcripts modified after cutoff_dt.
    Usage: calls = scan_transcripts(projects_dir, now - 14 days)
    Gotchas: checks mtime before opening to stay under 60s on large repos.
    """
    calls = []

    for dirpath, dirnames, filenames in os.walk(root_dir):
        for fname in filenames:
            if not fname.endswith('.jsonl'):
                continue

            fpath = Path(dirpath) / fname

            # Check mtime — skip old files
            try:
                mtime = datetime.fromtimestamp(fpath.stat().st_mtime, tz=timezone.utc)
                if mtime < cutoff_dt:
                    continue
            except:
                continue

            # Parse this transcript
            try:
                with open(fpath, 'r', encoding='utf-8', errors='replace') as f:
                    for line in f:
                        try:
                            entry = json.loads(line.strip())

                            # Must be assistant with usage
                            if entry.get('type') != 'assistant':
                                continue

                            msg = entry.get('message', {})
                            if msg.get('role') != 'assistant':
                                continue

                            if 'usage' not in msg:
                                continue

                            # Skip synthetic
                            if entry.get('model') == '<synthetic>' or msg.get('model') == '<synthetic>':
                                continue

                            # Check timestamp in window
                            ts_str = entry.get('timestamp', '')
                            if not ts_str:
                                continue

                            try:
                                ts = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
                                if ts < cutoff_dt:
                                    continue
                            except:
                                continue

                            call = Call(entry, str(fpath))
                            calls.append(call)

                        except json.JSONDecodeError:
                            continue
                        except Exception:
                            continue
            except Exception:
                continue

    return calls


def deduplicate_calls(calls: List[Call]) -> List[Call]:
    """
    Purpose: dedupe by (message_id, request_id), keeping the one with largest output_tokens.
    Usage: deduped = deduplicate_calls(raw_calls)
    Gotchas: handles streaming updates where output grows across multiple entries.
    """
    groups = defaultdict(list)
    for call in calls:
        groups[call.dedup_key].append(call)

    deduped = []
    for key, group in groups.items():
        # Keep the one with largest output_tokens (ties: last one in list)
        best = max(group, key=lambda c: (c.output_tokens, calls.index(c)))
        deduped.append(best)

    return deduped


def write_cache(line: str, json_data: dict, state_dir: Path):
    """
    Purpose: write cached line and append to history with lock protection.
    Usage: write_cache(text_line, json_dict, state_dir_path)
    Gotchas: uses lock file so only one process writes at a time.
    """
    import fcntl
    import time

    state_dir.mkdir(parents=True, exist_ok=True)
    lock_path = state_dir / 'write.lock'

    # Acquire lock with timeout
    lock_acquired = False
    for attempt in range(10):
        try:
            lock_fd = os.open(lock_path, os.O_CREAT | os.O_WRONLY, 0o644)
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            lock_acquired = True
            break
        except (IOError, OSError):
            time.sleep(0.1)

    if not lock_acquired:
        sys.stderr.write('token-week: lock timeout, skipping write\n')
        return

    try:
        # Write latest.txt
        latest_path = state_dir / 'latest.txt'
        with open(latest_path, 'w', encoding='utf-8') as f:
            f.write(line)

        # Append to history.jsonl
        history_path = state_dir / 'history.jsonl'
        with open(history_path, 'a', encoding='utf-8') as f:
            f.write(json.dumps(json_data) + '\n')
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)


def main():
    # Parse args
    json_output = '--json' in sys.argv
    write_cache_mode = '--write-cache' in sys.argv

    # Root directory (env override for tests)
    root_dir = Path(os.environ.get('TOKEN_WEEK_ROOT', Path.home() / '.claude' / 'projects'))

    # Time window: last 14 days (to cover 2 weeks)
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(days=14)

    # Scan and parse
    calls = scan_transcripts(root_dir, cutoff)

    # Deduplicate
    calls = deduplicate_calls(calls)

    # Split into weeks
    week_boundary = now - timedelta(days=7)

    last_7d = [c for c in calls if c.timestamp_dt() >= week_boundary]
    prior_7d = [c for c in calls if c.timestamp_dt() < week_boundary]

    # Calculate totals
    last_7d_cost = sum(c.cost for c in last_7d)
    prior_7d_cost = sum(c.cost for c in prior_7d)

    # Change percentage
    if prior_7d_cost > 0:
        change_pct = ((last_7d_cost - prior_7d_cost) / prior_7d_cost) * 100
    else:
        change_pct = 0.0 if last_7d_cost == 0 else float('inf')

    # Subagent percentage (of last 7d)
    subagent_cost = sum(c.cost for c in last_7d if c.is_subagent)
    subagent_pct = (subagent_cost / last_7d_cost * 100) if last_7d_cost > 0 else 0.0

    # Top model (by cost in last 7d)
    model_costs = defaultdict(float)
    for c in last_7d:
        model_costs[c.model_key] += c.cost

    if model_costs:
        top_model = max(model_costs.items(), key=lambda x: x[1])
        top_model_name = top_model[0]
        top_model_pct = (top_model[1] / last_7d_cost * 100) if last_7d_cost > 0 else 0.0
    else:
        top_model_name = 'none'
        top_model_pct = 0.0

    # Build JSON data
    json_data = {
        'last_7d': round(last_7d_cost, 2),
        'prior_7d': round(prior_7d_cost, 2),
        'change_pct': round(change_pct, 1),
        'subagent_pct': round(subagent_pct, 0),
        'top_model': top_model_name,
        'top_model_pct': round(top_model_pct, 0),
    }

    # Build text line
    change_str = f"+{change_pct:.0f}" if change_pct > 0 else f"{change_pct:.0f}"
    line = (
        f"[Tokens] last 7d: ${last_7d_cost:.2f} "
        f"(prior 7d: ${prior_7d_cost:.2f}, change {change_str}%). "
        f"Subagents {subagent_pct:.0f}%. "
        f"Top model: {top_model_name} ({top_model_pct:.0f}%)."
    )

    # Write cache mode
    if write_cache_mode:
        state_dir = Path(os.environ.get('TOKEN_STATE_DIR', Path.home() / '.claude' / 'state' / 'tokens'))
        json_data['date'] = now.strftime('%Y-%m-%d')
        write_cache(line, json_data, state_dir)
        return

    # Output
    if json_output:
        print(json.dumps(json_data))
    else:
        print(line)


if __name__ == '__main__':
    main()

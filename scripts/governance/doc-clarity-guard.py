# ABOUTME: PostToolUse hook that records which owner-facing docs a session or subagent saved. It makes no model call and prints nothing.
# ABOUTME: doc-clarity-gate.py (Stop and SubagentStop) reads the list and blocks unclear docs. This file also holds the shared helpers.
# ABOUTME: Fails open: any error or timeout means no output and exit 0. Eligibility and numbers: policy/doc-gate.json.
# ABOUTME: Switch: HARNESS_DOC_CLARITY=0 turns it off. Spec: docs/plans/harness/doc-clarity-guard/spec-gate.md (REQ-D1).
# ABOUTME: Shared with the gate: sha, bare_codes (Part C), locked and update_json (private atomic JSON state under a lock).
import contextlib
import fcntl
import fnmatch
import hashlib
import json
import os
import re
import signal
import sys

HOME = os.path.expanduser('~/.claude')
POLICY_FILE = os.path.join(HOME, 'policy', 'doc-gate.json')
STATE_DIR = os.path.join(HOME, 'state', 'clarity')
PENDING_DIR = os.path.join(STATE_DIR, 'doc-pending')


def on_alarm(signum, frame):
    """Purpose: hard time limit. Usage: signal.signal(SIGALRM, on_alarm).
    Gotchas: calls nothing that can block, prints nothing, exits 0 at once."""
    os._exit(0)


def sha(s):
    """Purpose: sha256 hex of a string. Usage: sha(text). Gotchas: surrogate-safe."""
    return hashlib.sha256(s.encode('utf-8', 'ignore')).hexdigest()


def eligible(path, policy):
    """Purpose: should this written file be checked? Usage: eligible(path, policy) -> bool.
    Gotchas: extension is case-insensitive. Segments are the folder names only. ~/.claude, plans/ and README* are not skipped."""
    path = os.path.abspath(os.path.expanduser(path))
    base = os.path.basename(path)
    if os.path.splitext(base)[1].lower() not in policy['extensions'] or base in policy['skip_basenames']:
        return False
    if any(path.startswith(p) for p in policy['skip_prefixes']):
        return False
    # skip_globs: full-path patterns for test data, e.g. escalation test drafts (owner, 2026-11-27)
    if any(fnmatch.fnmatch(path, g) for g in policy.get('skip_globs', [])):
        return False
    return not set(os.path.dirname(path).split(os.sep)) & set(policy['skip_segments'])


def bare_codes(text, cfg):
    """Purpose: list the distinct bare codes (B4, A5a-04, S-39) a reader meets in prose. Usage: codes = bare_codes(text, policy['codes']).
    Gotchas: code fences, inline code and HTML comments are dropped first. Table cells under a header that matches
    ref_header_regex are skipped, so one reference column may hold ids. Returns codes in first-seen order."""
    # A fence closes only on a run of the same mark at least as long as the one that opened it.
    text = re.sub(r'(?ms)^[ \t]*(?P<f>(?P<c>[`~])(?P=c){2,})[^\n]*\n.*?^[ \t]*(?P=f)(?P=c)*[ \t]*$', ' ', text)
    text = re.sub(r'<!--.*?-->', ' ', text, flags=re.S)
    text = re.sub(r'`[^`\n]*`', ' ', text)
    code_re, ref_re = re.compile(cfg['regex']), re.compile(cfg['ref_header_regex'])
    lines, keep, skip_cols = text.split('\n'), [], set()
    sep = re.compile(r'\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*')
    for i, line in enumerate(lines):
        nxt = lines[i + 1] if i + 1 < len(lines) else ''
        starts = not skip_cols and '|' in line and sep.fullmatch(nxt)
        if '|' not in line or not (skip_cols or starts):
            skip_cols = set()
            keep.append(line)
            continue
        # Escaped pipes stay inside their cell.
        cells = [c.replace('\0', '|') for c in line.replace('\\|', '\0').strip().strip('|').split('|')]
        if starts:
            # Header row: remember which columns are reference columns.
            skip_cols = {j for j, c in enumerate(cells) if ref_re.search(c)} or {-1}
        if re.fullmatch(r'[\s:-]*', ''.join(cells)):
            continue
        keep.append(' '.join(c for j, c in enumerate(cells) if j not in skip_cols))
    seen = []
    for c in code_re.findall('\n'.join(keep)):
        if c not in seen:
            seen.append(c)
    return seen

@contextlib.contextmanager
def locked():
    """Purpose: one exclusive lock for every read-modify-write of the doc state files.
    Usage: with locked(): ... Gotchas: the lock file lives in the state folder; it is released when the block ends or the process dies."""
    os.makedirs(STATE_DIR, exist_ok=True)
    fd = os.open(os.path.join(STATE_DIR, 'doc-gate.lock'), os.O_WRONLY | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def read_json(path, default):
    """Purpose: load a JSON object file. Usage: read_json(path, {}).
    Gotchas: a missing file gives the default. A file that is not a JSON object raises."""
    try:
        with open(path, encoding='utf-8') as fh:
            d = json.load(fh)
    except FileNotFoundError:
        return default
    if not isinstance(d, dict):
        raise ValueError('state file is not a map')
    return d


def write_json(path, data):
    """Purpose: atomic private write of a JSON file (mode 0600). Usage: write_json(path, data).
    Gotchas: temp file in the same folder, then replace. O_NONBLOCK so a stuck file cannot hang."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = '%s.%d.tmp' % (path, os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NONBLOCK, 0o600)
    with os.fdopen(fd, 'w', encoding='utf-8') as fh:
        json.dump(data, fh)
    os.replace(tmp, path)


def safe_name(session_id):
    """Purpose: turn a session id into a safe file name. Usage: safe_name(id). Gotchas: anything outside letters, digits, dash and underscore becomes an underscore."""
    return re.sub(r'[^A-Za-z0-9_-]', '_', str(session_id))


def record(session_id, agent_id, path):
    """Purpose: add a saved doc path to the session's pending list and, if given, the agent's list.
    Usage: record(session_id, agent_id_or_None, abs_path). Gotchas: a path appears at most once per list. Atomic write under the lock."""
    file = os.path.join(PENDING_DIR, safe_name(session_id) + '.json')
    with locked():
        pending = read_json(file, {})
        for key in ('main', agent_id):
            if key is None:
                continue
            lst = pending.get(key)
            lst = lst if isinstance(lst, list) else []
            if path not in lst:
                lst.append(path)
            pending[key] = lst
        write_json(file, pending)


def run(raw):
    """Purpose: do the whole hook job for one payload. Usage: run(stdin_text).
    Gotchas: records only eligible files that are at least min_chars long. Never raises past the caller's catch."""
    payload = json.loads(raw)
    policy = json.load(open(POLICY_FILE))
    path = os.path.abspath(os.path.expanduser(payload['tool_input']['file_path']))
    if not eligible(path, policy):
        return
    with open(path, encoding='utf-8', errors='ignore') as fh:
        if len(fh.read()) < policy['min_chars']:
            return
    agent = payload.get('agent_id')
    record(payload['session_id'], agent if isinstance(agent, str) and agent else None, path)


def main():
    """Purpose: PostToolUse hook entry. Usage: python3 -I ~/.claude/scripts/governance/doc-clarity-guard.py < payload.json.
    Gotchas: the alarm is set before stdin is read. A bad policy or alarm_s below 1 means a silent exit. No output, exit is always 0."""
    if os.environ.get('HARNESS_DOC_CLARITY') == '0':
        return
    signal.signal(signal.SIGALRM, on_alarm)
    secs = json.load(open(POLICY_FILE))['alarm_s']
    if isinstance(secs, bool) or not isinstance(secs, int) or secs < 1:
        return
    signal.alarm(secs)
    run(sys.stdin.read())


if __name__ == '__main__':
    try:
        main()
    except BaseException:
        pass
    os._exit(0)

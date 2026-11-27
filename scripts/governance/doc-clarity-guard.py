# ABOUTME: PostToolUse hook that warns when an owner-facing doc lacks a recommendation, gains and costs, or framed decisions.
# ABOUTME: Asks one OpenJev request with six questions, then adds a warning as additionalContext. It never blocks.
# ABOUTME: Fails open: any error, timeout or bad answer means no output and exit 0. All numbers and text: policy/doc-gate.json.
# ABOUTME: Switch: HARNESS_DOC_CLARITY=0 turns it off. Spec: docs/plans/harness/doc-clarity-guard/spec.md Part B.
import hashlib
import importlib.util
import json
import math
import os
import signal
import sys
import time

HOME = os.path.expanduser('~/.claude')
POLICY_FILE = os.path.join(HOME, 'policy', 'doc-gate.json')
REPLY_POLICY_FILE = os.path.join(HOME, 'policy', 'reply-gate.json')
SEEN_FILE = os.path.join(HOME, 'state', 'clarity', 'doc-gate-seen.json')
LOG_FILE = os.path.join(HOME, 'state', 'clarity', 'doc-log.jsonl')
GOVERNANCE = os.path.join(HOME, 'scripts', 'governance')
QUESTIONS = ('is_owner_report', 'says_what_to_do', 'gains_costs', 'has_decisions', 'decisions_framed', 'plain')


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
    return not set(os.path.dirname(path).split(os.sep)) & set(policy['skip_segments'])


def read_seen():
    """Purpose: load the seen-hash map {path hash: {'h': text hash, 't': time}}. Usage: seen = read_seen().
    Gotchas: a missing file gives an empty map. Any other read or parse error removes the file, then raises to the silent exit."""
    try:
        with open(SEEN_FILE, encoding='utf-8') as fh:
            d = json.load(fh)
        if not isinstance(d, dict):
            raise ValueError('seen file is not a map')
        return d
    except FileNotFoundError:
        return {}
    except Exception:
        try:
            os.remove(SEEN_FILE)
        except Exception:
            pass
        raise


def write_seen(seen, key, text_hash, cap):
    """Purpose: remember a text hash for a path and keep at most cap entries, oldest dropped.
    Usage: write_seen(seen, sha(path), sha(text), 500). Gotchas: any error propagates to the silent exit. Atomic replace."""
    seen.pop(key, None)
    seen[key] = {'h': text_hash, 't': time.time()}
    for k in sorted(seen, key=lambda k: seen[k].get('t', 0) if isinstance(seen[k], dict) else 0)[:max(0, len(seen) - cap)]:
        del seen[k]
    os.makedirs(os.path.dirname(SEEN_FILE), exist_ok=True)
    tmp = '%s.%d.tmp' % (SEEN_FILE, os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NONBLOCK, 0o600)
    with os.fdopen(fd, 'w', encoding='utf-8') as fh:
        json.dump(seen, fh)
    os.replace(tmp, SEEN_FILE)


def log_line(record):
    """Purpose: append one JSON line to the doc log, private to the owner.
    Usage: log_line({...}); never include text or the plain path. Gotchas: any error propagates to the silent exit. O_NONBLOCK so a stuck file cannot hang."""
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    data = (json.dumps(record, allow_nan=False) + '\n').encode()
    fd = os.open(LOG_FILE, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NONBLOCK, 0o600)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)
    os.chmod(LOG_FILE, 0o600)


def valid(answers):
    """Purpose: check every question has a finite noul number in 0..1. Usage: valid(answers) -> bool.
    Gotchas: a bool is not a number. Unknown stays unknown, no default is filled in."""
    if not isinstance(answers, dict):
        return False
    for q in QUESTIONS:
        a = answers.get(q)
        v = a.get('noul') if isinstance(a, dict) else None
        if not (isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and 0 <= v <= 1):
            return False
    return True


def findings(n, structure, policy):
    """Purpose: turn the six numbers into the three finding flags. Usage: f = findings(noul_dict, structure_ok_bool, policy).
    Gotchas: a non-report never warns, so every flag is False then. The plain number is logged only and never warns."""
    lo = policy['min']
    if n['is_owner_report'] < policy['report_min']:
        return {'no_action': False, 'no_gain_cost': False, 'unframed': False}
    return {'no_action': n['says_what_to_do'] < lo, 'no_gain_cost': n['gains_costs'] < lo,
            'unframed': n['has_decisions'] >= lo and (n['decisions_framed'] < lo or not structure)}


def message(path, flags, policy):
    """Purpose: build the warning text. Usage: message(path, flags, policy) -> str.
    Gotchas: spaces in the path become underscores so it counts as one word; if still over word_limit the folder is dropped."""
    m = policy['message']
    parts = [m[k] for k in ('no_action', 'no_gain_cost', 'unframed') if flags[k]]
    shown = path.replace(HOME, '~/.claude').replace(' ', '_')
    for p in (shown, os.path.basename(shown)):
        text = ' '.join([m['head'].format(path=p)] + parts + [m['tail']])
        if len(text.split()) <= m['word_limit']:
            return text
    return text


def run(raw, rec):
    """Purpose: do the whole hook job for one payload. Usage: out = run(stdin_text, rec); returns the warning or None.
    Gotchas: rec is filled in place and logged only when a model check ran. Never raises past the caller's catch."""
    t0 = time.monotonic()
    sys.path.insert(0, GOVERNANCE)
    import clarity_jev
    spec = importlib.util.spec_from_file_location('reply_clarity_gate', os.path.join(GOVERNANCE, 'reply-clarity-gate.py'))
    reply_gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reply_gate)
    policy = json.load(open(POLICY_FILE))
    path = os.path.abspath(os.path.expanduser(json.loads(raw)['tool_input']['file_path']))
    if not eligible(path, policy):
        return None
    with open(path, encoding='utf-8', errors='ignore') as fh:
        text = fh.read()
    if len(text) < policy['min_chars']:
        return None
    pkey, thash = sha(path), sha(text)
    seen = read_seen()
    if isinstance(seen.get(pkey), dict) and seen[pkey].get('h') == thash:
        return None
    body = {'model': policy['model'], 'state': {'reader': policy['reader_owner'], 'message': clarity_jev.redact(text)[0]},
            'questions': policy['questions']}
    answers, ms = clarity_jev.post_body(body, deadline=policy['deadline_s'])
    if not valid(answers):
        return None
    n = {q: answers[q]['noul'] for q in QUESTIONS}
    structure = reply_gate.structure_ok(text, json.load(open(REPLY_POLICY_FILE))['choice'])
    flags = findings(n, structure, policy)
    write_seen(seen, pkey, thash, policy['seen_cap'])
    rec.update(path=pkey, chars=len(text), answers=n, flags=flags, ms=ms)
    return message(path, flags, policy) if any(flags.values()) else None


def main():
    """Purpose: PostToolUse hook entry. Usage: python3 -I ~/.claude/scripts/governance/doc-clarity-guard.py < payload.json.
    Gotchas: the alarm is set before stdin is read. A bad policy or alarm_s below 1 means a silent exit. Output is a warning only, exit is always 0."""
    if os.environ.get('HARNESS_DOC_CLARITY') == '0':
        return
    signal.signal(signal.SIGALRM, on_alarm)
    secs = json.load(open(POLICY_FILE))['alarm_s']
    if isinstance(secs, bool) or not isinstance(secs, int) or secs < 1:
        return
    signal.alarm(secs)
    rec = {}
    out = run(sys.stdin.read(), rec)
    if rec:
        log_line({'time': round(time.time(), 3), 'path_sha256': rec['path'], 'chars': rec['chars'],
                  'answers': rec['answers'], 'flags': rec['flags'], 'ms': rec['ms']})
    if out:
        sys.stdout.write(json.dumps({'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': out}}, ensure_ascii=False))
        sys.stdout.flush()


if __name__ == '__main__':
    try:
        main()
    except BaseException:
        pass
    os._exit(0)

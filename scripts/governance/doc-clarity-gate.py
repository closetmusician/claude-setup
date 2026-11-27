# ABOUTME: Stop, SubagentStop and PreToolUse(SubagentHandback) hook that blocks unclear owner docs and forces a rewrite.
# ABOUTME: Reads the docs saved this session (or by this subagent), asks a headless Claude reader, blocks with the problem list.
# ABOUTME: Round 1 reads the whole doc. Later rounds only re-check the old problems. At most max_rewrites rewrite blocks, then one partial-report block.
# ABOUTME: Fails open: any error or timeout means no block and the doc stays pending. Switch: HARNESS_DOC_CLARITY=0 turns it off.
# ABOUTME: Spec: docs/plans/harness/doc-clarity-guard/spec-gate.md (REQ-D2 to D9). Numbers and prompts: policy/doc-gate.json "gate".
import concurrent.futures
import importlib.util
import json
import os
import signal
import subprocess
import sys
import tempfile
import time

HOME = os.path.expanduser('~/.claude')
GOVERNANCE = os.path.join(HOME, 'scripts', 'governance')
HEADLESS = os.path.join(HOME, 'scripts', 'lib', 'claude-headless.sh')
ROUNDS_DIR = os.path.join(HOME, 'state', 'clarity', 'doc-gate-rounds')
LOG_FILE = os.path.join(HOME, 'state', 'clarity', 'doc-log.jsonl')
# Every gate switch the nested reader call must turn off, so it cannot trigger another gate.
SWITCHES = ('HARNESS_DOC_CLARITY', 'HARNESS_REPLY_CLARITY', 'HARNESS_REPLY_GATE', 'HARNESS_STE_LINT', 'HARNESS_QUESTION_GUARD')

spec = importlib.util.spec_from_file_location('doc_clarity_guard', os.path.join(GOVERNANCE, 'doc-clarity-guard.py'))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


def on_alarm(signum, frame):
    """Purpose: hard time limit. Usage: signal.signal(SIGALRM, on_alarm).
    Gotchas: exits 0 at once with no output, so a slow gate never strands a session."""
    os._exit(0)


def log_line(record):
    """Purpose: append one JSON line to the doc log, private to the owner. Usage: log_line({...}).
    Gotchas: never put text, the plain path or problem words in it. Any error propagates to the caller's catch."""
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    data = (json.dumps(record, allow_nan=False) + '\n').encode()
    fd = os.open(LOG_FILE, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NONBLOCK, 0o600)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)
    os.chmod(LOG_FILE, 0o600)


def parse_json(out):
    """Purpose: turn the reader's reply into a dict. Usage: parse_json(stdout) -> dict.
    Gotchas: drops a ```json fence, then tries the whole text, then the first { to the last }. Raises when nothing parses to an object."""
    s = out.strip()
    if s.startswith('```'):
        s = s.split('\n', 1)[-1].rsplit('```', 1)[0]
    for cand in (s, s[s.find('{'):s.rfind('}') + 1]):
        try:
            d = json.loads(cand)
        except ValueError:
            continue
        if isinstance(d, dict):
            return d
    raise ValueError('reader reply is not a JSON object')


def ask_reader(prompt, cfg):
    """Purpose: run one headless Claude call on the Claude.ai plan and return its parsed JSON answer.
    Usage: ask_reader(full_prompt, policy['gate']). Gotchas: no tools, no settings (so no hooks), gate switches off, own temp cwd.
    A non-zero exit, a timeout or a bad reply raises, which the caller treats as a fail-open error."""
    env = dict(os.environ, **{k: '0' for k in SWITCHES})
    r = subprocess.run([HEADLESS, '-p', '--model', cfg['model'], '--tools', '', '--setting-sources', '', '--no-session-persistence'],
                       input=prompt, capture_output=True, text=True, timeout=cfg['reader_timeout_s'], env=env, cwd=tempfile.gettempdir())
    if r.returncode != 0:
        raise RuntimeError('reader exit %d' % r.returncode)
    return parse_json(r.stdout)


def clean_items(items, cap, status=False):
    """Purpose: validate a list of {where, text, fix} dicts from the reader. Usage: clean_items(list, 12).
    Gotchas: every field must be a string, or it raises. With status=True each item also needs status FIXED or OPEN. Cut to cap."""
    if not isinstance(items, list):
        raise ValueError('items is not a list')
    out = []
    for it in items:
        if not isinstance(it, dict) or not all(isinstance(it.get(k), str) for k in ('where', 'text', 'fix')):
            raise ValueError('bad item')
        row = {k: it[k] for k in ('where', 'text', 'fix')}
        if status:
            if it.get('status') not in ('FIXED', 'OPEN'):
                raise ValueError('bad status')
            row['status'] = it['status']
        out.append(row)
    return out[:cap]


def full_read(text, cfg, policy):
    """Purpose: round 1. Bare-code count, then the whole-doc reader. Usage: full_read(text, gate_cfg, policy) -> (verdict, problems).
    Gotchas: a doc the reader calls not an owner report passes and drops the code finding. A BLOCK with no problems raises."""
    d = ask_reader(cfg['reader_prompt'] + '\n\nThe document:\n' + text, cfg)
    if not isinstance(d.get('is_owner_report'), bool) or d.get('verdict') not in ('PASS', 'BLOCK'):
        raise ValueError('bad reader answer')
    if 'problems' not in d:
        raise ValueError('reader answer has no problems list')
    problems = clean_items(d['problems'], cfg['max_problems'])
    if not d['is_owner_report']:
        return 'PASS', []
    if d['verdict'] == 'BLOCK' and not problems:
        raise ValueError('BLOCK with no problems')
    codes = guard.bare_codes(text, policy['codes'])
    if len(codes) >= policy['codes']['min_distinct']:
        problems.insert(0, {'where': 'whole document', 'text': ', '.join(codes[:policy['codes']['examples']]),
                            'fix': cfg['code_finding_fix']})
        return 'BLOCK', problems[:cfg['max_problems']]
    return d['verdict'], problems if d['verdict'] == 'BLOCK' else []


def narrow_read(text, last, cfg):
    """Purpose: round 2 and later. The reader judges only the earlier problem list, plus new codes in rewritten text.
    Usage: narrow_read(text, last_problems, gate_cfg) -> (verdict, open_items). Gotchas: the verdict is computed here, not taken from the
    reader. open_items is the full list, also on PASS. A reader answer that skips an earlier problem raises. PASS when at most recheck_max_open items stay open and the reader found nothing new."""
    prompt = cfg['recheck_prompt'] + '\n\nEarlier problem list:\n' + json.dumps(last, ensure_ascii=False) + '\n\nThe new document:\n' + text
    d = ask_reader(prompt, cfg)
    items = clean_items(d.get('items'), len(last) + 1, status=True)
    if [(i['where'], i['text']) for i in items] != [(i['where'], i['text']) for i in last]:
        raise ValueError('reader gave no verdict for some earlier problems')
    if 'new' not in d:
        raise ValueError('reader answer has no new list')
    new = clean_items(d['new'], cfg['max_problems'])
    open_items = [{k: i[k] for k in ('where', 'text', 'fix')} for i in items if i['status'] == 'OPEN'] + new
    ok = len(open_items) - len(new) <= cfg['recheck_max_open'] and not new
    return ('PASS' if ok else 'BLOCK'), open_items


def check_doc(path, text, st, policy):
    """Purpose: one reader pass over a changed doc, in a worker thread. Usage: check_doc(path, text, state_entry, policy).
    Gotchas: returns a dict and never raises. kind is 'error' on any failure; round is 1 unless an earlier problem list exists."""
    cfg = policy['gate']
    last = st.get('problems') or []
    rnd = st.get('round', 0) + 1 if last else 1
    t0 = time.monotonic()
    try:
        verdict, problems = narrow_read(text, last, cfg) if last else full_read(text, cfg, policy)
        n_open = len(problems)
        problems = problems if verdict == 'BLOCK' else []
        return {'kind': verdict, 'problems': problems, 'open': n_open, 'round': rnd, 'ms': int((time.monotonic() - t0) * 1000)}
    except Exception:
        return {'kind': 'error', 'problems': [], 'open': None, 'round': rnd, 'ms': int((time.monotonic() - t0) * 1000)}


def lines(problems):
    """Purpose: format problems as <where>: "<text>" -> <fix> lines. Usage: lines(list) -> list of str. Gotchas: input already cut to 12."""
    return ['%s: "%s" -> %s' % (p['where'], p['text'], p['fix']) for p in problems]


def build_reason(rewrites, limits, cfg):
    """Purpose: build the block message. Usage: build_reason([(path, problems)], [(path, problems)], gate_cfg) -> str.
    Gotchas: paths are sorted for a stable order. Rewrite docs share one closing instruction; each limit doc gets its own partial-report line."""
    parts = []
    for path, problems in sorted(rewrites):
        parts.append('\n'.join(['Unclear doc: ' + path] + lines(problems)))
    if rewrites:
        parts.append(cfg['rewrite_message'])
    for path, problems in sorted(limits):
        shown = '; '.join('%s: "%s"' % (p['where'], p['text']) for p in problems[:cfg['max_problems']])
        parts.append(cfg['limit_message'].format(path=path, n=cfg['max_rewrites'], items='%s (%d open)' % (shown, len(problems))))
    return '\n\n'.join(parts)


def still_same(path, h):
    """Purpose: tell whether a doc still has the text the gate checked. Usage: still_same(path, sha) -> bool.
    Gotchas: a missing file counts as same (nothing left to check). Any other read error counts as changed, so the doc stays pending."""
    try:
        with open(path, encoding='utf-8', errors='ignore') as fh:
            return guard.sha(fh.read()) == h
    except (FileNotFoundError, NotADirectoryError):
        return True
    except OSError:
        return False


def run(payload):
    """Purpose: the whole gate job for one Stop or SubagentStop payload. Usage: out = run(payload_dict); returns the block reason or None.
    Gotchas: pending docs leave the list on PASS, on the limit block, on a missing file, or when the doc is past its block limit.
    A reader error leaves the doc pending with no counter change. State is saved once at the end, under the lock."""
    event, session, agent = payload.get('hook_event_name'), payload.get('session_id'), payload.get('agent_id')
    if event == 'PreToolUse' and payload.get('tool_name') == 'SubagentHandback':
        # A background agent hands back through this tool before SubagentStop fires, so a SubagentStop block
        # arrives too late to force a rewrite. Checking here makes the agent fix the doc before it hands back.
        event = 'SubagentStop'
    if event == 'SubagentStop' and not (isinstance(agent, str) and agent):
        return None
    if event not in ('Stop', 'SubagentStop') or not session:
        return None
    key = 'main' if event == 'Stop' else agent
    policy = json.load(open(guard.POLICY_FILE))
    cfg = policy['gate']
    name = guard.safe_name(session) + '.json'
    pending_file, rounds_file = os.path.join(guard.PENDING_DIR, name), os.path.join(ROUNDS_DIR, name)
    with guard.locked():
        pending = guard.read_json(pending_file, {})
        rounds = guard.read_json(rounds_file, {})
    paths = [p for p in pending.get(key, []) if isinstance(p, str)]
    done, work, decided, checked = set(), {}, [], {}
    for path in paths:
        try:
            with open(path, encoding='utf-8', errors='ignore') as fh:
                text = fh.read()
        except (FileNotFoundError, NotADirectoryError):
            done.add(path)
            continue
        except OSError:
            continue
        h = guard.sha(text)
        checked[path] = h
        st = rounds.get(guard.sha(path), {})
        if st.get('pass_hash') == h or st.get('blocks', 0) > cfg['max_rewrites']:
            done.add(path)
        elif st.get('problems') and st.get('block_hash') == h:
            decided.append((path, h, st, {'kind': 'BLOCK', 'problems': st['problems'], 'open': len(st['problems']), 'round': st.get('round', 1), 'ms': None}))
        else:
            work[path] = (text, h, st)
    if work:
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(work)) as pool:
            futures = {p: pool.submit(check_doc, p, t, st, policy) for p, (t, h, st) in work.items()}
            for p, (t, h, st) in work.items():
                decided.append((p, h, st, futures[p].result()))
    rewrites, limits, rows, saved = [], [], [], {}
    for path, h, st, res in decided:
        pkey = guard.sha(path)
        new = dict(st)
        if res['kind'] == 'PASS':
            new.update(pass_hash=h)
            new.pop('problems', None)
            new.pop('block_hash', None)
            saved[pkey] = new
            done.add(path)
            outcome = 'pass'
        elif res['kind'] == 'BLOCK':
            blocks = st.get('blocks', 0)
            new.update(round=res['round'], problems=res['problems'][:cfg['max_problems']], block_hash=h, blocks=blocks + 1)
            saved[pkey] = new
            if blocks >= cfg['max_rewrites']:
                limits.append((path, res['problems']))
                done.add(path)
                outcome = 'limit'
            else:
                rewrites.append((path, res['problems'][:cfg['max_problems']]))
                outcome = 'block'
        else:
            outcome = 'error'
        if res['ms'] is not None:
            known = res['kind'] != 'error'
            rows.append({'time': round(time.time(), 3), 'path_sha256': pkey, 'round': res['round'],
                         'verdict': res['kind'] if known else None, 'problems': len(res['problems']) if known else None,
                         'open': res['open'] if known else None, 'ms': res['ms'], 'outcome': outcome})
    with guard.locked():
        # Re-read both files so saves made during the reader calls are kept; only this run's docs are updated.
        pending = guard.read_json(pending_file, {})
        # A doc saved again during the reader call stays pending: it leaves only if it still has the checked text.
        gone = {p for p in done if p not in checked or still_same(p, checked[p])}
        for k in list(pending):
            pending[k] = [p for p in pending[k] if p not in gone]
        guard.write_json(pending_file, pending)
        rounds = guard.read_json(rounds_file, {})
        rounds.update(saved)
        guard.write_json(rounds_file, rounds)
    for row in rows:
        try:
            log_line(row)
        except Exception:
            pass
    return build_reason(rewrites, limits, cfg) if rewrites or limits else None


def main():
    """Purpose: Stop, SubagentStop and PreToolUse(SubagentHandback) hook entry. Usage: python3 -I ~/.claude/scripts/governance/doc-clarity-gate.py < payload.json.
    Gotchas: the alarm fires 10 s before the hook timeout and exits 0 with no output. Output is the block JSON or nothing. Exit is always 0."""
    if os.environ.get('HARNESS_DOC_CLARITY') == '0':
        return
    signal.signal(signal.SIGALRM, on_alarm)
    secs = json.load(open(guard.POLICY_FILE))['gate']['hook_timeout_s'] - 10
    if isinstance(secs, bool) or not isinstance(secs, int) or secs < 1:
        return
    signal.alarm(secs)
    payload = json.loads(sys.stdin.read())
    reason = run(payload)
    if reason and payload.get('hook_event_name') == 'PreToolUse':
        sys.stdout.write(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny',
                                                            'permissionDecisionReason': reason}}, ensure_ascii=False))
        sys.stdout.flush()
    elif reason:
        sys.stdout.write(json.dumps({'decision': 'block', 'reason': reason}, ensure_ascii=False))
        sys.stdout.flush()


if __name__ == '__main__':
    try:
        main()
    except BaseException:
        pass
    os._exit(0)

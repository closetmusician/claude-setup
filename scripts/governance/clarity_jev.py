# ABOUTME: Client that asks OpenJev (on Codiv) the clarity tests for one reply or question.
# ABOUTME: Reads TYPESAFE_API_KEY from ~/.claude/.env, removes secrets, sends one request, times it.
# ABOUTME: Logs one line per call to ~/.claude/state/clarity/log.jsonl: timings, tokens, scores. No text.
# ABOUTME: Fails open: any error, 429 or 529 returns answers=None and the reason in the metrics.
# ABOUTME: Used by the reply and question clarity hooks and by clarity_eval.py. Spec: docs/plans/harness/reply-clarity-guard/spec.md.
import hashlib
import http.client
import json
import os
import re
import ssl
import time

HOME = os.path.expanduser('~/.claude')
ENV_FILE = os.path.join(HOME, '.env')
RULES_FILE = os.path.join(HOME, 'policy', 'clarity-tests.json')
LOG_FILE = os.path.join(HOME, 'state', 'clarity', 'log.jsonl')
# Same provider-token patterns as scripts/secret-scan.sh, plus generic key=value secrets.
SECRET = re.compile(
    r'ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{22,}|ATATT[A-Za-z0-9_=.-]{20,}'
    r'|sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,}'
    r'|-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----'
    r'|glpat-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{35}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
    r'|(?i:(?:password|passwd|secret|api[_-]?key|token)["\']?\s*[=:]\s*["\']?)[^\s"\']{8,}')


def load_key():
    """Purpose: read the OpenJev key and base URL from ~/.claude/.env.
    Usage: key, base = load_key(); key is None when the file or the key is missing.
    Gotchas: never print the key. Accepts 'export K=V' and quoted values."""
    env = {}
    try:
        for line in open(ENV_FILE):
            line = line.strip()
            if '=' in line and not line.startswith('#'):
                k, v = line.removeprefix('export ').split('=', 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    except (OSError, ValueError):  # ValueError covers a file that is not valid UTF-8
        return None, None
    return env.get('TYPESAFE_API_KEY'), env.get('CODIV_BASE_URL', 'https://api.codiv.ai').rstrip('/')


def load_rules(path=RULES_FILE):
    """Purpose: read the clarity rules file (tests, framing, limits, version).
    Usage: rules = load_rules(); rules['tests'] maps test id to its definition.
    Gotchas: raises on a missing or bad file; callers that must fail open catch it."""
    with open(path) as f:
        return json.load(f)


def tests_for(rules, hook):
    """Purpose: pick the tests one hook sends, in OpenJev question format.
    Usage: questions = tests_for(rules, 'reply').
    Gotchas: only type, instructions and criteria go to the server; limits stay local."""
    out = {}
    for tid, t in rules['tests'].items():
        if hook in t.get('hooks', []):
            q = {'type': t['type'], 'instructions': t['instructions']}
            if t.get('criteria'):
                q['criteria'] = t['criteria']
            out[tid] = q
    return out


def redact(text):
    """Purpose: replace passwords, tokens and keys with [SECRET] before text leaves the machine.
    Usage: safe = redact(reply_text).
    Gotchas: pattern based, so it catches known shapes only. Count returned for the log."""
    return SECRET.subn('[SECRET]', text)


def _value(answer):
    """Purpose: turn one OpenJev answer into a number: yes-chance or expected score level.
    Usage: v = _value(resp['answers']['hidden_pointer']).
    Gotchas: returns None for an answer type this client does not know."""
    if 'noul' in answer:
        return answer['noul']
    if 'score' in answer:
        return answer['score']
    return None


def ask(text, questions, *, hook, framing, max_chars=6000, deadline=3.0, rules_version=None, log=True,
        model='openjev-latest', read_options=None, examples=None):
    """Purpose: send one text with its tests to OpenJev and time every step.
    Usage: answers, m = ask(reply, tests_for(rules, 'reply'), hook='reply', framing=rules['framing']).
    model, read_options (steps, samples, think) and examples come from the rules file. With examples,
    the state is JSON: the reader, the labelled examples, then the message to judge.
    Gotchas: answers is None on any failure (fail open). m always has the timings and the reason.
    The deadline covers connect, send and read together; each step gets what is left, and an answer
    that arrives after the deadline counts as a failure. DNS lookup is not bounded here: the hooks add
    their own process alarm as the hard limit."""
    t0 = time.monotonic()
    m = {'ts': round(time.time(), 3), 'hook': hook, 'rules_version': rules_version, 'req_model': model,
         'chars': len(text), 'max_chars': max_chars, 'n_tests': len(questions)}
    redacted, m['secrets_removed'] = redact(text)  # redact before clipping, so no cut-off secret survives
    safe = redacted[:max_chars]
    m['clipped'] = len(redacted) > max_chars
    m['text_hash'] = hashlib.sha256(text.encode()).hexdigest()[:16]
    answers = None
    key, base = load_key()
    if not key:
        m['error'] = 'no_key'
        return _finish(answers, m, t0, log)
    host = base.split('://', 1)[-1].split('/', 1)[0]
    if examples:
        state = {'reader': framing, 'examples': examples, 'message_to_judge': safe}
    else:
        state = framing + '\n\n' + safe
    body = json.dumps(dict(read_options or {}, model=model, state=state, questions=questions)).encode()
    conn = None
    try:
        conn = http.client.HTTPSConnection(host, timeout=deadline, context=ssl.create_default_context())
        conn.connect()
        m['connect_ms'] = _ms(t0)
        conn.sock.settimeout(max(0.05, deadline - (time.monotonic() - t0)))
        conn.request('POST', '/v1/systemone', body=body, headers={
            'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
        conn.sock.settimeout(max(0.05, deadline - (time.monotonic() - t0)))
        resp = conn.getresponse()
        m['first_byte_ms'] = _ms(t0)
        conn.sock.settimeout(max(0.05, deadline - (time.monotonic() - t0)))
        raw = resp.read()
        m['status'] = resp.status
        m['request_id'] = resp.getheader('x-request-id')
        st = resp.getheader('server-timing') or ''
        dur = re.search(r'model;dur=([\d.]+)', st)
        m['model_ms'] = float(dur.group(1)) if dur else None
        if resp.status != 200:
            m['error'] = 'http_%d' % resp.status
        else:
            r = json.loads(raw)
            m['model'] = r.get('model')
            m['input_tokens'] = (r.get('usage') or {}).get('input_tokens')
            got = {k: float(_value(v)) for k, v in (r.get('answers') or {}).items() if _value(v) is not None}
            conf = {k: round(float(v['confidence']), 3) for k, v in (r.get('answers') or {}).items()
                    if 'confidence' in v}
            if time.monotonic() - t0 > deadline:
                m['error'] = 'deadline'
            else:
                answers, m['confidence'] = got, conf
    except Exception as e:  # fail open on every network or parse error
        m['error'] = type(e).__name__
    finally:
        if conn:
            conn.close()
    return _finish(answers, m, t0, log)


def post_body(body, deadline=3.0):
    """Purpose: send one ready OpenJev request body and time it.
    Usage: answers, ms = post_body({'model': m, 'state': {...}, 'questions': {...}}, deadline=3.0).
    Gotchas: answers is the raw 'answers' dict (noul and score values, legends), or None on any failure
    (fail open). The deadline covers connect, send and read together; DNS lookup is not bounded here.
    Writes no log line, so a caller can run it on a thread."""
    t0 = time.monotonic()
    answers = None
    key, base = load_key()
    conn = None
    try:
        if not key:
            raise ValueError('no_key')
        host = base.split('://', 1)[-1].split('/', 1)[0]
        conn = http.client.HTTPSConnection(host, timeout=deadline, context=ssl.create_default_context())
        conn.connect()
        conn.sock.settimeout(max(0.05, deadline - (time.monotonic() - t0)))
        conn.request('POST', '/v1/systemone', body=json.dumps(body).encode(), headers={
            'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
        conn.sock.settimeout(max(0.05, deadline - (time.monotonic() - t0)))
        resp = conn.getresponse()
        conn.sock.settimeout(max(0.05, deadline - (time.monotonic() - t0)))
        raw = resp.read()
        if resp.status == 200 and time.monotonic() - t0 <= deadline:
            answers = json.loads(raw).get('answers')
    except Exception:  # fail open on every network or parse error
        answers = None
    finally:
        if conn:
            conn.close()
    return answers, _ms(t0)


def _ms(t0):
    """Purpose: milliseconds since t0, rounded.
    Usage: m['connect_ms'] = _ms(t0).
    Gotchas: uses the monotonic clock, so it is safe across clock changes."""
    return round((time.monotonic() - t0) * 1000, 1)


def _finish(answers, m, t0, log):
    """Purpose: add total time and the scores, then write the log line.
    Usage: return _finish(answers, m, t0, log).
    Gotchas: a log write error never fails the call. The log holds scores, never text."""
    m['total_ms'] = _ms(t0)
    m['scores'] = {k: round(v, 3) for k, v in (answers or {}).items() if v is not None}
    if log:
        try:
            os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
            fd = os.open(LOG_FILE, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            with os.fdopen(fd, 'a') as f:
                f.write(json.dumps(m) + '\n')
        except OSError:
            pass
    return answers, m

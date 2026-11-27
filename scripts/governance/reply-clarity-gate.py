# ABOUTME: Stop hook that makes the assistant rewrite its worst replies once, and logs a score for every reply.
# ABOUTME: Sends two OpenJev requests, turns the answers into a fitted score, and blocks above a fixed limit.
# ABOUTME: Also blocks a reply that asks the owner to choose but has no Good:, Bad: and Recommend: lines.
# ABOUTME: Fails open: any error means no block. Numbers live in policy/reply-gate.json. Spec: docs/plans/harness/reply-clarity-guard/reply-gate-spec.md.
# ABOUTME: Switches: HARNESS_REPLY_CLARITY=0 turns it off; HARNESS_REPLY_GATE=log scores and logs but never blocks.
import hashlib
import json
import math
import os
import re
import signal
import sys
import threading
import time

HOME = os.path.expanduser('~/.claude')
POLICY_FILE = os.path.join(HOME, 'policy', 'reply-gate.json')
LOG_FILE = os.path.join(HOME, 'state', 'clarity', 'reply-log.jsonl')
TURNS_DIR = os.path.expanduser('~/.claude/state/clarity/gate-turns')  # one rewrite counter file per session
GOVERNANCE = os.path.join(HOME, 'scripts', 'governance')
clarity_jev = clarity_names = None  # loaded inside run(), so a missing helper fails open

FEATURES = ('r1_score', 'r1_sentence', 'r2_next', 'r2_options', 'r3_process', 'r3_skip', 'r3_point', 'length', 'unexpl')
CODE_FENCE = re.compile(r"```.*?```", re.S)


def log_line(record):
    """Purpose: append one JSON line to the reply log, private to the owner.
    Usage: log_line({...}); never include reply text or names.
    Gotchas: best effort. Any error is ignored, so a log failure never causes a block.
    Opens with O_NONBLOCK so a stuck file cannot hang the hook."""
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        data = (json.dumps(record, allow_nan=False) + '\n').encode()
        fd = os.open(LOG_FILE, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NONBLOCK, 0o600)
        try:
            os.write(fd, data)
        finally:
            os.close(fd)
        os.chmod(LOG_FILE, 0o600)
    except Exception:
        pass


def on_alarm(signum, frame):
    """Purpose: hard time limit. Usage: signal.signal(SIGALRM, on_alarm).
    Gotchas: calls nothing that can block (no log, no file work), prints nothing, exits 0 at once."""
    os._exit(0)


def num(v, lo, hi):
    """Purpose: check a number is real, finite and inside lo..hi. Usage: num(v, 0, 1).
    Gotchas: a bool is not a number here. Returns None (falsy) on a huge or odd value instead of raising."""
    try:
        return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and lo <= v <= hi
    except (OverflowError, TypeError, ValueError):
        return None


def policy_ok(p):
    """Purpose: check the policy file before use. Usage: policy_ok(policy) -> bool.
    Gotchas: the 9 feature keys must match exactly; every mean, sd and weight is finite and sd > 0."""
    try:
        feats = p['features']
        if set(feats) != set(FEATURES):
            return False
        for f in feats.values():
            if not (num(f['mean'], -math.inf, math.inf) and num(f['weight'], -math.inf, math.inf)
                    and num(f['sd'], -math.inf, math.inf) and f['sd'] > 0):
                return False
        ch = p['choice']
        for k in ('recommend_words', 'big_picture_words', 'rating_words'):
            if not (isinstance(ch[k], list) and ch[k] and all(isinstance(w, str) and w for w in ch[k])):
                return False
        for k in ('table_min_cols', 'table_min_rows', 'cell_min_words', 'tail_chars'):
            if not num(ch[k], 1, 10000):
                return False
        if not (num(ch['rated_cell_share'], 0, 1) and num(ch['has_options_min'], 0, 1) and num(ch['implications_min'], 0, 1)
                and num(ch['max_rewrites'], 1, 2) and isinstance(ch['tail_regex'], str)
                and isinstance(ch['decision_regex'], str)):
            return False
        return num(p['bias'], -math.inf, math.inf) and num(p['limit'], -math.inf, math.inf)
    except (KeyError, TypeError):
        return False


def answers_ok(answers, questions, required=None):
    """Purpose: check one OpenJev reply has every asked question with a valid number.
    Usage: answers_ok(answers, policy['questions_a']) -> bool. required limits the check to the listed question ids
    (set B uses only unexplained_ref; the other questions are sent and logged but not needed).
    Gotchas: noul must be in 0..1, score in 0..3; anything else, including a bool, is invalid."""
    if not isinstance(answers, dict):
        return False
    for qid in (questions if required is None else required):
        q = questions[qid]
        a = answers.get(qid)
        kind = q['type']
        if not isinstance(a, dict) or not num(a.get(kind), 0, 1 if kind == 'noul' else 3):
            return False
    return True


def last_turn(path, last_message, prev_chars):
    """Purpose: read the transcript and return the reply blocks, known terms and last assistant uuid.
    Usage: blocks, known, uuid, turn = last_turn(transcript_path, payload['last_assistant_message'], policy['known_prev_chars']).
    Gotchas: sidechain, meta, compact and API-error rows and tool_result rows are ignored. A typed row that starts
    with '<', 'Caveat:' or '[Request interrupted' is not an owner message (same as mine4.py).
    last_assistant_message is added when no block equals it, because the transcript can lag the Stop event.
    A meta user row starting 'Stop hook feedback' (a block) restarts the reply blocks but not the turn.
    turn = owner message count plus a hash of the last owner message; it keys the rewrite counter."""
    owners, cur, prev, uuid = [], [], [], None
    feedback = 'Stop hook feedback'
    with open(path, encoding='utf-8', errors='ignore') as fh:
        for line in fh:
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if not isinstance(row, dict):
                continue
            if row.get('type') == 'user' and row.get('isMeta') and not row.get('isSidechain'):
                c = (row.get('message') or {}).get('content')
                c = c if isinstance(c, str) else ' '.join(b.get('text', '') for b in (c or []) if isinstance(b, dict) and isinstance(b.get('text'), str))
                if c.lstrip().startswith(feedback):
                    cur = []  # a Stop hook sent the reply back: score only the rewrite that follows
                continue
            if any(row.get(k) for k in ('isSidechain', 'isMeta', 'isCompactSummary', 'isApiErrorMessage')):
                continue
            content = (row.get('message') or {}).get('content')
            blocks = [{'type': 'text', 'text': content}] if isinstance(content, str) else (content if isinstance(content, list) else [])
            if row.get('type') not in ('user', 'assistant') or any(isinstance(b, dict) and b.get('type') == 'tool_result' for b in blocks):
                continue
            texts = [b['text'] for b in blocks if isinstance(b, dict) and b.get('type') == 'text' and isinstance(b.get('text'), str)]
            if row.get('type') == 'user':
                s = '\n'.join(texts).strip()
                if s and not s.startswith(('<', 'Caveat:', '[Request interrupted')):
                    owners.append(s)
                    prev, cur = cur, []
            elif row.get('type') == 'assistant':
                uuid = row.get('uuid')
                cur.extend(t for t in texts if t.strip())
    if isinstance(last_message, str) and last_message.strip() and not any(b.strip() == last_message.strip() for b in cur):
        cur.append(last_message)
    known = ('\n'.join(owners) + '\n' + ('\n\n'.join(prev))[-prev_chars:]).lower()
    turn = '%d:%s' % (len(owners), hashlib.sha256((owners[-1] if owners else '').encode()).hexdigest()[:16])
    return cur, known, uuid, turn


def starts_with(line, word):
    """Purpose: does a line start with word, after bullets, numbers and bold marks? Usage: starts_with(line, 'Good:').
    Gotchas: case-insensitive. Markers are -, *, + or N. / N) then optional ** or __."""
    return re.match(r'\s*(?:(?:[-*+]|\d+[.)])\s*)*(?:\*\*|__)?' + re.escape(word), line, re.I) is not None


SEPARATOR = re.compile(r'\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)*\|?\s*')


def table_rows(lines, i):
    """Purpose: read the body rows of the markdown table whose header is lines[i] and separator lines[i + 1].
    Usage: rows = table_rows(lines, i) -> list of rows, each a list of cell strings (outer pipes dropped).
    Gotchas: the body ends at the first line without a pipe."""
    rows = []
    for l in lines[i + 2:]:
        if '|' not in l:
            break
        rows.append([c.strip() for c in l.strip().strip('|').split('|')])
    return rows


def structure_ok(text, choice):
    """Purpose: does a choice reply follow the decision template (rules/writing-style.md section 5c)?
    Usage: structure_ok(text, policy['choice']) -> bool.
    Gotchas: needs a recommendation line, a big-picture line, and one markdown table with at least
    table_min_cols columns and table_min_rows body rows. At least rated_cell_share of the non-label cells
    must start with a rating word or a number and hold at least cell_min_words words. Fenced code is removed first."""
    lines = CODE_FENCE.sub(' ', text).split('\n')
    if not any(starts_with(l, w) for l in lines for w in choice['recommend_words']):
        return False
    if not any(starts_with(l, w) for l in lines for w in choice['big_picture_words']):
        return False
    rating = re.compile(r'[*_`\s]*(?:(?:' + '|'.join(re.escape(w) for w in choice['rating_words']) + r')\b|[~<>$]?\d)', re.I)
    for i, (l, nxt) in enumerate(zip(lines, lines[1:])):
        if '|' not in l or not SEPARATOR.fullmatch(nxt):
            continue
        rows = table_rows(lines, i)
        width = len(l.strip().strip('|').split('|'))
        if width < choice['table_min_cols'] or len(rows) < choice['table_min_rows']:
            continue
        body = [c for r in rows for c in r[1:] if c]
        rated = [c for c in body if rating.match(c) and len(c.split()) >= choice['cell_min_words']]
        if body and len(rated) >= choice['rated_cell_share'] * len(body):
            return True
    return False


def score_reply(text, a, b, policy):
    """Purpose: turn the two answer sets and the reply text into features, score and choice flags. No network.
    Usage: r = score_reply(text, answers_a, answers_b, policy); r['score'], r['score_block'], r['choice_block'].
    Gotchas: weights are used exactly as stored (some are negative). Callers must check answers_ok first.
    The fixture check calls this directly."""
    def noul(ans, q):
        """Purpose: read one noul number. Usage: noul(a, 'has_options').
        Gotchas: answers_ok has already checked the key exists."""
        return ans[q]['noul']
    v = {
        'r1_score': (3 - a['zero_context_plain']['score']) / 3,
        'r1_sentence': 1 - noul(a, 'every_sentence_plain'),
        'r2_next': 1 - noul(a, 'next_step_clear'),
        'r2_options': noul(a, 'has_options') * (1 - noul(a, 'options_implications')),
        'r3_process': noul(a, 'process_not_results'),
        'r3_skip': a['skippable_share']['score'] / 3,
        'r3_point': 1 - noul(a, 'point_first'),
        'length': math.log(len(text)),
        'unexpl': noul(b, 'unexplained_ref'),
    }
    score = policy['bias'] + sum(policy['features'][k]['weight'] * (v[k] - policy['features'][k]['mean']) / policy['features'][k]['sd']
                                 for k in FEATURES)
    ch = policy['choice']
    tail = text[-ch['tail_chars']:]
    asked = noul(a, 'has_options') >= ch['has_options_min'] and '?' in tail and re.search(ch['tail_regex'], tail, re.I) is not None
    words = re.search(ch['decision_regex'], CODE_FENCE.sub(' ', text), re.I) is not None  # whole reply, no fences, no has_options or '?'
    detected = asked or words
    ok = structure_ok(text, ch)
    shallow = ok and noul(a, 'options_implications') < ch['implications_min']
    return {'features': v, 'score': score, 'score_block': score > policy['limit'], 'choice_detected': detected,
            'choice_trigger': 'ask' if asked else 'decision_words' if words else 'none',
            'structure_ok': ok, 'shallow': shallow, 'choice_block': detected and (not ok or shallow)}


def ask_both(text, policy):
    """Purpose: run the two OpenJev requests on two daemon threads and wait at most deadline_s in total.
    Usage: (a, ms_a), (b, ms_b) = ask_both(text, policy); an unfinished request gives (None, None).
    Gotchas: daemon threads are never joined at exit; the caller ends with os._exit(0)."""
    message = clarity_jev.redact(text)[0][:policy['max_chars']]
    out = {}

    def run(key, reader, questions):
        """Purpose: one request on one thread. Usage: Thread(target=run, args=('a', reader, questions)).
        Gotchas: stores (answers, ms) in out[key]; post_body never raises."""
        body = {'model': policy['model'], 'state': {'reader': reader, 'message': message}, 'questions': questions}
        out[key] = clarity_jev.post_body(body, deadline=policy['deadline_s'])

    threads = [threading.Thread(target=run, args=('a', policy['reader_zero_context'], policy['questions_a']), daemon=True),
               threading.Thread(target=run, args=('b', policy['reader_owner'], policy['questions_b']), daemon=True)]
    end = time.monotonic() + policy['deadline_s']
    for t in threads:
        t.start()
    for t in threads:
        t.join(max(0.0, end - time.monotonic()))
    return out.get('a', (None, None)), out.get('b', (None, None))


def block_reason(text, r, names, policy):
    """Purpose: build the rewrite message for the model. Usage: reason = block_reason(text, result, names, policy).
    Gotchas: at most 8 lines. Names are redacted, one line each, cut to 40 chars, at most message.max_names."""
    f = r['features']
    rule1 = 'Rule 1: make every sentence plain English an 18-year-old with zero context understands.'
    lines = ['Rewrite your last reply for the owner. Keep every fact; fix only how it reads.']
    if r['score_block']:
        extra = []
        if f['r1_sentence'] > 0.5:
            extra.append(rule1)
        if names:
            shown = [clarity_jev.redact(n)[0].replace('\n', ' ')[:40] for n in names][:policy['message']['max_names']]
            extra.append('Explain in plain words or remove: ' + ', '.join(shown) + '.')
        if f['r3_skip'] >= 0.5 or f['r3_process'] > 0.5:
            extra.append('Rule 3: cut process detail and background the owner did not ask for.')
        if f['r3_point'] > 0.5:
            extra.append('Put the main result or answer in the first sentence.')
        if len(text.split()) > policy['message']['word_limit']:
            extra.append('Aim for %d words or fewer; put long detail in a file and link it.' % policy['message']['word_limit'])
        lines += extra or [rule1]
    if r['choice_block'] and not r['structure_ok']:
        lines.append('Rule 2: this asks the owner to choose. Follow the decision principles in ~/.claude/rules/writing-style.md '
                     'section 5c: recommendation first with reasons; a markdown table with one row per real option, '
                     'one column per dimension that decides this choice (at most 4) and a last Recommend column '
                     '(Yes/No: why), each cell a rating then its short consequence for the project; '
                     'then a Big picture: line on what the choice means overall and what happens if it is wrong.')
    elif r['choice_block']:
        lines.append('Rule 2: the table is there, but the consequences are generic. In each cell say what the option '
                     'means for this project: who is affected, by how much, what it costs, what could go wrong. '
                     'Make the Big picture line say what happens if the choice is wrong.')
    if r['choice_block'] and r['choice_trigger'] == 'decision_words':
        lines.append('List each decision as a choice with options, a recommendation, and the gain and cost of each option.')
    return '\n'.join(lines)


def turns_path(session):
    """Purpose: the counter file for one session. Usage: path = turns_path(sid).
    Gotchas: one file per session, so two sessions never overwrite each other's counts."""
    return os.path.join(TURNS_DIR, hashlib.sha256(session.encode()).hexdigest()[:24] + '.json')


def gate_blocks(session, turn):
    """Purpose: how many times this gate already blocked in this owner turn. Usage: n = gate_blocks(sid, turn).
    Gotchas: returns None when the counter file cannot be read; callers then allow no extra rewrite."""
    try:
        with open(turns_path(session), encoding='utf-8') as fh:
            e = json.load(fh)
    except FileNotFoundError:
        return 0
    except Exception:
        return None
    if not isinstance(e, dict) or e.get('turn') != turn:
        return 0
    return e['blocks'] if isinstance(e.get('blocks'), int) and not isinstance(e.get('blocks'), bool) else None


def note_block(session, turn, n):
    """Purpose: record that the gate blocked n times in this owner turn. Usage: ok = note_block(sid, turn, 2).
    Gotchas: returns True only when the file was written. Callers block a second time only after a True,
    so a failed write can never loop. Unique temp name, then atomic replace."""
    try:
        os.makedirs(TURNS_DIR, exist_ok=True)
        path = turns_path(session)
        tmp = '%s.%d.tmp' % (path, os.getpid())
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NONBLOCK, 0o600)
        with os.fdopen(fd, 'w', encoding='utf-8') as fh:
            json.dump({'turn': turn, 'blocks': n, 'time': round(time.time())}, fh)
        os.replace(tmp, path)
        return True
    except Exception:
        return False


def claim_round2(session, turn):
    """Purpose: claim the one extra rewrite for this owner turn. Usage: if claim_round2(sid, turn): block.
    Gotchas: O_CREAT | O_EXCL makes the claim atomic, so two overlapping runs cannot both win.
    Returns False on any error, so a failure never allows a block."""
    try:
        os.makedirs(TURNS_DIR, exist_ok=True)
        mark = turns_path(session) + '.' + hashlib.sha256(turn.encode()).hexdigest()[:16] + '.r2'
        os.close(os.open(mark, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NONBLOCK, 0o600))
        return True
    except Exception:
        return False


def conf_of(answers, questions):
    """Purpose: keep only numbers from an answer set for the log. Usage: conf_of(answers_a).
    Gotchas: only the question ids in the policy; numbers only; no text, no legends."""
    out = {}
    for q in questions:
        a = (answers or {}).get(q)
        if isinstance(a, dict):
            out[q] = {k: a.get(k) for k in ('noul', 'score', 'confidence') if num(a.get(k), -math.inf, math.inf)}
    return out


def run(raw, rec):
    """Purpose: do the whole Stop hook job for one payload. Usage: reason = run(stdin_text, rec); returns the block reason or None. rec is filled in place.
    Gotchas: does not log; main() prints the decision first, then logs. Never raises."""
    t0 = time.monotonic()
    global clarity_jev, clarity_names
    try:
        sys.path.insert(0, GOVERNANCE)
        import clarity_jev as _jev
        import clarity_names as _names
        clarity_jev, clarity_names = _jev, _names
        payload = json.loads(raw)
        rec['session_id'] = payload.get('session_id')
        active = bool(payload.get('stop_hook_active'))
        mode = 'log' if os.environ.get('HARNESS_REPLY_GATE') == 'log' else 'block'
        rec.update(mode=mode, stop_hook_active=active, blocked=False, block_reasons=[], skipped=None, error=None)
        policy = json.load(open(POLICY_FILE))
        rec['policy'] = policy.get('version')
        if not policy_ok(policy):
            rec['error'] = 'policy'
            return None
        blocks, known, uuid, turn = last_turn(payload['transcript_path'], payload.get('last_assistant_message'), policy['known_prev_chars'])
        rec['assistant_uuid'] = uuid
        text = '\n\n'.join(blocks[-policy['text_blocks']:])[-policy['text_tail_chars']:]
        rec.update(text_hash=hashlib.sha256(text.encode()).hexdigest(), chars=len(text), words=len(text.split()))
        if len(text) < policy['min_chars']:
            rec['skipped'] = 'short'
            return None
        (a, ms_a), (b, ms_b) = ask_both(text, policy)
        rec.update(ms_a=ms_a, ms_b=ms_b)
        if not (answers_ok(a, policy['questions_a']) and answers_ok(b, policy['questions_b'], ('unexplained_ref',))):
            rec['error'] = 'invalid_answers'
            return None
        r = score_reply(text, a, b, policy)
        names = [n for n in clarity_names.new_names(clarity_jev.redact(text)[0], known) if '[SECRET]' not in n]
        reason = None
        sid = str(rec.get('session_id'))
        if mode == 'block' and not active and (r['score_block'] or r['choice_block']):
            round_no = 1  # first rewrite: shared with the other Stop hooks through stop_hook_active
        elif mode == 'block' and active and r['choice_block'] and gate_blocks(sid, turn) == 1 \
                and policy['choice']['max_rewrites'] >= 2:
            round_no = 2  # one extra rewrite, only for a choice reply that is still missing the table or still shallow
            r = dict(r, score_block=False)
        else:
            round_no = 0
        if round_no == 2 and not (claim_round2(sid, turn) and note_block(sid, turn, 2)):
            round_no = 0  # the extra rewrite needs an atomic claim and a saved count first, so it can never repeat
        elif round_no == 1:
            note_block(sid, turn, 1)  # best effort: a failed write only means no extra rewrite later
        if round_no:
            reason = block_reason(text, r, names, policy)
            rec.update(blocked=True, rewrite_round=round_no,
                       block_reasons=[c for c, on in (('score', r['score_block']), ('choice', r['choice_block'])) if on])
        try:  # log-only fields: an error here must never change the decision
            rec.update(answers_a=conf_of(a, policy['questions_a']), answers_b=conf_of(b, policy['questions_b']),
                       features=r['features'], score=r['score'], limit=policy['limit'], choice_detected=r['choice_detected'], choice_trigger=r['choice_trigger'],
                       structure_ok=r['structure_ok'], shallow=r['shallow'], n_new_names=len(names))
        except Exception:
            rec['error'] = 'log_fields'
        return reason
    except Exception as e:  # fail open on every error
        rec['error'] = type(e).__name__
        rec['blocked'] = False
        return None
    finally:
        rec['total_ms'] = round((time.monotonic() - t0) * 1000, 1)


def main():
    """Purpose: Stop hook entry. Usage: python3 -I ~/.claude/scripts/governance/reply-clarity-gate.py < stop.json.
    Gotchas: the alarm is set before stdin is read. Output and exit use os._exit(0) so daemon threads never delay the end."""
    if os.environ.get('HARNESS_REPLY_CLARITY') == '0':
        return
    signal.signal(signal.SIGALRM, on_alarm)
    try:
        alarm_s = int(json.load(open(POLICY_FILE))['alarm_s'])
    except Exception:
        alarm_s = 7
    signal.alarm(alarm_s)
    rec = {'time': round(time.time(), 3), 'session_id': None, 'policy': None, 'blocked': False}
    reason = None
    try:
        reason = run(sys.stdin.read(), rec)
    except BaseException as e:
        rec['error'] = type(e).__name__
    if reason:
        try:
            sys.stdout.write(json.dumps({'decision': 'block', 'reason': reason}, ensure_ascii=False))
            sys.stdout.flush()
        except Exception:
            rec['blocked'] = False
    log_line(rec)


if __name__ == '__main__':
    try:
        main()
    except BaseException:
        pass
    os._exit(0)

#!/usr/bin/env python3
# ABOUTME: PreToolUse hook for AskUserQuestion. Blocks cryptic questions once, so Claude rewrites them.
# ABOUTME: Checks: 3+ undefined codes, a code in a header or option label, a pointer to a rule or section.
# ABOUTME: Regexes are copied from docs/learnings/asking-questions/scripts/hook_checks.py (stands alone).
# ABOUTME: Fails open on any error. Kill switch: HARNESS_QUESTION_GUARD=0. State: QUESTION_GUARD_STATE_DIR.
# ABOUTME: Spec: docs/plans/harness/question-clarity-guard-spec.md (REQ-1 to REQ-7).
import hashlib, json, os, re, signal, sys, time

CODE = re.compile(r'(?<![\w$/.#-])(?:[A-Z]{1,4}-?\d{1,3}[a-z]?|T-[A-Z][A-Z0-9]+(?:-\d+[a-z]?)?)(?![\w/.-])')
ITEM = re.compile(r'\b(?:[Ii]tems?|[Ff]ix(?:es)?|[Cc]uts?|[Ss]tages?|[Aa]rms?|[Ll]anes?|[Pp]hases?|[Rr]ule|[Oo]ption|[Vv]ersion|[Cc]heck(?:list)? item)\s+\(?[A-Z0-9]{1,3}[a-z]?\)?(?![\w%$])')
KNOWN = {'Q1', 'Q2', 'Q3', 'Q4', 'H1', 'H2', 'US', 'UK', 'AI', 'PR', 'PRs', 'MVP', 'MB', 'GB', 'KB'}
DEFINED_AFTER = re.compile(r'^\s*(?:\((?:the|a|an|one|our|its|your)\b|,\s*(?:the|a|an)\b|\s+means\b|\s*=\s)')
POINTER = re.compile(
    r"(?:\bas in the table\b|\bin the table\b|§\s?\d|\beng-(?:design|plan)[\w.-]*\s+(?:§|D?\d)"
    r"|\byour (?:\d{1,2}-\d{1,2} |[\d-]{8,}\s)rule\b|\byour rule \d|\bper your rule\b"
    r"|\b(?:three|two|original|earlier|old) (?:original )?options\b|\bagreed version\b|\bthe (?:June|July) mistake\b)")
RUN_ID = r'\b[a-z]+\d+[a-z]*-[a-z]*\d+\w*\b|\b[a-z]+(?:-[a-z]+)+-\d+\b'
OPT_LABEL_CODE = re.compile(r'^(?:[A-Z]\d?|O\d|#\d+)\s*[:.)]|' + RUN_ID + '|' + CODE.pattern)
# Provider token patterns, copied from scripts/secret-scan.sh.
SECRET = re.compile(r'ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{22,}|ATATT[A-Za-z0-9_=.-]{20,}|sk-(?:proj|ant|svcacct)?-?[A-Za-z0-9_-]{24,}|AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|glpat-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{35}')
LINK_WINDOW = 600          # seconds: a call this soon after a block is the next attempt
KEEP_DAYS = 30
SCAN_CAP = 4000            # characters scanned per field, so regex work stays bounded
MAX_ITEMS = 20             # questions, and options per question, that are scanned
TIME_LIMIT = 3             # seconds: the hook allows the call after this (settings timeout is 5)

def cap(v):
    return str(v or '')[:SCAN_CAP]

def scan(qs):
    """Purpose: copy the questions with every text field cut to SCAN_CAP characters.
    Usage: scan(questions) -> list of dicts.
    Gotchas: also keeps only the first MAX_ITEMS questions and options."""
    return [{'header': cap(q.get('header')), 'question': cap(q.get('question')),
             'options': [{'label': cap(o.get('label')), 'description': cap(o.get('description'))}
                         for o in (q.get('options') if isinstance(q.get('options'), list) else [])[:MAX_ITEMS]
                         if isinstance(o, dict)]} for q in qs[:MAX_ITEMS]]

def text_of(q):
    """Purpose: join one question's text with its option labels and descriptions.
    Usage: text_of(question_dict) -> str.
    Gotchas: the header is left out; chk_header checks it."""
    parts = [q.get('question', '')]
    for o in q.get('options', []):
        parts += [o.get('label', ''), o.get('description', '')]
    return '\n'.join(str(p or '') for p in parts)

def undefined_codes(qs):
    """Purpose: list the distinct short codes that the call never defines.
    Usage: undefined_codes(questions) -> sorted list.
    Gotchas: a code is defined when it is followed by '(the ...', ', the ...', 'means' or '='."""
    full = '\n'.join(text_of(q) for q in qs)
    found, defined = set(), set()
    for m in list(CODE.finditer(full)) + list(ITEM.finditer(full)):
        tok = m.group(0).strip().strip('()')
        if tok in KNOWN:
            continue
        found.add(tok)
        if DEFINED_AFTER.match(full[m.end():m.end() + 12]):
            defined.add(tok)
    return sorted(found - defined)

def chk_codes(qs, n=3):
    """Purpose: flag a call with n or more undefined codes (B4, R18, item 10).
    Usage: chk_codes(questions, n=3).
    Gotchas: the hook uses 3, not the reference default of 2 (2 blocks one clear call)."""
    c = undefined_codes(qs)
    return [f'undefined codes: {", ".join(c[:6])}'] if len(c) >= n else []

def chk_header(qs):
    """Purpose: flag a header chip that is or holds a code ('D1 retry', 'T4 cuts').
    Usage: chk_header(questions) -> list of findings.
    Gotchas: copied as written in the reference, including its and/or precedence."""
    return [f'header is a code: {q.get("header")}' for q in qs
            if CODE.search(q.get('header', '') or '') or ITEM.search(q.get('header', '') or '')
            and (q.get('header', '') or '') not in KNOWN]

def chk_option_label(qs):
    """Purpose: flag option labels that lead with or hold a code ('O4: planned run').
    Usage: chk_option_label(questions) -> list of findings.
    Gotchas: a dollar cap such as 'Cap at $50' does not match."""
    out = []
    for q in qs:
        for o in q.get('options', []):
            lab = o.get('label', '') or ''
            m = OPT_LABEL_CODE.search(lab)
            if m and m.group(0).strip() not in KNOWN:
                out.append(f'option label holds a code: {lab}')
    return out

def chk_pointer(qs):
    """Purpose: flag text that points at something the owner must go and read.
    Usage: chk_pointer(questions) -> list of findings.
    Gotchas: only bare pointers match; 'You said X' with X spelled out is fine."""
    return [f'pointer: {m.group(0)}' for q in qs for m in POINTER.finditer(text_of(q))]

def find_problems(qs):
    """Purpose: the block rule: header code, label code, 3+ undefined codes, or a pointer.
    Usage: find_problems(questions) -> list of finding strings (empty = pass).
    Gotchas: the four checks must stay in step with hook_checks.py (COMBINED+pointer)."""
    return chk_header(qs) + chk_option_label(qs) + chk_codes(qs, 3) + chk_pointer(qs)

def redact(s):
    """Purpose: replace token-like strings with [REDACTED] before text is logged.
    Usage: redact(str) -> str.
    Gotchas: patterns come from scripts/secret-scan.sh; add new providers in both places."""
    return SECRET.sub('[REDACTED]', s)

def state_dir():
    """Purpose: return the state folder for markers and the log.
    Usage: state_dir() -> path.
    Gotchas: QUESTION_GUARD_STATE_DIR overrides the default, so checks avoid the real folder."""
    return os.environ.get('QUESTION_GUARD_STATE_DIR') or os.path.expanduser('~/.claude/state/question-clarity')

def read_log(path):
    """Purpose: read the log lines that parse as JSON.
    Usage: read_log(path) -> list of dicts (empty if the file is missing).
    Gotchas: a broken line is skipped, never fatal."""
    rows = []
    try:
        for line in open(path):
            try:
                rows.append(json.loads(line))
            except ValueError:
                pass
    except OSError:
        pass
    return rows

def write_log(path, entry):
    """Purpose: append one entry, drop rows older than 30 days, keep file mode 600.
    Usage: write_log(path, entry_dict).
    Gotchas: rewrites the file through a temp file; two writers at once can lose a line (accepted)."""
    keep = [r for r in read_log(path) if r.get('ts', 0) >= entry['ts'] - KEEP_DAYS * 86400]
    keep.append(entry)
    tmp = path + '.tmp'
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as f:
        for r in keep:
            f.write(json.dumps(r, ensure_ascii=False) + '\n')
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)

def reason_text(findings):
    """Purpose: build the deny message that Claude reads.
    Usage: reason_text(findings) -> str.
    Gotchas: keep it plain; it must say that an unchanged resend goes through."""
    lines = ['This question is hard to read for someone with no context. Rewrite it and ask again.', '', 'Found:']
    uniq = list(dict.fromkeys(findings))
    lines += [f'- {f}' for f in uniq[:15]]
    if len(uniq) > 15:
        lines.append(f'- and {len(uniq) - 15} more')
    lines += ['',
        'Template:',
        '  Question: the goal in one sentence, what is true now in plain words, then the choice. Say why the owner must decide if it is not obvious.',
        '  Header: 2-3 plain words. No codes.',
        '  Option label: a plain verb phrase, 2-6 words. No codes, no letters as names.',
        '  Option description: what happens and what changes for the goal. Good: the main benefit. Bad: the main cost or risk.',
        '',
        'Checklist: remove or define every code and made-up name at first use; put the facts in the question instead of pointing at a file, rule number or report; one decision per question.',
        'If the code names are real and needed, send the same question again unchanged. It will go through.',
        'If two rewrites are blocked (by this check or the AI grader), resend with metadata {"source": "clarity-retry"}. The owner never sees it, and both checks let it through.']
    return '\n'.join(lines)

def retry_earned(transcript_path, need=2):
    """Purpose: true when the last `need` AskUserQuestion results in this chat were all blocks.
    Usage: retry_earned(payload.get('transcript_path')) -> bool.
    Gotchas: reads only the last 4 MB of the log; an unreadable log means 'not earned', so the
    tag can never skip the checks without proof that a real question got stuck."""
    try:
        with open(transcript_path, 'rb') as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 4_000_000))
            lines = f.read().decode('utf-8', 'ignore').splitlines()
    except Exception:
        return False
    ask_ids, results = set(), []
    for line in lines:
        try:
            content = json.loads(line).get('message', {}).get('content')
        except Exception:
            continue
        if not isinstance(content, list):
            continue
        for x in content:
            if not isinstance(x, dict):
                continue
            if x.get('type') == 'tool_use' and x.get('name') == 'AskUserQuestion':
                ask_ids.add(x.get('id'))
            elif x.get('type') == 'tool_result' and x.get('tool_use_id') in ask_ids:
                results.append(bool(x.get('is_error')))
    return len(results) >= need and all(results[-need:])

def decide(payload):
    """Purpose: run the guard on one payload; return the deny JSON dict or None to allow.
    Usage: decide(payload_dict).
    Gotchas: writes the marker and the log; log errors never change the decision."""
    if payload.get('tool_name') not in (None, 'AskUserQuestion'):
        return None
    qs = (payload.get('tool_input') or {}).get('questions')
    if not isinstance(qs, list) or not qs or not all(isinstance(q, dict) for q in qs):
        sys.stderr.write('question-clarity-guard: allowed, payload has no valid questions list\n')
        return None
    sid = str(payload.get('session_id') or 'nosession')
    h = hashlib.sha256(json.dumps(qs, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]
    sdir = state_dir()
    marker = os.path.join(sdir, 'seen', hashlib.sha256(sid.encode()).hexdigest()[:16] + '-' + h)
    # Escape hatch: after two blocked rewrites Claude sets the hidden metadata.source to
    # 'clarity-retry'. The owner never sees metadata. Allow and log, so no question is stuck.
    tagged = ((payload.get('tool_input') or {}).get('metadata') or {}).get('source') == 'clarity-retry'
    retry = tagged and retry_earned(payload.get('transcript_path') or '')
    if retry:
        findings = []
    elif tagged:
        findings = ['retry tag not earned: it works only after the last 2 tries of this question were blocked. Rewrite the question in plain words instead']
    else:
        findings = find_problems(scan(qs))
    try:
        os.makedirs(os.path.join(sdir, 'seen'), mode=0o700, exist_ok=True)
        if findings:
            try:
                os.close(os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600))
            except FileExistsError:
                if not tagged:  # an unearned tag never rides the unchanged-resend pass
                    findings = []
            seen = not findings
        else:
            seen = os.path.exists(marker)
    except Exception as e:
        sys.stderr.write(f'question-clarity-guard: allowed, state folder unusable: {e}\n')
        return None
    verdict = 'block' if findings else ('pass-retry' if retry else ('pass-resend' if seen else 'pass'))
    try:
        logp = os.path.join(sdir, 'log.jsonl')
        now = time.time()
        attempt = 1
        prev = [r for r in read_log(logp) if r.get('session') == redact(sid) and r.get('verdict') == 'block'
                and now - r.get('ts', 0) <= LINK_WINDOW]
        if prev:
            attempt = prev[-1].get('attempt', 1) + 1
        write_log(logp, {'ts': now, 'time': time.strftime('%Y-%m-%dT%H:%M:%S%z'), 'session': redact(sid), 'hash': h,
                         'verdict': verdict, 'findings': [redact(f) for f in findings], 'attempt': attempt,
                         'questions': redact(json.dumps(qs, ensure_ascii=False))})
    except Exception as e:
        sys.stderr.write(f'question-clarity-guard: log failed: {e}\n')
    if not findings:
        return None
    return {'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny',
                                   'permissionDecisionReason': reason_text(findings)}}

def main():
    """Purpose: hook entry. Read stdin JSON, print deny JSON on a finding, always exit 0.
    Usage: python3 -I question-clarity-guard.py < payload.json.
    Gotchas: any error allows the call (this is a style gate); HARNESS_QUESTION_GUARD=0 turns it off."""
    if os.environ.get('HARNESS_QUESTION_GUARD') == '0':
        return
    def give_up(*_):
        sys.stderr.write('question-clarity-guard: allowed, time limit reached\n')
        os._exit(0)
    signal.signal(signal.SIGALRM, give_up)
    signal.alarm(TIME_LIMIT)
    try:
        out = decide(json.load(sys.stdin))
        if out:
            print(json.dumps(out))
    except Exception as e:
        sys.stderr.write(f'question-clarity-guard: allowed after error: {e}\n')

if __name__ == '__main__':
    main()
    sys.exit(0)

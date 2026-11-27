# ABOUTME: Log-only Stop hook that scores the finished assistant turn with OpenJev.
# ABOUTME: Reads transcript_path and session_id from stdin JSON; never blocks a reply.
# ABOUTME: The parent exits quietly after forking; a detached child does all scoring.
# ABOUTME: One 10 second alarm bounds the child; any error exits quietly (fail open).
# ABOUTME: Logs scores and identifiers, never reply text; HARNESS_REPLY_CLARITY=0 disables it.
import os
import signal
import sys

RULES_FILE = os.path.expanduser('~/.claude/policy/clarity-tests-reply-log.json')
LOG_FILE = os.path.expanduser('~/.claude/state/clarity/reply-log.jsonl')
GOVERNANCE = os.path.expanduser('~/.claude/scripts/governance')


def last_turn(path):
    """Purpose: collect assistant text after the last real user message.
    Usage: text, message_uuid = last_turn(payload['transcript_path']).
    Gotchas: tool results and metadata do not reset the turn; malformed rows fail open."""
    import json

    pieces, message_uuid = [], None
    with open(path, encoding='utf-8') as transcript:
        for line in transcript:
            if not line.strip():
                continue
            row = json.loads(line)
            message = row.get('message') or {}
            content = message.get('content', [])
            role = row.get('type')
            if role == 'user' and not row.get('isMeta') and not row.get('isCompactSummary'):
                texts = [content] if isinstance(content, str) else [
                    str(block.get('text', '')) for block in content
                    if isinstance(block, dict) and block.get('type') == 'text']
                # A row that holds only system reminders is not a real prompt.
                real_user = any(t.strip() and not t.lstrip().startswith('<system-reminder>') for t in texts)
                if real_user:
                    pieces, message_uuid = [], None
            elif role == 'assistant':
                message_uuid = row.get('uuid')
                if isinstance(content, list):
                    pieces.extend(block['text'] for block in content
                                  if isinstance(block, dict) and block.get('type') == 'text'
                                  and isinstance(block.get('text'), str))
    return '\n\n'.join(pieces), message_uuid


def score_reply(raw):
    """Purpose: read the Stop payload, score its turn, and append one private log line.
    Usage: score_reply(stdin_text) in the detached child.
    Gotchas: empty replies skip the call; missing scores produce a null would_block.
    The transcript can lag the Stop event, so last_assistant_message is added when missing."""
    import hashlib
    import json
    import time

    started = time.monotonic()
    sys.path.insert(0, GOVERNANCE)
    import clarity_jev

    payload = json.loads(raw)
    text, message_uuid = last_turn(payload['transcript_path'])
    final = payload.get('last_assistant_message')
    if isinstance(final, str) and final.strip() and not text.rstrip().endswith(final.strip()):
        text = (text + '\n\n' + final) if text.strip() else final
    if not text.strip():
        return
    rules = clarity_jev.load_rules(RULES_FILE)
    answers, metrics = clarity_jev.ask(
        text, clarity_jev.tests_for(rules, 'reply'), hook='reply',
        framing=rules['framing'], max_chars=rules['max_chars'],
        deadline=rules['deadline_s'], rules_version=rules['version'])
    plain = (answers or {}).get('plain_language')
    record = {
        'time': round(time.time(), 3), 'session_id': payload.get('session_id'),
        'assistant_uuid': message_uuid, 'text_hash': hashlib.sha256(text.encode()).hexdigest(),
        'chars': len(text), 'scores': answers if answers is not None else {},
        'would_block': plain < rules['tests']['plain_language']['block_at'] if plain is not None else None,
        'rules_version': rules['version'],
        'total_ms': round((time.monotonic() - started) * 1000, 1),
    }
    if metrics.get('error'):
        record['error'] = metrics['error']
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    fd = os.open(LOG_FILE, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(fd, 'a', encoding='utf-8') as log:
        log.write(json.dumps(record, allow_nan=False) + '\n')


def main():
    """Purpose: exit immediately or fork one quiet child with a hard time limit.
    Usage: python3 -I ~/.claude/scripts/governance/reply-clarity-log.py < stop.json.
    Gotchas: preserve stdin for the payload before replacing all standard descriptors."""
    if os.environ.get('HARNESS_REPLY_CLARITY') == '0':
        return 0
    try:
        pid = os.fork()
    except OSError:
        return 0
    if pid:
        return 0
    try:
        signal.signal(signal.SIGALRM, signal.SIG_DFL)
        signal.alarm(10)
        os.setsid()
        raw = sys.stdin.read()
        # Drop every inherited pipe so the hook runner sees EOF at once.
        null_fd = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 1, 2):
            os.dup2(null_fd, fd)
        os.closerange(3, 4096)
        score_reply(raw)
    except Exception:
        pass
    finally:
        os._exit(0)


if __name__ == '__main__':
    sys.exit(main())

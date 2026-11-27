# ABOUTME: Live check for /fc: resumes a --fork-session copy of a chat in a pseudo-terminal.
# ABOUTME: Runs /fc, a few tool reads, /fc again, then /exit. Usage: python3 -I replay_live_drive.py <session id> <log>.
# Drives an interactive Claude Code in a pseudo-terminal: resume a fork of a chat, run /fc, wait, exit.
import os, pty, sys, time, select, subprocess
sid, log = sys.argv[1], sys.argv[2]
env = {k: v for k, v in os.environ.items() if not k.startswith(('CLAUDE_CODE_USE_BEDROCK', 'AWS_'))}
env.pop('CLAUDECODE', None)
pid, fd = pty.fork()
if pid == 0:
    os.chdir(os.path.expanduser('~/.claude'))
    os.execvpe('claude', ['claude', '--resume', sid, '--fork-session'], env)
out = open(log, 'wb')
def pump(secs):
    end = time.time() + secs
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            try: out.write(os.read(fd, 65536)); out.flush()
            except OSError: return
def send(text, wait):
    os.write(fd, text.encode()); pump(2); os.write(fd, b'\r'); pump(wait)
pump(25)
send('/fc', 70)
send('Use the Bash tool to run these one at a time: cat ~/.claude/plugins/local/fast-compact/src/compact.ts; cat ~/.claude/plugins/local/fast-compact/src/replay.ts; cat ~/.claude/plugins/local/fast-compact/hooks/fast-compact.ts; cat ~/.claude/plugins/local/fast-compact/README.md; cat ~/.claude/plugins/local/fast-compact/bench/RESULTS.md; cat ~/.claude/plugins/local/fast-compact/src/state.ts. Then reply with one word: done.', 150)
send('/fc', 70)
send('/exit', 20)
try: os.kill(pid, 15)
except Exception: pass

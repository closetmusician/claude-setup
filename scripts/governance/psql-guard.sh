#!/usr/bin/env bash
# ABOUTME: PreToolUse hook (Bash): blocks a psql call that has no statement_timeout of 1-300000 ms of its own.
# ABOUTME: Also blocks any timeout of 0 or over 300000, and NOT IN (SELECT ...), which cannot hash and runs for hours.
# ABOUTME: A guardrail, not a sandbox. Never rewrites the command. Exit 2 = deny. Kill switch HARNESS_PSQL_GUARD=0.
# ABOUTME: Fail-open on jq or python errors. Spec: FEAT-PT-DBQ design 10.1 (Q-30). Written 2026-11-23.

set -uo pipefail
trap 'exit 0' ERR

[[ "${HARNESS_PSQL_GUARD:-1}" == "0" ]] && exit 0
command -v jq >/dev/null 2>&1 || { echo "psql-guard: jq not found, skipping" >&2; exit 0; }

INPUT="$(cat)"
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || { echo "psql-guard: bad JSON input, skipping" >&2; exit 0; }
[[ "$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')" == "Bash" ]] || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"
[[ "$CMD" == *psql* ]] || exit 0   # fast path: no psql text, nothing to check

# Purpose: find every psql call in the command and print a deny reason if one is unsafe.
# Usage: python3 -c "$CHECK" < command-text   (prints nothing = allow; prints a reason = deny)
# Gotchas: splits on shell operators outside quotes; heredoc bodies are data, used only by the psql
#   call they feed. Sees through env, sudo, xargs, nohup, time, nice, timeout, bash -c, and $(...) or
#   backticks inside double quotes. A timeout counts only where the server applies it: PGOPTIONS, a
#   conninfo options=, or a SET before any other SQL. Not caught: docker exec ... psql, eval, variables.
CHECK='
import re, shlex, sys, os

cmd = sys.stdin.read().replace("\\\n", " ")
# wrapper name -> (short options that take a value, long options that take a value)
WRAPPERS = {"env": (("-u", "-C", "-S"), ("--unset", "--chdir", "--split-string")),
            "sudo": (("-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U", "-r", "-t"),
                     ("--user", "--group", "--host", "--prompt", "--close-from", "--chdir", "--chroot",
                      "--command-timeout", "--other-user", "--role", "--type")),
            "doas": (("-u", "-C"), ()),
            "xargs": (("-I", "-n", "-P", "-L", "-d", "-E", "-s", "-a"),
                      ("--max-args", "--max-procs", "--max-lines", "--delimiter", "--eof", "--max-chars",
                       "--arg-file", "--process-slot-var")),
            "nice": (("-n",), ("--adjustment",)), "nohup": ((), ()), "time": (("-f", "-o"), ("--format", "--output")),
            "command": ((), ()), "exec": (("-a",), ()), "setsid": ((), ()),
            "timeout": (("-s", "-k"), ("--signal", "--kill-after")), "gtimeout": (("-s", "-k"), ("--signal", "--kill-after"))}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
# psql options whose next word is a value, not SQL or a database name
PSQL_VALUE_OPTS = {"-v", "--set", "--variable", "-f", "--file", "-o", "--output", "-U", "--username", "-h", "--host",
                   "-p", "--port", "-P", "--pset", "-L", "--log-file", "-T", "--table-attr", "-F", "--field-separator",
                   "-R", "--record-separator"}
TIMEOUT = re.compile(r"statement[_-]timeout[\"\x27]?\s*(?:=|,|\s+to\s+)\s*[\"\x27]?(\d+)([a-z]*)", re.I)
PGOPT = re.compile(r"(?:-c\s*|--)statement[_-]timeout\s*=\s*[\"\x27]?(\d+)([a-z]*)", re.I)
SQL_SET = re.compile(r"^SET\s+(?:SESSION\s+)?statement_timeout\s*(?:=|TO)\s*[\"\x27]?(\d+)([a-z]*)[\"\x27]?$", re.I)
SQL_SETCONF = re.compile(r"^SELECT\s+set_config\(\s*\x27statement_timeout\x27\s*,\s*\x27(\d+)([a-z]*)\x27\s*,\s*false\s*\)$", re.I)
SQL_RESET = re.compile(r"\bRESET\s+(?:statement_timeout|ALL)\b|statement_timeout\s*(?:=|TO)\s*DEFAULT\b", re.I)
SUBS = []    # command substitutions found inside double quotes; walked after the main text

def close_paren(text, k):
    """Return the index of the ) that closes a $( opened just before text[k]."""
    depth, q = 1, None
    while k < len(text):
        c = text[k]
        if q:
            if c == "\\" and q == "\"":
                k += 1
            elif c == q:
                q = None
        elif c in "\"\x27":
            q = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return k
        k += 1
    return len(text)

def split(text):
    """Return [[segment_text, heredoc_body], ...] split on operators outside quotes."""
    segs, pending, q, i = [["", ""]], [], None, 0
    while i < len(text):
        c = text[i]
        if q:
            if q == "\"" and text.startswith("$(", i):
                j = close_paren(text, i + 2)
                SUBS.append(text[i + 2:j])
                segs[-1][0] += text[i:j + 1]
                i = j + 1
                continue
            if q == "\"" and c == "`":
                j = text.find("`", i + 1)
                j = len(text) if j < 0 else j
                SUBS.append(text[i + 1:j])
                segs[-1][0] += text[i:j + 1]
                i = j + 1
                continue
            segs[-1][0] += c
            if c == "\\" and q == "\"" and i + 1 < len(text):
                i += 1
                segs[-1][0] += text[i]
            elif c == q:
                q = None
        elif c in "\"\x27":
            q = c
            segs[-1][0] += c
        elif c == "\\" and i + 1 < len(text):
            segs[-1][0] += text[i:i + 2]
            i += 1
        elif c == "#" and (i == 0 or text[i - 1] in " \t\n;&|()"):
            while i + 1 < len(text) and text[i + 1] != "\n":
                i += 1
        elif text.startswith("<<", i) and not text.startswith("<<<", i) and \
                re.match(r"<<-?\s*[\"\x27]?\w+", text[i:]):
            m = re.match(r"<<-?\s*([\"\x27]?)(\w+)\1", text[i:])
            pending.append((segs[-1], m.group(2)))
            i += len(m.group(0)) - 1
        elif c == "\n" and pending:
            lines = text[i + 1:].split("\n")
            used = 0
            for seg, delim in pending:
                body = []
                while used < len(lines) and lines[used].strip() != delim:
                    body.append(lines[used])
                    used += 1
                used += 1
                seg[1] = "\n".join(body)
            i += sum(len(l) + 1 for l in lines[:used])
            pending = []
            segs.append(["", ""])
        elif c in ";&|()`\n":
            segs.append(["", ""])
        else:
            segs[-1][0] += c
        i += 1
    return segs

def words(text):
    try:
        return shlex.split(text)
    except ValueError:
        return text.split()

def strip_sql_comments(s):
    return re.sub(r"--[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", s, flags=re.S))

def is_assign(t, name=r"[A-Za-z_]\w*"):
    return re.match(name + "=", t)

def psql_parts(args):
    """Return (sql_texts, conninfo_texts) from psql args. -Atc style flag groups count as -c."""
    sql, conn, i = [], [], 0
    while i < len(args):
        a = args[i]
        m = re.match(r"-([AtqXxeEabnsSz01wW]*)c(.*)$", a, re.S) if not a.startswith("--") else None
        if a == "--command" or (m and not m.group(2)):
            if i + 1 < len(args):
                sql.append(args[i + 1])
            i += 2
            continue
        if m:
            sql.append(m.group(2))
        elif a.startswith("--command="):
            sql.append(a[len("--command="):])
        elif a in ("-d", "--dbname"):
            conn += args[i + 1:i + 2]
            i += 2
            continue
        elif a.startswith("--dbname="):
            conn.append(a[len("--dbname="):])
        elif a in PSQL_VALUE_OPTS:
            i += 2
            continue
        elif not a.startswith("-"):
            conn.append(a)
        i += 1
    return sql, conn

def sql_timeout(text):
    """Return the timeout match of a SET that runs before any other SQL, or None."""
    text = "\n".join(l for l in strip_sql_comments(text).split("\n") if not l.strip().startswith("\\"))
    for stmt in text.split(";"):
        s = " ".join(stmt.split())
        if not s:
            continue
        m = SQL_SET.match(s) or SQL_SETCONF.match(s)
        if m:
            return m
        if not re.match(r"(?:SET|BEGIN|START\s+TRANSACTION)\b", s, re.I):
            return None
    return None

calls = []   # each: (PGOPTIONS strings that reach psql, psql args, heredoc body)

def walk(text, session):
    for seg, body in split(text):
        toks, env, sess = words(seg), [], session
        while toks and is_assign(toks[0]):
            if toks[0].startswith("PGOPTIONS="):
                env.append(toks[0])
            toks.pop(0)
        if toks and toks[0] in ("export", "declare", "typeset"):
            session += [t for t in toks[1:] if t.startswith("PGOPTIONS=")]
            continue
        if toks and toks[0] == "unset" and "PGOPTIONS" in toks:
            session.clear()
            continue
        while toks and os.path.basename(toks[0]) in WRAPPERS:
            name, i = os.path.basename(toks[0]), 1
            short, long_ = WRAPPERS[name]
            if name == "command" and len(toks) > 1 and toks[1] in ("-v", "-V"):
                toks = []   # lookup only, nothing runs
                break
            if name == "sudo" and not any(t == "-E" or t.startswith("--preserve-env") for t in toks):
                env, sess = [], []   # sudo resets the environment by default
            while i < len(toks):
                t = toks[i]
                if t == "--":
                    i += 1
                    break
                if name == "env" and (t in ("-i", "--ignore-environment", "-") or t == "--unset=PGOPTIONS" or
                                      (t in ("-u", "--unset") and toks[i + 1:i + 2] == ["PGOPTIONS"])):
                    env, sess = [], []
                if is_assign(t) and name in ("env", "sudo"):
                    if t.startswith("PGOPTIONS="):
                        env.append(t)
                elif t.startswith("-"):
                    i += 2 if (t in short or t in long_) else 1
                    continue
                else:
                    break
                i += 1
            if name in ("timeout", "gtimeout"):
                i += 1   # skip the duration
            toks = toks[i:]
        if not toks:
            continue
        name = os.path.basename(toks[0])
        if name == "psql" and set(toks[1:]) & {"--version", "-V", "--help", "-?"}:
            continue   # prints info and exits, no SQL runs
        if name == "psql":
            calls.append((env + sess, toks[1:], body))
        elif name in SHELLS:
            for j, t in enumerate(toks[1:], 1):
                if t.startswith("-") and not t.startswith("--") and "c" in t and j + 1 < len(toks):
                    walk(toks[j + 1], sess + env)
                    break
            else:
                walk(body, sess + env)

walk(cmd, [])
while SUBS:
    walk(SUBS.pop(), [])
if not calls:
    sys.exit(0)
if re.search(r"NOT\s+IN\s*\(\s*SELECT", cmd, re.I):
    print("Use NOT EXISTS (SELECT 1 ... WHERE p.k = t.k). NOT IN over a large subquery cannot hash and runs for hours.")
    sys.exit(3)
for env, args, body in calls:
    sql, conn = psql_parts(args)
    every = [m for s in env + args + [body] for m in TIMEOUT.findall(s)]
    if any(int(n) == 0 or int(n) > 300000 for n, unit in every if not unit) or \
            any(SQL_RESET.search(s) for s in sql + [body]):
        print("statement_timeout of 0, above 300000 ms, or reset found. Every statement_timeout in a psql command must be 1 to 300000 ms.")
        sys.exit(3)
    good = [m for s in env + [c for c in conn if "options=" in c] for m in PGOPT.findall(s)]
    first = sql_timeout(";".join(sql + [body]))
    if first:
        good.append(first.groups())
    if not any(1 <= int(n) <= 300000 for n, unit in good if not unit):
        print("Each psql call needs its own statement_timeout of 1 to 300000 ms. Prefix it: PGOPTIONS=\x27-c statement_timeout=300000\x27 psql ...")
        sys.exit(3)
'

RC=0
REASON="$(printf '%s' "$CMD" | python3 -c "$CHECK")" || RC=$?
[[ "$RC" -eq 3 ]] || exit 0   # 0 = allow; any other code = checker broke, fail open

jq -cn --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 2

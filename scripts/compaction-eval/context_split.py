# ABOUTME: Splits the REAL context window at each past built-in compaction into the parts that fill it.
# ABOUTME: Step 1 fits tokens-per-char for each kind of content from real call-to-call usage growth (trimmed least squares).
# ABOUTME: Step 2 applies those ratios to every point in out/backtest-points.jsonl and leaves the rest as "unattributed".
# ABOUTME: Also measures the real window right after each compaction (first API call after the boundary).
# ABOUTME: Read only. Run: uv run --with numpy python -I context_split.py  (writes out/context-split.json and prints a table).
import json
import os
import re
import statistics as st
from collections import defaultdict

import numpy as np

HOME = os.path.expanduser('~')
HERE = os.path.dirname(os.path.abspath(__file__))
POINTS = os.path.join(HERE, 'out', 'backtest-points.jsonl')
KINDS = ['tool_output', 'tool_input', 'claude_text', 'thinking', 'host_text', 'user_text', 'attachment']
# Attachment records that are bookkeeping for the app, not text the model reads.
BOOKKEEPING = {'prompt_snapshot', 'command_permissions', 'credential_org', 'auto_mode', 'remote_session_change', 'model'}


def read(path):
    """Purpose: load one transcript file as a list of records.
    Usage: read(path). Torn lines (a session still writing) are skipped.
    Gotchas: keeps file order, which the segment logic depends on."""
    out = []
    for line in open(path):
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


def window(usage):
    """Purpose: the size of the context the model read on one API call.
    Usage: window(record['message']['usage']).
    Gotchas: input + cache read + cache write; output tokens are not part of the input window."""
    return (usage.get('input_tokens') or 0) + (usage.get('cache_read_input_tokens') or 0) + (usage.get('cache_creation_input_tokens') or 0)


def is_host(text, rec):
    """Purpose: tell text the app or a hook injected from text the person typed.
    Usage: is_host(text, record).
    Gotchas: meta records and text that opens with a tag (<system-reminder>, <task-notification>...) count as host text."""
    return bool(rec.get('isMeta') or rec.get('isCompactSummary')) or text.lstrip().startswith('<')


def host_label(text, rec):
    """Purpose: name the source of one host text block for the breakdown.
    Usage: host_label(text, record) -> 'skill text', 'other agents', 'compact summary', or 'other host text'.
    Gotchas: 'Another Claude session sent a message' and task notifications both count as messages from other agents."""
    t = text.lstrip()
    if rec.get('isCompactSummary'):
        return 'compact summary'
    if t.startswith('Base directory for this skill'):
        return 'skill text'
    if t.startswith('Another Claude session sent a message') or re.match(r'<(task-notification|agent-message|cross-session-message)', t):
        return 'messages from other agents'
    return 'other host text'


def kinds_of(rec, acc, sub=None):
    """Purpose: add one record's chars, by kind, into acc (and host text by source into sub).
    Usage: kinds_of(record, defaultdict(int), defaultdict(int)).
    Gotchas: thinking counts its readable text plus its signature, because both take window space (fit shows the same rate)."""
    t, m = rec.get('type'), rec.get('message') or {}
    content = m.get('content')
    if t == 'assistant':
        for b in content if isinstance(content, list) else []:
            ty = b.get('type')
            if ty == 'text':
                acc['claude_text'] += len(b.get('text') or '')
            elif ty == 'tool_use':
                acc['tool_input'] += len(json.dumps(b.get('input') or {}))
            elif ty == 'thinking':
                acc['thinking'] += len(b.get('thinking') or '') + len(b.get('signature') or '')
    elif t == 'user':
        items = [content] if isinstance(content, str) else []
        for b in content if isinstance(content, list) else []:
            if b.get('type') == 'text':
                items.append(b.get('text') or '')
            elif b.get('type') == 'tool_result':
                x = b.get('content')
                acc['tool_output'] += len(x) if isinstance(x, str) else sum(len(y.get('text') or '') for y in x or [] if isinstance(y, dict))
        for s in items:
            if is_host(s, rec):
                acc['host_text'] += len(s)
                if sub is not None:
                    sub[host_label(s, rec)] += len(s)
            else:
                acc['user_text'] += len(s)
    elif t == 'attachment':
        a = rec.get('attachment') or {}
        if a.get('type') not in BOOKKEEPING:
            acc['attachment'] += len(json.dumps(a))


def fit(paths):
    """Purpose: tokens per char for each kind, from real growth between consecutive API calls.
    Usage: coef = fit(paths); coef[kind] is tokens per char, coef['step'] is fixed tokens per call.
    Gotchas: big jumps (tool list changes, deferred tool loads) are not content growth, so the worst 10% are dropped 4 times."""
    X, Y = [], []
    for path in paths:
        prev_id, prev_win, acc = None, None, defaultdict(int)
        for r in read(path):
            if r.get('isSidechain'):
                continue
            m = r.get('message') or {}
            if r.get('type') == 'system' and r.get('subtype') == 'compact_boundary':
                prev_id, acc = None, defaultdict(int)
                continue
            if r.get('type') == 'assistant' and m.get('usage') and m.get('id') != prev_id:
                w = window(m['usage'])
                if prev_id and prev_win and w >= prev_win:
                    X.append([acc[k] for k in KINDS] + [1])
                    Y.append(w - prev_win)
                prev_id, prev_win, acc = m.get('id'), w, defaultdict(int)
            kinds_of(r, acc)
    X, Y = np.array(X, float), np.array(Y, float)
    keep = np.ones(len(Y), bool)
    for _ in range(4):
        c, *_ = np.linalg.lstsq(X[keep], Y[keep], rcond=None)
        err = np.abs(Y - X @ c)
        keep = err <= np.quantile(err[keep], 0.9)
    r2 = 1 - ((Y[keep] - X[keep] @ c) ** 2).sum() / ((Y[keep] - Y[keep].mean()) ** 2).sum()
    coef = dict(zip(KINDS + ['step'], c.tolist()))
    return coef, dict(steps=len(Y), kept=int(keep.sum()), r2=round(float(r2), 4))


def main():
    """Purpose: fit the ratios, split each compaction point's window, print the table, write out/context-split.json.
    Usage: run the file. Needs out/backtest-points.jsonl from backtest.ts.
    Gotchas: the start-up block is the measured window of the session's FIRST API call, so it also holds the first prompt."""
    pts = [json.loads(l) for l in open(POINTS)]
    path_of = lambda p: f"{HOME}/.claude/projects/{p['project']}/{p['session']}.jsonl"
    coef, quality = fit(sorted({path_of(p) for p in pts}))
    rows, files = [], {}
    for p in pts:
        R = files.setdefault(path_of(p), read(path_of(p)))
        by = {r['uuid']: r for r in R if r.get('uuid')}
        bounds = [i for i, r in enumerate(R) if r.get('type') == 'system' and r.get('subtype') == 'compact_boundary']
        bi = bounds[p['index']]
        lo = bounds[p['index'] - 1] if p['index'] > 0 else -1
        calls = [i for i, r in enumerate(R) if r.get('type') == 'assistant' and (r.get('message') or {}).get('usage')]
        startup = window(R[calls[0]]['message']['usage'])
        after = next(window(R[i]['message']['usage']) for i in calls if i > bi and not R[i].get('isSidechain'))
        seg = [r for r in R[lo + 1:bi] if not r.get('isSidechain')]
        if p['index'] == 0:
            seg = [r for i, r in enumerate(R[:bi]) if i > calls[0] or r.get('type') != 'attachment']  # start-up attachments sit in the start-up block
            seg = [r for r in seg if not r.get('isSidechain')]
        else:
            have = {r.get('uuid') for r in seg}
            seg += [by[u] for u in R[lo]['compactMetadata'].get('preservedMessages', {}).get('uuids', []) if u in by and u not in have]
        acc, sub = defaultdict(int), defaultdict(int)
        seen_skill = set()
        for r in seg:
            kinds_of(r, acc, sub)
            # A skill text identical to one already loaded in this segment is a pure repeat.
            c = (r.get('message') or {}).get('content')
            if r.get('type') == 'user' and r.get('isMeta') and isinstance(c, (str, list)):
                s = c if isinstance(c, str) else ' '.join(b.get('text') or '' for b in c if isinstance(b, dict))
                if s.startswith('Base directory for this skill'):
                    if s in seen_skill:
                        sub['repeated skill text'] += len(s)
                    seen_skill.add(s)
        n_calls = len({(R[i].get('message') or {}).get('id') for i in calls if lo < i < bi})
        tok = {k: acc[k] * coef[k] for k in KINDS}
        tok['per-call overhead'] = n_calls * coef['step']
        tok['start-up block'] = startup
        tok['unattributed'] = p['preTokens'] - sum(tok.values())
        host_tok = {k: v * coef['host_text'] for k, v in sub.items()}
        fc_freed = (p['fcBeforeChars'] - p['fcAfterChars']) * coef['tool_output']
        rows.append(dict(session=p['session'], index=p['index'], pre=p['preTokens'], after_builtin=after, tokens=tok, host=host_tok, fc_default_freed=fc_freed))
    json.dump(dict(coef=coef, fit=quality, rows=rows), open(os.path.join(HERE, 'out', 'context-split.json'), 'w'), indent=1)

    share = lambda f: (round(st.median(f(r) for r in rows) * 100, 1), round(st.mean(f(r) for r in rows) * 100, 1))
    print(f"fit: {quality}; chars per token: " + ', '.join(f"{k} {1 / coef[k]:.2f}" for k in KINDS) + f"; per call {coef['step']:.1f} tok")
    print(f"points {len(rows)}; median window before {st.median(r['pre'] for r in rows):.0f} tok; median start-up block {st.median(r['tokens']['start-up block'] for r in rows):.0f} tok\n")
    print('| Part of the window at compaction | Median share | Mean share |\n|---|---|---|')
    for k in ['start-up block', 'tool_output', 'tool_input', 'host_text', 'claude_text', 'thinking', 'attachment', 'user_text', 'per-call overhead', 'unattributed']:
        print(f"| {k} | {share(lambda r, k=k: r['tokens'][k] / r['pre'])[0]}% | {share(lambda r, k=k: r['tokens'][k] / r['pre'])[1]}% |")
    print('\nhost text by source (share of whole window):')
    for k in ['skill text', 'repeated skill text', 'messages from other agents', 'compact summary', 'other host text']:
        print(f"  {k}: median {share(lambda r, k=k: r['host'].get(k, 0) / r['pre'])[0]}%, mean {share(lambda r, k=k: r['host'].get(k, 0) / r['pre'])[1]}%")
    print(f"\nmost any compaction can free (window minus start-up block): median {share(lambda r: 1 - r['tokens']['start-up block'] / r['pre'])[0]}%")
    print(f"built-in real freed (first call after vs before): median {share(lambda r: 1 - r['after_builtin'] / r['pre'])[0]}%, mean {share(lambda r: 1 - r['after_builtin'] / r['pre'])[1]}%")
    print(f"/fc default freed, as share of whole window: median {share(lambda r: r['fc_default_freed'] / r['pre'])[0]}%, mean {share(lambda r: r['fc_default_freed'] / r['pre'])[1]}%")


if __name__ == '__main__':
    main()

# ABOUTME: Runs the clarity tests over the labelled set and reports how well each test splits bad from good.
# ABOUTME: Set: ~/.claude/state/clarity/labelled.jsonl (private, git-ignored). Rules: policy/clarity-tests.json.
# ABOUTME: Reports per test: average bad and good, AUC, the limit that blocks no good example, catch rate.
# ABOUTME: Also reports timing (connect, model, total; p50 and p95), tokens and errors. Caches answers per setup.
# ABOUTME: Usage: python3 clarity_eval.py --tag base [--rules F] [--max-chars N] [--split] [--hook reply|question]
import argparse
import concurrent.futures as cf
import hashlib
import json
import os
import re
import statistics
import sys
import time
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clarity_jev as cj  # noqa: E402

STATE = os.path.join(cj.HOME, 'state', 'clarity')
SET_FILE = os.environ.get('CLARITY_SET') or os.path.join(STATE, 'labelled.jsonl')  # env picks the wide set
EVAL_DIR = os.path.join(STATE, 'eval')


def load_set(path=SET_FILE):
    """Purpose: read the labelled examples (one JSON object per line).
    Usage: items = load_set(); each has id, kind (reply|question), label (bad|good|mild), text.
    Gotchas: 'mild' examples are scored and shown, but never used to set a limit."""
    return [json.loads(line) for line in open(path) if line.strip()]


SUFFIX = ('\n\n---\nEnd of the message. Judge it as a smart 18-year-old who has never seen this project and may not ask the writer '
          'anything. Names, ids, codes, files and steps count as unclear unless the message explains them in plain words.')


def prep_texts(text, prep, max_chars):
    """Purpose: turn one reply into the text(s) sent to OpenJev, per the optional --prep flag.
    Usage: prep_texts(t, 'nocode,tail', 4000) -> list of texts; more than one means chunks (worst score wins).
    Gotchas: empty prep returns [text] unchanged (today's behaviour). Steps: nocode, nopath, notable, nolist,
    then one of head (default), tail, headtail, chunks:N (pieces of N chars, split on blank lines)."""
    if not prep:
        return [text]
    steps = prep.split(',')
    if 'nocode' in steps:
        text = re.sub(r'```.*?```', '[code]', text, flags=re.S)
        text = re.sub(r'`[^`\n]+`', '[code]', text)
    if 'notable' in steps:
        text = '\n'.join(l for l in text.split('\n') if not l.lstrip().startswith('|'))
    if 'nopath' in steps:
        text = re.sub(r'(?:~|\.{0,2})?/?(?:[\w.-]+/)+[\w.-]+', '[path]', text)
    if 'nolist' in steps:
        text = re.sub(r'^\s*(?:[-*]|\d+[.)])\s+', '', text, flags=re.M)
    text = text.strip()
    if 'wrap' in steps:  # mark where the message starts and ends
        return ['<message>\n' + text[:max_chars - 40] + '\n</message>']
    if 'suffix' in steps:  # clip to 4000, then add a reminder line; run with --max-chars 4600 so it is not cut
        return [text[:4000] + SUFFIX]
    for st in steps:
        if st == 'tail':
            return [text[-max_chars:]]
        if st == 'headtail' and len(text) > max_chars:
            return [text[:max_chars // 2] + '\n[...]\n' + text[-max_chars // 2:]]
        if st.startswith('chunks:'):
            n, out, cur = int(st[7:]), [], ''
            for para in text.split('\n\n'):
                if cur and len(cur) + len(para) > n:
                    out.append(cur)
                    cur = ''
                cur += ('\n\n' if cur else '') + para
            return (out + [cur])[:6] if cur else out or [text]
    return [text]


def run_one(item, questions, framing, max_chars, deadline, cache, setup=None):
    """Purpose: get the answers for one example, from the cache or from OpenJev.
    Usage: row = run_one(item, qs, framing, 6000, 10, cache).
    Gotchas: the cache key covers the text, the test wording AND ORDER, the framing and the clip length.
    Order matters: OpenJev scores shift by up to 1 point when the same tests come in another order."""
    setup = setup or {}
    key = hashlib.sha256(json.dumps([item['text'], list(questions.items()), framing, max_chars]
                                    + ([setup] if setup else [])).encode()).hexdigest()
    if key in cache:
        return dict(cache[key], cached=True)
    for attempt in range(5):  # the eval retries busy or over-quota answers; the hooks never do
        answers, m = cj.ask(item['text'], questions, hook='eval', framing=framing, max_chars=max_chars,
                            deadline=deadline, log=False, **setup)
        if m.get('error') not in ('http_429', 'http_529', 'http_503', 'TimeoutError'):
            break
        time.sleep(2 * 2 ** attempt)
    m['attempts'] = attempt + 1
    row = {'key': key, 'answers': answers, 'm': m}
    if answers is not None:
        cache[key] = row
    return dict(row, cached=False)


def auc(bad, good, bad_when):
    """Purpose: chance that a random bad example looks worse than a random good one (0.5 = no split).
    Usage: a = auc([0.9, 0.8], [0.1], 'above').
    Gotchas: ties count half. Returns None when a side is empty."""
    if not bad or not good:
        return None
    sign = 1 if bad_when == 'above' else -1
    wins = sum((sign * (b - g) > 0) + 0.5 * (b == g) for b in bad for g in good)
    return wins / (len(bad) * len(good))


def best_limit(bad, good, bad_when, max_false=0):
    """Purpose: find the limit that blocks at most max_false good examples and catches the most bad ones.
    Usage: limit, caught = best_limit(bad, good, 'above', 0).
    Gotchas: the limit sits halfway between neighbour values and is NOT rounded, because rounding can
    move it past a good example. Fit on the same data, so it is optimistic."""
    if not bad or not good:
        return None, 0
    sign = 1 if bad_when == 'above' else -1
    gs = sorted((sign * g for g in good), reverse=True)
    edge = gs[max_false] if max_false < len(gs) else min(sign * b for b in bad) - 1
    caught = [sign * b for b in bad if sign * b > edge]
    if not caught:
        return None, 0
    return sign * (edge + min(caught)) / 2, len(caught)


def pct(vals, p):
    """Purpose: the p-th percentile of a list (nearest rank).
    Usage: pct(times, 95).
    Gotchas: returns None for an empty list."""
    if not vals:
        return None
    s = sorted(vals)
    return s[min(len(s) - 1, int(round(p / 100 * (len(s) - 1))))]


def main():
    """Purpose: run one setup over the labelled set and write a report.
    Usage: see the ABOUTME usage line. Reports go to state/clarity/eval/<tag>.md and .json.
    Gotchas: --split sends one request per test, to measure the cost of batching tests."""
    ap = argparse.ArgumentParser()
    ap.add_argument('--tag', required=True)
    ap.add_argument('--rules', default=cj.RULES_FILE)
    ap.add_argument('--max-chars', type=int)
    ap.add_argument('--hook', choices=['reply', 'question'])
    ap.add_argument('--split', action='store_true')
    ap.add_argument('--workers', type=int, default=8)
    ap.add_argument('--deadline', type=float, default=10.0)
    ap.add_argument('--set', default=SET_FILE, help='labelled set file (default: the strict set)')
    ap.add_argument('--prep', default='', help='optional input prep, see prep_texts (default: none)')
    ap.add_argument('--keep-conf', action='store_true', help='also store the per-test confidence in the JSON file')
    ap.add_argument('--fresh', action='store_true', help='ignore the cache, to measure run-to-run noise')
    a = ap.parse_args()
    rules = cj.load_rules(a.rules)
    max_chars = a.max_chars or rules.get('max_chars', 6000)
    items = [i for i in load_set(a.set) if not a.hook or i['kind'] == a.hook]
    os.makedirs(EVAL_DIR, exist_ok=True)
    cache_file = os.path.join(EVAL_DIR, 'cache.json')
    cache = json.load(open(cache_file)) if os.path.exists(cache_file) and not a.fresh else {}
    jobs = []
    for it in items:
        qs = cj.tests_for(rules, it['kind'])
        groups = [{k: v} for k, v in qs.items()] if a.split else [qs]
        for tx in prep_texts(it['text'], a.prep, max_chars):
            jobs += [(dict(it, text=tx), g) for g in groups]
    rows = []
    with cf.ThreadPoolExecutor(a.workers) as ex:
        setup = {k: rules[k] for k in ('model', 'read_options', 'examples') if rules.get(k)}
        skip = set(rules.get('example_ids', []))  # examples taken from the set are never scored
        def item_setup(it):  # examples may be one list, or one list per kind (reply, question)
            ex_ = setup.get('examples')
            return dict(setup, examples=ex_[it['kind']]) if isinstance(ex_, dict) else setup
        futs = {ex.submit(run_one, it, g, rules['framing'], max_chars, a.deadline, cache, item_setup(it)): it
                for it, g in jobs if it['id'] not in skip}
        for f in cf.as_completed(futs):
            rows.append((futs[f], f.result()))
    if a.fresh:  # keep the stored cache as it was
        return report(a, rules, max_chars, items, rows)
    fd = os.open(cache_file + '.tmp', os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, 'w') as f:
        json.dump(cache, f)
    os.replace(cache_file + '.tmp', cache_file)
    report(a, rules, max_chars, items, rows)


def report(a, rules, max_chars, items, rows):
    """Purpose: compute the split and timing tables and write them as markdown and JSON.
    Usage: called by main().
    Gotchas: timing only counts fresh (not cached) calls."""
    scores = {}
    for it, r in rows:
        for k, v in (r['answers'] or {}).items():
            cur = scores.setdefault(it['id'], {})
            if k in cur:  # several chunks of one reply: the worst score wins
                v = max(cur[k], v) if rules['tests'][k]['bad_when'] == 'above' else min(cur[k], v)
            cur[k] = v
    out = {'tag': a.tag, 'rules_version': rules['version'], 'max_chars': max_chars, 'split': a.split,
           'n_items': len(items), 'tests': {}, 'timing': {}}
    lines = [f"# Clarity eval: {a.tag}", '',
             f"Rules {rules['version']}, clip {max_chars} chars, {'one request per test' if a.split else 'all tests in one request'}.", '',
             '| Hook | Test | Bad avg | Good avg | Mild avg | AUC | Limit (0 good blocked) | Bad caught | Limit (1 good blocked) | Bad caught |',
             '|---|---|---|---|---|---|---|---|---|---|']
    for kind in ('reply', 'question'):
        ks = [i for i in items if i['kind'] == kind]
        if not ks:
            continue
        for tid, t in rules['tests'].items():
            if kind not in t.get('hooks', []):
                continue
            g = {lab: [scores[i['id']][tid] for i in ks if i['label'] == lab and tid in scores.get(i['id'], {})]
                 for lab in ('bad', 'good', 'mild')}
            au = auc(g['bad'], g['good'], t['bad_when'])
            l0, c0 = best_limit(g['bad'], g['good'], t['bad_when'], 0)
            l1, c1 = best_limit(g['bad'], g['good'], t['bad_when'], 1)
            avg = lambda v: round(statistics.mean(v), 2) if v else None  # noqa: E731
            r3 = lambda v: None if v is None else round(v, 3)  # noqa: E731  display only
            out['tests'][f'{kind}:{tid}'] = {'bad': avg(g['bad']), 'good': avg(g['good']), 'mild': avg(g['mild']),
                                             'auc': au and round(au, 3), 'limit0': l0, 'caught0': c0, 'limit1': l1,
                                             'caught1': c1, 'n_bad': len(g['bad']), 'n_good': len(g['good'])}
            lines.append(f"| {kind} | {tid} | {avg(g['bad'])} | {avg(g['good'])} | {avg(g['mild'])} | "
                         f"{au and round(au, 2)} | {r3(l0)} | {c0} of {len(g['bad'])} | {r3(l1)} | {c1} of {len(g['bad'])} |")
    conf = {it['id']: r['m'].get('confidence') for it, r in rows} if a.keep_conf else {}
    fresh = [r['m'] for _, r in rows if not r['cached']]
    for f in ('connect_ms', 'first_byte_ms', 'model_ms', 'total_ms', 'input_tokens'):
        v = [m[f] for m in fresh if m.get(f) is not None]
        out['timing'][f] = {'p50': pct(v, 50), 'p95': pct(v, 95), 'max': max(v) if v else None}
    out['timing']['calls'] = len(fresh)
    out['timing']['errors'] = sum(1 for m in fresh if m.get('error'))
    out['timing']['error_kinds'] = dict(Counter(m['error'] for m in fresh if m.get('error')))
    out['timing']['retried'] = sum(1 for m in fresh if m.get('attempts', 1) > 1)
    out['timing']['over_3s'] = sum(1 for m in fresh if m.get('total_ms', 0) > 3000)
    lines += ['', f"Fresh calls: {len(fresh)}. Errors: {out['timing']['errors']} {out['timing']['error_kinds']}. Retried: {out['timing']['retried']}. Over 3 s: {out['timing']['over_3s']}.", '',
              '| Step | p50 | p95 | max |', '|---|---|---|---|']
    for f in ('connect_ms', 'first_byte_ms', 'model_ms', 'total_ms', 'input_tokens'):
        t = out['timing'][f]
        lines.append(f"| {f} | {t['p50']} | {t['p95']} | {t['max']} |")
    base = os.path.join(EVAL_DIR, a.tag)
    for path, body in ((base + '.md', '\n'.join(lines) + '\n'), (base + '.json', json.dumps({'summary': out, 'scores': scores}
                                                       | ({'conf': conf} if a.keep_conf else {})))):
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)  # private: ids map to real chats
        os.fchmod(fd, 0o600)  # also tightens a file made earlier with looser rights
        with os.fdopen(fd, 'w') as f:
            f.write(body)
    print('\n'.join(lines))


if __name__ == '__main__':
    main()

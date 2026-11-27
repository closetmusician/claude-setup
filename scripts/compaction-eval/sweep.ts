// ABOUTME: Replays fast-compact (/fc) at many settings on the 44 shared points and scores each setting with scoreAfter from backtest.ts.
// ABOUTME: No Jev, no network. Cuts the newest-first way, like the default hook with provider none. Archive writes go to a mkdtemp dir.
// ABOUTME: Run: /Users/yklin/.bun/bin/bun sweep.ts [--out FILE]. Prints a markdown table; raw text never leaves out/points.jsonl.
// ABOUTME: Never edits backtest.ts or the vendor copy. The default row must reproduce 93.7% kept, median freed 19.3%, 24 of 44 fallbacks.
// ABOUTME: Spec: ~/.claude/docs/temp/compaction-replay-2026-11-26/scope.md (lane A).
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir, tmpdir } from 'node:os';
import { fcRun, scoreAfter, corpusOf } from './backtest.ts';
import type { Cut, Message, Options } from '../../plugins/local/fast-compact/src/types.ts';

const HERE = import.meta.dir;
const FC = join(HERE, '../../plugins/local/fast-compact');
const { plan, chooseWhole, cutsOf, applyCuts, sizeOf, fresh, mostFreed } = await import(join(FC, 'src/compact.ts'));
const { DEFAULT_OPTIONS } = await import(join(FC, 'src/types.ts'));
const { distinctiveTokens } = await import(join(FC, 'bench/points.ts'));

const PART_CHARS = 1_000_000;
const AUTO_MIN_FREED = 0.2;
const ISO = '20260101T000000';

interface Pt {
  id: string;
  session: string;
  before: Message[];
  neededDirect: string[];
  neededRefetched: string[];
  neededDirectNeverRepeated: string[];
  ceiling: number;
  thinkingChars: number;
  beforeChars: number;
}

// Purpose: stable short hash for archive file names, same as the hook.
// Usage: hashOf(key). Only the file name length matters here.
// Gotchas: copied from the hook, which does not export it.
function hashOf(text: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 0x01000193);
  return (h >>> 0).toString(16).padStart(8, '0');
}

// Purpose: split text into pieces of at most `size` chars without cutting a surrogate pair (same rule as the hook).
// Usage: pieces(text, PART_CHARS). Returns at least one piece.
// Gotchas: the hook calls this parts(); renamed to avoid a clash with local variables.
function pieces(text: string, size: number): string[] {
  const out: string[] = [];
  for (let at = 0; at < text.length; ) {
    let end = Math.min(text.length, at + size);
    const last = text.charCodeAt(end - 1);
    if (end < text.length && last >= 0xd800 && last <= 0xdbff) end--;
    out.push(text.slice(at, end));
    at = end;
  }
  return out.length > 0 ? out : [''];
}

interface Run {
  freedShare: number;
  ceilingShare: number;
  afterTokens: number;
  scores: ReturnType<typeof scoreAfter>;
  archiveOnly: { direct: number; directNeverRepeated: number };
  fallback: boolean;
  ms: number;
}

// Purpose: run the /fc cut on one point with the given options, exactly like backtest.ts fcRun but with options as a parameter.
// Usage: cutOnce(point, opts, dir). With dir set, also writes every cut original as a real archive file there and times it.
// Gotchas: newest-first ranking (no Jev). The fallback flag repeats the hook's three 20% checks. ms covers cut plus writes when dir is set.
function cutOnce(p: Pt, opts: Options, dir: string | null): { after: Message[]; cuts: Cut[]; fallback: boolean; ms: number; beforeChars: number; afterChars: number } {
  const archive = dir ? `${dir}/${p.session}` : `${homedir()}/.claude/fast-compact/${p.session}`;
  const stamp = ISO;
  const t0 = performance.now();
  const pl = plan(p.before, opts);
  const whole = chooseWhole(pl.outputs, undefined, opts, pl.cutBefore);
  const cuts: Cut[] = cutsOf(pl, whole);
  const pathOf = (cut: Cut): string => {
    const key = cut.kind === 'notice' ? `${stamp}-${cut.key}` : cut.key;
    const safe = key.replace(/[^A-Za-z0-9._-]/g, '_').replace(/^\.+/, '_');
    return `${archive}/${cut.kind}-${safe === key ? safe : `${safe}-${hashOf(key)}`}.txt`;
  };
  const whereOf = (cut: Cut): string => {
    const n = Math.max(1, Math.ceil(cut.original.length / PART_CHARS));
    return n > 1 ? `${pathOf(cut)} (continued in .part2 to .part${n} beside it)` : pathOf(cut);
  };
  if (dir) {
    mkdirSync(archive, { recursive: true });
    for (const cut of cuts) {
      const ps = pieces(cut.original, PART_CHARS);
      ps.forEach((piece, i) => writeFileSync(i === 0 ? pathOf(cut) : `${pathOf(cut)}.part${i + 1}`, piece));
    }
  }
  const cutMsgs: Message[] = cuts.length > 0 ? applyCuts(p.before, cuts, whereOf, opts) : [...p.before];
  const after: Message[] = fresh(cutMsgs);
  const ms = performance.now() - t0;
  const beforeChars = sizeOf(p.before);
  const afterChars = sizeOf(after);
  const enough = (n: number): boolean => beforeChars - n >= AUTO_MIN_FREED * beforeChars;
  const takes = cuts.length > 0 && enough(beforeChars - mostFreed(p.before, opts)) && enough(sizeOf(applyCuts(p.before, cuts, () => '', opts))) && enough(afterChars);
  return { after, cuts, fallback: !takes, ms, beforeChars, afterChars };
}

// Purpose: score one point at one setting: freed share, ceiling share, kept needed tokens, archive-only share, fallback flag.
// Usage: runPoint(point, opts). No file writes.
// Gotchas: archive-only counts needed tokens found in the cut originals but not in the after text (the model must re-read the file).
function runPoint(p: Pt, opts: Options): Run {
  const r = cutOnce(p, opts, null);
  const sc = scoreAfter(p, r.after);
  const have: Set<string> = distinctiveTokens(corpusOf(r.after));
  const arch: Set<string> = distinctiveTokens(r.cuts.map((c) => c.original).join('\n'));
  const only = (toks: string[]): number => toks.filter((t) => !have.has(t) && arch.has(t)).length;
  const freed = r.beforeChars > 0 ? (r.beforeChars - r.afterChars) / r.beforeChars : 0;
  return {
    freedShare: freed,
    ceilingShare: p.ceiling > 0 ? freed / p.ceiling : 0,
    afterTokens: sc.afterEstTokens,
    scores: sc,
    archiveOnly: { direct: only(p.neededDirect), directNeverRepeated: only(p.neededDirectNeverRepeated) },
    fallback: r.fallback,
    ms: r.ms,
  };
}

const median = (xs: number[]): number => {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
};
const mean = (xs: number[]): number => xs.reduce((a, b) => a + b, 0) / xs.length;
const sum = (xs: number[]): number => xs.reduce((a, b) => a + b, 0);
const pc = (x: number): string => `${(100 * x).toFixed(1)}%`;

const O = (o: Partial<Options>): Options => ({ ...DEFAULT_OPTIONS, ...o });
const SETTINGS: [string, Options][] = [
  ['default', O({})],
  ['cutTo 1000', O({ cutTo: 1000 })],
  ['cutTo 600', O({ cutTo: 600 })],
  ['cutTo 300', O({ cutTo: 300 })],
  ['keepRecentCalls 5', O({ keepRecentCalls: 5 })],
  ['keepRecentCalls 3', O({ keepRecentCalls: 3 })],
  ['keepRecentCalls 0', O({ keepRecentCalls: 0 })],
  ['keepWhole 0.1', O({ keepWhole: 0.1 })],
  ['keepWhole 0', O({ keepWhole: 0 })],
  ['noticeCutTo 100', O({ noticeCutTo: 100 })],
  ['medium (cutTo 600, recent 5, whole 0.1)', O({ cutTo: 600, keepRecentCalls: 5, keepWhole: 0.1 })],
  ['hard (cutTo 300, recent 3, whole 0)', O({ cutTo: 300, keepRecentCalls: 3, keepWhole: 0 })],
];

// Purpose: median wall clock of the full cut plus real archive writes over all points, in a fresh temp dir.
// Usage: wallClock(points, opts). Removes the temp dir at the end.
// Gotchas: includes disk writes; the first points may be slower (cold cache). Includes the cut itself (plan, apply, fresh).
function wallClock(pts: Pt[], opts: Options): number {
  const dir = mkdtempSync(join(tmpdir(), 'fcsweep-'));
  try {
    return median(pts.map((p) => cutOnce(p, opts, dir).ms));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// Purpose: run the sweep and print the markdown table.
// Usage: bun sweep.ts [--out FILE]. Stops with exit 2 if the default row misses the regression anchor.
// Gotchas: reads out/points.jsonl (raw text); prints numbers only.
function main(): void {
  const pts: Pt[] = readFileSync(join(HERE, 'out/points.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  // Cross-check: my cut equals backtest.ts fcRun at default settings on every point.
  let mismatch = 0;
  for (const p of pts) {
    const a = fcRun(p.before, p.session, '2026-01-01T00:00:00Z');
    const b = cutOnce(p, DEFAULT_OPTIONS, null);
    if (a.afterChars !== b.afterChars || a.hookTakesAuto === b.fallback) mismatch++;
  }
  const rows: string[] = [];
  const header = '| Setting | Freed median | Freed mean | Of ceiling (median per point) | After tokens median | Direct kept | Re-fetched kept | Never-repeated kept | Never-repeated archive only | Fallbacks (of 44) |';
  rows.push(header, '|' + header.split('|').slice(1, -1).map(() => '---').join('|') + '|');
  let defaultOk = true;
  const detail: string[] = [];
  for (const [name, opts] of SETTINGS) {
    const rs = pts.map((p) => runPoint(p, opts));
    const k = (f: (r: Run) => { n: number; kept: number }): string => {
      const n = sum(rs.map((r) => f(r).n));
      const kept = sum(rs.map((r) => f(r).kept));
      return `${pc(kept / n)} (${kept}/${n})`;
    };
    const nn = sum(rs.map((r) => r.scores.directNeverRepeated.n));
    const ao = sum(rs.map((r) => r.archiveOnly.directNeverRepeated));
    const aod = sum(rs.map((r) => r.archiveOnly.direct));
    const nd = sum(rs.map((r) => r.scores.direct.n));
    const fb = rs.filter((r) => r.fallback).length;
    rows.push(`| ${name} | ${pc(median(rs.map((r) => r.freedShare)))} | ${pc(mean(rs.map((r) => r.freedShare)))} | ${pc(median(rs.map((r) => r.ceilingShare)))} | ${Math.round(median(rs.map((r) => r.afterTokens))).toLocaleString()} | ${k((r) => r.scores.direct)} | ${k((r) => r.scores.refetched)} | ${k((r) => r.scores.directNeverRepeated)} | ${pc(ao / nn)} (${ao}/${nn}) | ${fb} |`);
    detail.push(`${name}: direct archive-only ${pc(aod / nd)} (${aod}/${nd})`);
    if (name === 'default') {
      const dk = sum(rs.map((r) => r.scores.direct.kept)) / nd;
      defaultOk = Math.abs(dk - 0.937) < 0.0005 && Math.abs(median(rs.map((r) => r.freedShare)) - 0.193) < 0.0005 && fb === 24;
      detail.push(`default anchor: direct kept ${pc(dk)}, median freed ${pc(median(rs.map((r) => r.freedShare)))}, fallbacks ${fb}, anchor ${defaultOk ? 'PASS' : 'FAIL'}, fcRun cross-check mismatches ${mismatch}`);
      if (!defaultOk || mismatch) {
        console.log(detail.join('\n'));
        process.exit(2);
      }
    }
  }
  const thinkShare = pts.map((p) => (p.beforeChars > 0 ? p.thinkingChars / p.beforeChars : 0));
  const wcDefault = wallClock(pts, DEFAULT_OPTIONS);
  const wcHard = wallClock(pts, SETTINGS[SETTINGS.length - 1]![1]);
  const out = [
    ...rows,
    '',
    ...detail,
    `thinking (separate, not mixed in): median thinkingChars/beforeChars ${pc(median(thinkShare))}, mean ${pc(mean(thinkShare))}, median thinkingChars ${Math.round(median(pts.map((p) => p.thinkingChars)))}`,
    `median ceiling ${pc(median(pts.map((p) => p.ceiling)))}`,
    `wall clock median per point (cut plus real archive writes): default ${wcDefault.toFixed(1)} ms, hard ${wcHard.toFixed(1)} ms`,
  ].join('\n');
  console.log(out);
  const i = process.argv.indexOf('--out');
  if (i >= 0 && process.argv[i + 1]) writeFileSync(process.argv[i + 1]!, out + '\n');
}

main();

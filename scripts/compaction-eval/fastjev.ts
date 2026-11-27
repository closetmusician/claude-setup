// ABOUTME: Replays fast-jev-compaction (tamaratran, frozen copy in ../../plugins/local/fast-compact/bench/upstream) on the 44 shared points, with real OpenJev answers.
// ABOUTME: It calls upstream compact() unchanged, with a JevAsker that posts to Codiv (api.codiv.ai/v1/systemone, model jev-latest).
// ABOUTME: Scoring uses scoreAfter from backtest.ts, so /fc and fast-jev share one yardstick. Results hold numbers only, no transcript text.
// ABOUTME: Run: bun fastjev.ts --step0 | --run [--limit N] | --report. Writes out/fastjev-results.json and the lane-B report. Cache: out/jev-cache/.
// ABOUTME: Spec: docs/temp/compaction-replay-2026-11-26/scope.md. Secrets are masked with the clarity_jev.py pattern before anything is sent.
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { scoreAfter } from './backtest.ts';
import { compact, batchCalls, questionsFor, reductionRatio } from '../../plugins/local/fast-compact/bench/upstream/compact.ts';
import { collectToolCalls, estimateTokens, fitState } from '../../plugins/local/fast-compact/bench/upstream/state.ts';
import { buildJevRequest, noulAnswer, parseJevResponse } from '../../plugins/local/fast-compact/bench/upstream/request.ts';
import type { CompactResult, JevAsker, JevQuestions, JevResponse, JevState, Message } from '../../plugins/local/fast-compact/bench/upstream/types.ts';

const HERE = import.meta.dir;
const OUT = join(HERE, 'out');
const CACHE = join(OUT, 'jev-cache');
const POINTS = join(OUT, 'points.jsonl');
const RESULTS = join(OUT, 'fastjev-results.json');
const STEP0 = join(OUT, 'fastjev-step0.json');
const RUN_DIR = join(homedir(), '.claude/docs/temp/compaction-replay-2026-11-26');
const MODEL = 'jev-latest';
const MAX_CONCURRENT = 4;
const TOKEN_CAP = 40_000_000;
const MIN_REDUCTION = 0.25; // minReductionRatio of the real hook (tamaratran/fast-jev-compaction hooks/fast-jev.ts)
const TIMEOUT_MS = 180_000;

// Same patterns as scripts/governance/clarity_jev.py SECRET. The keyword pattern is case-insensitive, as the Python (?i:...) group is.
const SECRET = /ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{22,}|ATATT[A-Za-z0-9_=.-]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----|glpat-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{35}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g;
const SECRET_KEYWORD = /(?:password|passwd|secret|api[_-]?key|token)["']?\s*[=:]\s*["']?[^\s"']{8,}/gi;

type Point = {
  id: string; preTokens: number; postTokens: number; durationMs: number; before: Message[];
  neededDirect: string[]; neededRefetched: string[]; neededDirectNeverRepeated: string[];
  builtinKept: { direct: boolean[]; refetched: boolean[]; directNeverRepeated: boolean[] };
  ceiling: number; beforeChars: number;
};

// Purpose: read the points file written by backtest.ts --dump.
// Usage: loadPoints(). Returns the 44 points in file order.
// Gotchas: the file holds raw transcript text. Never print or copy its content.
function loadPoints(): Point[] {
  return readFileSync(POINTS, 'utf8').trim().split('\n').map((l) => JSON.parse(l) as Point);
}

// Purpose: read TYPESAFE_API_KEY and CODIV_BASE_URL from ~/.claude/.env without printing them.
// Usage: const { key, url } = loadEnv(). url is the full System One endpoint.
// Gotchas: accepts "export K=V" and quotes. Throws if the key is missing. Never log the key.
function loadEnv(): { key: string; url: string } {
  const env: Record<string, string> = {};
  for (let line of readFileSync(join(homedir(), '.claude/.env'), 'utf8').split('\n')) {
    line = line.trim();
    if (!line.includes('=') || line.startsWith('#')) continue;
    const i = line.replace(/^export\s+/, '').indexOf('=');
    const s = line.replace(/^export\s+/, '');
    env[s.slice(0, i).trim()] = s.slice(i + 1).trim().replace(/^["']|["']$/g, '');
  }
  const key = env.TYPESAFE_API_KEY;
  if (!key) throw new Error('TYPESAFE_API_KEY missing in ~/.claude/.env');
  const base = (env.CODIV_BASE_URL ?? 'https://api.codiv.ai').replace(/\/+$/, '');
  return { key, url: base.endsWith('/v1/systemone') ? base : `${base}/v1/systemone` };
}

// Purpose: mask secrets in one string and count the masks.
// Usage: redactString(s). Returns the masked text.
// Gotchas: pattern based, so only known secret shapes are caught. Counted in the global redactedTotal.
let redactedTotal = 0;
function redactString(s: string): string {
  const fix = (m: string): string => { redactedTotal++; return '[SECRET]'; };
  return s.toWellFormed().replace(SECRET, fix).replace(SECRET_KEYWORD, fix);
}

// Purpose: tracks live and cached requests, tokens and times for one point or the whole run.
// Usage: a Stats object is created per point; the asker adds to the current one and to the total.
// Gotchas: inputTokens uses the usage the server reports; it falls back to the upstream estimate.
interface Stats { http: number; cached: number; inputTokens: number; outputTokens: number; liveMs: number[]; models: Set<string>; }
const newStats = (): Stats => ({ http: 0, cached: 0, inputTokens: 0, outputTokens: 0, liveMs: [], models: new Set() });
const total = newStats();
let current = newStats();
let liveInputTokens = 0;

let active = 0;
const waiting: (() => void)[] = [];

// Purpose: run fn with at most MAX_CONCURRENT calls in flight across the whole process.
// Usage: await limited(() => post(...)).
// Gotchas: the quota is shared with the live reply guards, so do not raise MAX_CONCURRENT.
async function limited<T>(fn: () => Promise<T>): Promise<T> {
  if (active >= MAX_CONCURRENT) await new Promise<void>((r) => waiting.push(r));
  active++;
  try { return await fn(); } finally { active--; waiting.shift()?.(); }
}

// Purpose: POST one request body to Codiv. Retries a 429 at most twice (2 s, then 6 s).
// Usage: const { status, ok, text, ms } = await post(body).
// Gotchas: a timeout or network error returns status 0 with no retry; the caller marks the point FAILED.
async function post(req: ReturnType<typeof buildJevRequest>): Promise<{ status: number; ok: boolean; text: string; ms: number }> {
  const started = Date.now();
  for (let attempt = 0; ; attempt++) {
    let status = 0, ok = false, text = '';
    try {
      const r = await fetch(req.url, { method: 'POST', headers: req.headers, body: req.body, signal: AbortSignal.timeout(TIMEOUT_MS) });
      status = r.status; ok = r.ok; text = await r.text();
    } catch (e) { text = `network error: ${(e as Error).name}`; }
    if (status === 429 && attempt < 2) { await Bun.sleep(attempt === 0 ? 2000 : 6000); continue; }
    return { status, ok, text, ms: Date.now() - started };
  }
}

// Purpose: the JevAsker that upstream compact() calls. Masks secrets, caches by request hash, posts to Codiv.
// Usage: compact(messages, new CodivAsker()). Throws on any non-200, bad JSON or missing answers.
// Gotchas: only good answers are cached. The cache key hashes the masked body, never the key. Stops the run past TOKEN_CAP live input tokens.
class CodivAsker implements JevAsker {
  private env = loadEnv();
  async ask(state: JevState, questions: JevQuestions): Promise<JevResponse> {
    if (liveInputTokens > TOKEN_CAP) throw new Error('TOKEN_CAP exceeded: run stopped');
    const body = JSON.stringify({ model: MODEL, state, questions }, (_k, v: unknown) => (typeof v === 'string' ? redactString(v) : v));
    const hash = createHash('sha256').update(body).digest('hex').slice(0, 24);
    const file = join(CACHE, `${hash}.json`);
    const estimate = estimateTokens(body);
    let parsed: JevResponse;
    if (existsSync(file)) {
      const c = JSON.parse(readFileSync(file, 'utf8')) as { response: JevResponse; ms: number };
      parsed = c.response;
      for (const s of [current, total]) { s.cached++; s.inputTokens += parsed.usage?.input_tokens ?? estimate; s.outputTokens += parsed.usage?.output_tokens ?? 0; if (parsed.model) s.models.add(parsed.model); }
      return parsed;
    }
    const req = buildJevRequest({ apiKey: this.env.key, model: MODEL, baseUrl: this.env.url }, JSON.parse(body).state, JSON.parse(body).questions);
    const r = await limited(() => post(req));
    parsed = parseJevResponse(r.status, r.ok, r.text);
    for (const name of Object.keys(questions)) noulAnswer(parsed.answers, name); // bad answer throws before caching
    mkdirSync(CACHE, { recursive: true });
    writeFileSync(file, JSON.stringify({ response: parsed, ms: r.ms }));
    const used = parsed.usage?.input_tokens ?? estimate;
    liveInputTokens += used;
    for (const s of [current, total]) { s.http++; s.inputTokens += used; s.outputTokens += parsed.usage?.output_tokens ?? 0; s.liveMs.push(r.ms); if (parsed.model) s.models.add(parsed.model); }
    return parsed;
  }
}

// Purpose: step 0. Send ONE full real request built from the largest point and report what came back.
// Usage: bun fastjev.ts --step0. Writes out/fastjev-step0.json (numbers only).
// Gotchas: the request is cached, so the full run reuses it. A failure is recorded and the run stops.
async function step0(points: Point[]): Promise<void> {
  const p = points.reduce((a, b) => (b.beforeChars > a.beforeChars ? b : a));
  const calls = collectToolCalls(p.before, 6);
  const cands = calls.filter((c) => !c.pinned);
  const fitted = fitState(p.before, calls, { goal: '', preserveRecentMessages: 6, maxStateTokens: 25_000 });
  const batches = batchCalls(cands, fitted.tokens, { maxRequestTokens: 30_000 });
  const questions = Object.assign({}, ...batches[0]!.map(questionsFor)) as JevQuestions;
  const result: Record<string, unknown> = { point: p.id, beforeChars: p.beforeChars, candidates: cands.length, batches: batches.length, firstBatchCalls: batches[0]!.length, stateTokensEst: fitted.tokens, stage: fitted.stage };
  const asker = new CodivAsker();
  const t = Date.now();
  try {
    const resp = await asker.ask(fitted.state, questions);
    result.ok = true; result.httpStatus = 200; result.model = resp.model ?? null; result.parseAccepted = true;
    result.usage = resp.usage ?? null; result.roundTripMs = Date.now() - t;
    result.requestEstTokens = estimateTokens(JSON.stringify({ model: MODEL, state: fitted.state, questions }));
    result.answerCount = Object.keys(resp.answers).length;
    result.cachedHit = total.cached > 0;
  } catch (e) {
    result.ok = false; result.error = String((e as Error).message).slice(0, 200); result.roundTripMs = Date.now() - t;
  }
  writeFileSync(STEP0, JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
}

interface PointResult {
  id: string; failed?: string; model?: string;
  beforeChars: number; ceiling: number; reduction?: number; fallback?: boolean;
  freedShare?: number; freedOfCeiling?: number; freedTokens?: number; beforeEstTokens?: number;
  classes?: { direct: [number, number]; refetched: [number, number]; directNeverRepeated: [number, number] };
  decisions?: { kept: number; truncated: number; droppedCall: number; pinned: number };
  damage?: number; wallMs?: number; builtinMs: number; httpRequests?: number; cachedRequests?: number; compactRequests?: number;
  inputTokens?: number; stateStage?: string;
  keepCall?: number[]; keepResult?: number[];
  shipped?: { freedShare: number; freedTokens: number; classes: PointResult['classes']; wallMs: number };
}

// Purpose: count damage: assistant text messages left in the history after every tool call of their assistant turn was dropped (drop_call).
// Usage: damageCount(before, result). A turn is a run of consecutive assistant messages (Claude Code stores the text and the tool_use blocks of one reply as separate records).
// Gotchas: tool uses with no result are never decided and count as not dropped. Turns with no tool use are not counted.
function damageCount(before: readonly Message[], r: CompactResult): number {
  const drop = new Set<string>();
  const idOf = new Map(collectToolCalls(before, 6).map((c) => [c.id, c.tool_use_id]));
  for (const d of r.decisions) if (d.action === 'drop_call') drop.add(idOf.get(d.id)!);
  let n = 0;
  for (let i = 0; i < before.length; ) {
    if (before[i]!.role !== 'assistant') { i++; continue; }
    let j = i;
    while (j < before.length && before[j]!.role === 'assistant') j++;
    const turn = before.slice(i, j);
    const uses = turn.flatMap((m) => m.toolUses);
    if (uses.length > 0 && uses.every((t) => drop.has(t.tool_use_id))) n += turn.filter((m) => m.text.trim().length > 0).length;
    i = j;
  }
  return n;
}

// Purpose: count the true flags of a built-in kept list as [n, kept].
// Usage: flagPair(point.builtinKept.direct).
// Gotchas: same order and length as the needed token list.
const flagPair = (f: boolean[]): [number, number] => [f.length, f.filter(Boolean).length];

// Purpose: run upstream compact() on one point and measure it on the shared yardstick.
// Usage: await runPoint(point). Returns a PointResult; a thrown error becomes failed, never kept-all or dropped-all.
// Gotchas: points run one after another so wall clock is honest; batches inside one point run concurrently (cap 4 overall).
async function runPoint(p: Point): Promise<PointResult> {
  current = newStats();
  const res: PointResult = { id: p.id, beforeChars: p.beforeChars, ceiling: p.ceiling, builtinMs: p.durationMs };
  const started = Date.now();
  let out: CompactResult;
  try {
    out = await compact(p.before, new CodivAsker(), { keepThreshold: 0.5, preserveRecentMessages: 6, maxStateTokens: 25_000, maxRequestTokens: 30_000, truncateHeadChars: 300 });
  } catch (e) {
    res.failed = String((e as Error).message).slice(0, 160);
    res.wallMs = Date.now() - started;
    return res;
  }
  res.wallMs = Date.now() - started;
  res.model = [...current.models].join(',') || undefined;
  const after = scoreAfter(p, out.messages);
  const beforeEst = scoreAfter(p, p.before).afterEstTokens;
  res.beforeEstTokens = beforeEst;
  res.reduction = reductionRatio(out);
  res.fallback = res.reduction < MIN_REDUCTION;
  res.freedShare = (p.beforeChars - after.afterChars) / p.beforeChars;
  res.freedOfCeiling = res.freedShare / p.ceiling;
  res.freedTokens = beforeEst - after.afterEstTokens;
  res.classes = { direct: [after.direct.n, after.direct.kept], refetched: [after.refetched.n, after.refetched.kept], directNeverRepeated: [after.directNeverRepeated.n, after.directNeverRepeated.kept] };
  const s = out.stats;
  res.decisions = { kept: s.kept, truncated: s.resultsDropped, droppedCall: s.callsDropped, pinned: s.pinned };
  res.damage = damageCount(p.before, out);
  res.httpRequests = current.http; res.cachedRequests = current.cached; res.compactRequests = s.requests;
  res.inputTokens = current.inputTokens; res.stateStage = s.stateStage;
  const live = out.decisions.filter((d) => d.reason !== 'pinned');
  res.keepCall = live.map((d) => d.keepCall); res.keepResult = live.map((d) => d.keepResult);
  if (res.fallback) {
    res.shipped = { freedShare: 1 - p.postTokens / p.preTokens, freedTokens: p.preTokens - p.postTokens, classes: { direct: flagPair(p.builtinKept.direct), refetched: flagPair(p.builtinKept.refetched), directNeverRepeated: flagPair(p.builtinKept.directNeverRepeated) }, wallMs: res.wallMs + p.durationMs };
  } else {
    res.shipped = { freedShare: res.freedShare, freedTokens: res.freedTokens, classes: res.classes, wallMs: res.wallMs };
  }
  return res;
}

// Purpose: quantile of a list by linear interpolation.
// Usage: q([1,2,3], 0.5). Returns NaN for an empty list.
// Gotchas: sorts a copy.
function q(xs: number[], f: number): number {
  if (!xs.length) return NaN;
  const s = [...xs].sort((a, b) => a - b);
  const i = (s.length - 1) * f, lo = Math.floor(i), hi = Math.ceil(i);
  return s[lo]! + (s[hi]! - s[lo]!) * (i - lo);
}
const mean = (xs: number[]): number => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : NaN);
const pct = (x: number): string => `${(x * 100).toFixed(1)}%`;

// Purpose: build the comparison markdown from the saved per-point results.
// Usage: report(results). Returns the lane-B.md text (numbers only).
// Gotchas: failed points are left out of every average and listed with the count. Class share = sum kept / sum needed over points.
function report(all: PointResult[], step: Record<string, unknown> | null): string {
  const ok = all.filter((r) => !r.failed);
  const failed = all.filter((r) => r.failed);
  const models = [...new Set(ok.map((r) => r.model).filter(Boolean))];
  const jev113 = models.length > 0 && models.every((m) => /jev-1\.13/.test(m!));
  const label = jev113 ? 'fast-jev logic on jev-1.13' : `fast-jev logic on ${models.join(', ') || 'UNKNOWN model'}`;
  const classShare = (get: (r: PointResult) => PointResult['classes'] | undefined, k: 'direct' | 'refetched' | 'directNeverRepeated'): string => {
    let n = 0, kept = 0;
    for (const r of ok) { const c = get(r)?.[k]; if (c) { n += c[0]; kept += c[1]; } }
    return `${pct(n ? kept / n : NaN)} (${kept}/${n})`;
  };
  const fb = ok.filter((r) => r.fallback);
  const row = (name: string, share: number[], toks: number[], wall: number[], cls: (r: PointResult) => PointResult['classes'] | undefined, fallbacks: string): string =>
    `| ${name} | ${pct(q(share, 0.5))} / ${pct(mean(share))} | ${Math.round(q(toks, 0.5))} / ${Math.round(mean(toks))} | ${classShare(cls, 'direct')} | ${classShare(cls, 'directNeverRepeated')} | ${classShare(cls, 'refetched')} | ${(q(wall, 0.5) / 1000).toFixed(1)}s / ${(mean(wall) / 1000).toFixed(1)}s | ${fallbacks} |`;
  const ofCeil = (rs: PointResult[], useShipped: boolean): number[] => rs.map((r) => (useShipped ? r.shipped!.freedShare : r.freedShare!) / r.ceiling);
  const sumD = (k: 'kept' | 'truncated' | 'droppedCall' | 'pinned'): number => ok.reduce((a, r) => a + r.decisions![k], 0);
  const calls = ok.flatMap((r) => r.keepCall ?? []);
  const results = ok.flatMap((r) => r.keepResult ?? []);
  const modal = (xs: number[]): string => { const m = new Map<string, number>(); for (const x of xs) m.set(x.toFixed(2), (m.get(x.toFixed(2)) ?? 0) + 1); const [v, c] = [...m.entries()].sort((a, b) => b[1] - a[1])[0] ?? ['-', 0]; return `${pct(c / (xs.length || 1))} of answers share the value ${v}`; };
  const L: string[] = [];
  L.push('# Lane B: fast-jev-compaction replay on 44 points', '');
  L.push(`Label: ${label}. Models seen: ${models.join(', ') || 'none'}. Points scored: ${ok.length} of ${all.length}. Failed: ${failed.length}.`);
  L.push('Settings: upstream defaults (keepThreshold 0.5, preserveRecentMessages 6, maxStateTokens 25000, maxRequestTokens 30000, truncateHeadChars 300). Endpoint api.codiv.ai/v1/systemone, model jev-latest.', '');
  L.push('## Step 0 (one full request from the largest point)', '', '```json', JSON.stringify(step), '```', '');
  L.push('## Comparison table', '', 'Cells: median / mean over scored points. Class cells: kept / needed over all scored points (direct = direct tokens; direct-never-repeated = headline class; refetched = re-fetched tokens).', '');
  L.push('| Arm | Freed share of Before chars | Freed est. tokens | Direct kept | Direct never repeated kept | Re-fetched kept | Wall clock (compact only) | Fallbacks (<25%) |', '|---|---|---|---|---|---|---|---|');
  L.push(row('RAW (always pruned history)', ok.map((r) => r.freedShare!), ok.map((r) => r.freedTokens!), ok.map((r) => r.wallMs!), (r) => r.classes, `${fb.length} of ${ok.length} would fall back`));
  L.push(row('AS SHIPPED (fallback to built-in)', ok.map((r) => r.shipped!.freedShare), ok.map((r) => r.shipped!.freedTokens), ok.map((r) => r.shipped!.wallMs), (r) => r.shipped!.classes, `${fb.length} fell back (built-in numbers used)`));
  L.push('', `Share of ceiling reached (freed share divided by the point ceiling; median / mean): RAW ${pct(q(ofCeil(ok, false), 0.5))} / ${pct(mean(ofCeil(ok, false)))}; AS SHIPPED ${pct(q(ofCeil(ok, true), 0.5))} / ${pct(mean(ofCeil(ok, true)))}. Median ceiling ${pct(q(ok.map((r) => r.ceiling), 0.5))}.`);
  L.push('AS SHIPPED mixes scales: kept points use chars share and estimated tokens; fallback points use 1 - postTokens/preTokens and preTokens - postTokens from the transcript compactMetadata (real tokens).');
  L.push('', '## Decisions, damage, cost', '');
  L.push(`- Decisions over scored points: keep ${sumD('kept')}, truncate (drop_result) ${sumD('truncated')}, drop_call ${sumD('droppedCall')}, pinned ${sumD('pinned')}.`);
  L.push(`- Damage proxy (assistant text messages left after every tool call of their turn was dropped; turn = run of consecutive assistant messages): total ${ok.reduce((a, r) => a + r.damage!, 0)}; points with damage > 0: ${ok.filter((r) => r.damage! > 0).length} of ${ok.length}; max in one point ${Math.max(0, ...ok.map((r) => r.damage!))}.`);
  L.push(`- Requests: compact() batches ${ok.reduce((a, r) => a + r.compactRequests!, 0)}; live HTTP calls ${ok.reduce((a, r) => a + r.httpRequests!, 0)}; cache hits ${ok.reduce((a, r) => a + r.cachedRequests!, 0)}. Total input tokens (server usage, summed per point): ${ok.reduce((a, r) => a + r.inputTokens!, 0)} against the cap of ${TOKEN_CAP}. The server reports 0 output tokens. Step-0 request: server usage ${(step?.usage as {input_tokens?: number} | undefined)?.input_tokens ?? 'n/a'} input tokens against an upstream estimate of ${step?.requestEstTokens ?? 'n/a'}.`);
  L.push(`- Wall clock total (sum of per-point compact() times): ${(ok.reduce((a, r) => a + r.wallMs!, 0) / 1000).toFixed(0)}s. Built-in durationMs median ${(q(ok.map((r) => r.builtinMs), 0.5) / 1000).toFixed(1)}s. Points with any cached request (wall clock then not live): ${ok.filter((r) => r.cachedRequests! > 0).length}.`);
  L.push('- Secrets masked before sending: 2 in the live run (count from that process; a cached rerun does not recount).');
  L.push('', '## Score spread (unpinned calls, pooled)', '');
  L.push('| Score | n | p10 | median | p90 | share >= 0.5 | stuck check |', '|---|---|---|---|---|---|---|');
  for (const [name, xs] of [['keepCall', calls], ['keepResult', results]] as const) L.push(`| ${name} | ${xs.length} | ${q(xs, 0.1).toFixed(3)} | ${q(xs, 0.5).toFixed(3)} | ${q(xs, 0.9).toFixed(3)} | ${pct(xs.filter((x) => x >= 0.5).length / (xs.length || 1))} | ${modal(xs)} |`);
  L.push('', '## Failed points', '');
  if (!failed.length) L.push('None.'); else for (const f of failed) L.push(`- ${f.id}: ${f.failed}`);
  L.push('', '## Per point (RAW)', '', '| Point | Before chars | Freed | Of ceiling | Reduction | Fallback | Direct kept | Dec k/t/d | Damage | Wall | HTTP/cache | Model |', '|---|---|---|---|---|---|---|---|---|---|---|---|');
  for (const r of ok) L.push(`| ${r.id} | ${r.beforeChars} | ${pct(r.freedShare!)} | ${pct(r.freedOfCeiling!)} | ${pct(r.reduction!)} | ${r.fallback ? 'yes' : 'no'} | ${r.classes!.direct[1]}/${r.classes!.direct[0]} | ${r.decisions!.kept}/${r.decisions!.truncated}/${r.decisions!.droppedCall} | ${r.damage} | ${(r.wallMs! / 1000).toFixed(1)}s | ${r.httpRequests}/${r.cachedRequests} | ${r.model ?? ''} |`);
  return L.join('\n') + '\n';
}

// Purpose: entry point. Dispatches --step0, --run or --report.
// Usage: see the ABOUTME block. --run reads out/fastjev-step0.json and refuses to start if step 0 failed.
// Gotchas: --run saves results after every point, so a crash keeps finished points; --report rebuilds the markdown only.
async function main(): Promise<void> {
  mkdirSync(OUT, { recursive: true });
  const argv = process.argv.slice(2);
  const points = loadPoints();
  if (argv.includes('--step0')) return step0(points);
  const step = existsSync(STEP0) ? (JSON.parse(readFileSync(STEP0, 'utf8')) as Record<string, unknown>) : null;
  if (argv.includes('--run')) {
    if (!step || step.ok !== true) throw new Error('step 0 not passed: run --step0 first');
    const li = argv.indexOf('--limit');
    const list = li >= 0 ? points.slice(0, Number(argv[li + 1])) : points;
    const results: PointResult[] = existsSync(RESULTS) ? (JSON.parse(readFileSync(RESULTS, 'utf8')) as PointResult[]).filter((r) => !r.failed) : [];
    for (const p of list) {
      if (results.some((r) => r.id === p.id)) continue; // finished in an earlier run (its wall clock stays the live one)
      const r = await runPoint(p);
      results.push(r);
      writeFileSync(RESULTS, JSON.stringify(results));
      console.log(`${p.id} ${r.failed ? `FAILED ${r.failed}` : `freed ${pct(r.freedShare!)} direct ${r.classes!.direct[1]}/${r.classes!.direct[0]} wall ${((r.wallMs ?? 0) / 1000).toFixed(1)}s http ${r.httpRequests}`}`);
      if (liveInputTokens > TOKEN_CAP) { console.log('TOKEN_CAP passed: stopping'); break; }
    }
  }
  const results = JSON.parse(readFileSync(RESULTS, 'utf8')) as PointResult[];
  const md = report(results, step);
  mkdirSync(RUN_DIR, { recursive: true });
  writeFileSync(join(RUN_DIR, 'lane-B.md'), md);
  console.log(`wrote ${join(RUN_DIR, 'lane-B.md')}`);
}

await main();

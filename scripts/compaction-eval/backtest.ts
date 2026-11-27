// ABOUTME: Replays every built-in Claude Code compaction on this machine and asks what fast-compact would have kept.
// ABOUTME: Per point it compares the built-in summary and fast-compact's cut (no Jev, no network) with the tokens the assistant used next.
// ABOUTME: It only reads transcripts. It never writes under ~/.claude/projects and never edits the vendor copy of fast-compact.
// ABOUTME: Run: bun backtest.ts [--root DIR] [--fc DIR] [--window 40] [--trace 2] [--dump FILE]. Writes out/backtest-points.jsonl and out/backtest-summary.md.
// ABOUTME: --dump writes one shared point per line (raw transcript text, may hold secrets). Other tools import processFile and scoreAfter from here.
// ABOUTME: Spec: ~/.claude/docs/plans/harness/compaction-eval/spec.md (the "Spec fixes from the Codex check" section wins).
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { homedir } from 'node:os';
import { basename, join } from 'node:path';
import type { Cut, Message } from '../../plugins/local/fast-compact/src/types.ts';

const args = process.argv.slice(2);

// Purpose: read one "--name value" command line option.
// Usage: flag('--root', default). Returns the default when the option is absent.
// Gotchas: no "--name=value" form; the value is the next argument.
function flag(name: string, fallback: string): string {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] !== undefined ? args[i + 1]! : fallback;
}

const HERE = import.meta.dir;
const ROOT = flag('--root', join(homedir(), '.claude/projects'));
const FC = flag('--fc', join(HERE, '../../plugins/local/fast-compact'));
const WINDOW = Number(flag('--window', '40'));
const TRACE = Number(flag('--trace', '0'));
const OUT = join(HERE, 'out');

// fast-compact's own code, loaded from ~/.claude/plugins/local/fast-compact (or --fc <dir>; for the old ea84e37 baseline, check that commit out to a worktree and pass it).
const { plan, chooseWhole, cutsOf, applyCuts, sizeOf, fresh, mostFreed } = await import(join(FC, 'src/compact.ts'));
const { DEFAULT_OPTIONS } = await import(join(FC, 'src/types.ts'));
const { estimateTokens } = await import(join(FC, 'src/state.ts'));
const { isHostText } = await import(join(FC, 'bench/transcript.ts'));
const { distinctiveTokens } = await import(join(FC, 'bench/points.ts'));

type Block = { type: string; text?: string; thinking?: string; id?: string; name?: string; input?: Record<string, unknown>; tool_use_id?: string; content?: unknown; is_error?: boolean };
type Rec = {
  type: string;
  subtype?: string;
  uuid?: string;
  parentUuid?: string | null;
  logicalParentUuid?: string | null;
  isSidechain?: boolean;
  isMeta?: boolean;
  isCompactSummary?: boolean;
  content?: string;
  timestamp?: string;
  message?: { content?: string | Block[] };
  compactMetadata?: {
    trigger?: string;
    preTokens?: number;
    postTokens?: number;
    durationMs?: number;
    preservedMessages?: { uuids?: string[] };
  };
};
type EvalMsg = Message & { uuid: string; host?: boolean };

// ---------------------------------------------------------------- fc ledger

const LEDGER_DIR = flag('--ledger-dir', join(homedir(), '.claude/fast-compact'));
const LEDGER_SLACK_MS = 120_000;
type LedgerLine = { session: string; at: number };
const usedLedger = new Set<LedgerLine>();

// Purpose: read all fast-compact ledger lines (ledger-*.jsonl), to tell fc compactions from built-in ones.
// Usage: loadLedger(dir). Returns session and time for each valid line.
// Gotchas: a missing folder (fc not installed) gives an empty list.
function loadLedger(dir: string): LedgerLine[] {
  if (!existsSync(dir)) return [];
  const out: LedgerLine[] = [];
  for (const f of readdirSync(dir)) {
    if (!/^ledger-.*\.jsonl$/.test(f)) continue;
    for (const line of readFileSync(join(dir, f), 'utf8').split('\n')) {
      try {
        const row = JSON.parse(line) as { at?: string; session?: string };
        const at = Date.parse(row.at ?? '');
        if (row.session && Number.isFinite(at)) out.push({ session: row.session, at });
      } catch {
        // blank or torn line
      }
    }
  }
  return out;
}
const LEDGER = loadLedger(LEDGER_DIR);

// Purpose: whether a ledger line proves this boundary was an fc compaction.
// Usage: isFcBoundary(session, isoTime). Same rule as report.py: same session, within 120 s, one line per boundary.
// Gotchas: marks the nearest unused line as used so one line never explains two boundaries.
function isFcBoundary(session: string, iso: string | undefined): boolean {
  const t = Date.parse(iso ?? '');
  if (!Number.isFinite(t)) return false;
  let best: LedgerLine | undefined;
  for (const l of LEDGER) {
    if (l.session !== session || usedLedger.has(l)) continue;
    const d = Math.abs(l.at - t);
    if (d <= LEDGER_SLACK_MS && (!best || d < Math.abs(best.at - t))) best = l;
  }
  if (best) usedLedger.add(best);
  return !!best;
}

// ---------------------------------------------------------------- reading

// Purpose: turn a tool_result content value into the text the model read.
// Usage: resultText(block.content). Images and other non-text parts become "[type]".
// Gotchas: matches fast-compact's own reader so sizes line up with the hook.
function resultText(content: unknown): string {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.map((p: Block) => (p.type === 'text' ? (p.text ?? '') : `[${p.type}]`)).join('\n');
}

// Purpose: adapter from one transcript line to hook-shaped messages, keeping EVERY block.
// Usage: toMessages(rec). An assistant line with 3 blocks gives up to 3 messages (text or tool call each).
// Gotchas: fast-compact's reader keeps only content[0] of an assistant line; this one fixes that. Thinking blocks are dropped.
function toMessages(rec: Rec): EvalMsg[] {
  const uuid = rec.uuid!;
  const content = rec.message?.content;
  if (rec.type === 'assistant') {
    if (!Array.isArray(content)) return [];
    const out: EvalMsg[] = [];
    for (const b of content) {
      if (b.type === 'text' && b.text) out.push({ uuid, role: 'assistant', text: b.text, toolUses: [] });
      else if (b.type === 'tool_use' && b.id && b.name) {
        out.push({ uuid, role: 'assistant', text: '', toolUses: [{ tool_use_id: b.id, tool: b.name, input: b.input ?? {} }] });
      }
    }
    return out;
  }
  if (rec.type !== 'user') return [];
  const meta = !!(rec.isMeta || rec.isCompactSummary);
  if (typeof content === 'string') return [{ uuid, role: 'user', text: content, toolUses: [], host: meta || isHostText(content) || undefined }];
  if (!Array.isArray(content)) return [];
  const texts: string[] = [];
  const toolResults: { tool_use_id: string; text: string; isError: boolean }[] = [];
  for (const b of content) {
    if (b.type === 'text' && b.text) texts.push(b.text);
    else if (b.type === 'image') texts.push('[image]');
    else if (b.type === 'tool_result' && b.tool_use_id) toolResults.push({ tool_use_id: b.tool_use_id, text: resultText(b.content), isError: b.is_error === true });
  }
  const text = texts.join('\n');
  if (!text && toolResults.length === 0) return [];
  const m: EvalMsg = { uuid, role: 'user', text, toolUses: [] };
  if (toolResults.length > 0) m.toolResults = toolResults;
  if (text && (meta || isHostText(text))) m.host = true;
  return [m];
}

// Purpose: read all lines of one transcript file.
// Usage: readRecords(path). Returns records in file order.
// Gotchas: a torn last line (session still writing) is skipped, not an error.
export function readRecords(path: string): Rec[] {
  const out: Rec[] = [];
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    if (!line) continue;
    try {
      out.push(JSON.parse(line) as Rec);
    } catch {
      // torn line
    }
  }
  return out;
}

// Purpose: the parent chain from a leaf record back to its root, oldest first.
// Usage: chainBack(byUuid, leafUuid). Stops at a compaction boundary (its parent is null).
// Gotchas: the map spans the whole file, so a chain can cross where fast-compact's per-segment reader stops.
function chainBack(byUuid: Map<string, Rec>, leaf: string | undefined | null): Rec[] {
  const chain: Rec[] = [];
  const seen = new Set<string>();
  for (let r = leaf ? byUuid.get(leaf) : undefined; r?.uuid && !seen.has(r.uuid); r = r.parentUuid ? byUuid.get(r.parentUuid) : undefined) {
    seen.add(r.uuid);
    chain.push(r);
  }
  return chain.reverse();
}

// Purpose: flatten every string inside a tool input into plain lines of text.
// Usage: inputText(input). Used to look for tokens in tool inputs.
// Gotchas: avoids JSON.stringify, which would add backslashes that split tokens.
function inputText(v: unknown): string {
  if (typeof v === 'string') return v;
  if (typeof v === 'number') return String(v);
  if (Array.isArray(v)) return v.map(inputText).join('\n');
  if (v && typeof v === 'object') return Object.values(v).map(inputText).join('\n');
  return '';
}

// Purpose: all the text one message carries: its words, tool inputs and tool outputs.
// Usage: corpusOf(messages). The result is what "kept" checks search.
// Gotchas: for fast-compact the messages are the CUT ones, so cut-away text is not in here.
export function corpusOf(msgs: readonly Message[]): string {
  const parts: string[] = [];
  for (const m of msgs) {
    if (m.text) parts.push(m.text);
    for (const u of m.toolUses) parts.push(inputText(u.input));
    for (const r of m.toolResults ?? []) parts.push(r.text);
  }
  return parts.join('\n');
}

// Purpose: add tool-result records that the parent walk dropped, then put all records in file order.
// Usage: withSiblingResults(chain, recs, posOf, from, to). Looks only at file positions from..to.
// Gotchas: parallel tool calls give each result its own parent, so a plain walk keeps only one result of a batch.
function withSiblingResults(chain: Rec[], recs: Rec[], posOf: Map<string, number>, from: number, to: number): Rec[] {
  const have = new Set(chain.map((r) => r.uuid));
  const called = new Set<string>();
  const answered = new Set<string>();
  const blocks = (r: Rec): Block[] => (Array.isArray(r.message?.content) ? (r.message!.content as Block[]) : []);
  for (const r of chain) for (const b of blocks(r)) {
    if (b.type === 'tool_use' && b.id) called.add(b.id);
    if (b.type === 'tool_result' && b.tool_use_id) answered.add(b.tool_use_id);
  }
  const extra: Rec[] = [];
  for (let j = Math.max(0, from); j <= Math.min(to, recs.length - 1); j++) {
    const r = recs[j]!;
    if (r.type !== 'user' || r.isSidechain || !r.uuid || have.has(r.uuid)) continue;
    if (blocks(r).some((b) => b.type === 'tool_result' && b.tool_use_id && called.has(b.tool_use_id) && !answered.has(b.tool_use_id))) extra.push(r);
  }
  return [...chain, ...extra].sort((x, y) => posOf.get(x.uuid!)! - posOf.get(y.uuid!)!);
}

// ---------------------------------------------------------------- fast-compact

// Purpose: short stable hash used in archive file names (copied from hooks/fast-compact.ts, which does not export it).
// Usage: hashOf(key). Only matters for the length of the archive path.
// Gotchas: keep in step with the hook if it changes; the vendor pin makes that explicit.
function hashOf(text: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 0x01000193);
  return (h >>> 0).toString(16).padStart(8, '0');
}

const PART_CHARS = 1_000_000;
const AUTO_MIN_FREED = 0.2;

interface FcResult {
  cuts: Cut[];
  after: Message[];
  ms: number;
  beforeChars: number;
  afterChars: number;
  hookTakesAuto: boolean;
}

// Purpose: run fast-compact's full cut on the Before messages as the hook does, without Jev or archive writes.
// Usage: fcRun(messages, sessionId, isoTime). Runs plan, chooseWhole (with cutBefore), cutsOf, applyCuts, fresh (resumeSafe on).
// Gotchas: time covers the cut only, not archive writes or host time. hookTakesAuto repeats the hook's three 20% checks.
export function fcRun(messages: Message[], session: string, iso: string): FcResult {
  const opts = DEFAULT_OPTIONS;
  const dir = `${homedir()}/.claude/fast-compact/${session}`;
  const stamp = iso.replace(/[-:]/g, '').slice(0, 15);
  const t0 = performance.now();
  const p = plan(messages, opts);
  const whole = chooseWhole(p.outputs, undefined, opts, p.cutBefore);
  const cuts: Cut[] = cutsOf(p, whole);
  const pathOf = (cut: Cut): string => {
    const key = cut.kind === 'notice' ? `${stamp}-${cut.key}` : cut.key;
    const safe = key.replace(/[^A-Za-z0-9._-]/g, '_').replace(/^\.+/, '_');
    return `${dir}/${cut.kind}-${safe === key ? safe : `${safe}-${hashOf(key)}`}.txt`;
  };
  const whereOf = (cut: Cut): string => {
    const n = Math.max(1, Math.ceil(cut.original.length / PART_CHARS));
    return n > 1 ? `${pathOf(cut)} (continued in .part2 to .part${n} beside it)` : pathOf(cut);
  };
  const cutMsgs: Message[] = cuts.length > 0 ? applyCuts(messages, cuts, whereOf, opts) : [...messages];
  const after: Message[] = fresh(cutMsgs);
  const ms = performance.now() - t0;
  const beforeChars = sizeOf(messages);
  const afterChars = sizeOf(after);
  const enough = (n: number): boolean => beforeChars - n >= AUTO_MIN_FREED * beforeChars;
  // The hook's three auto checks: most possible freed, freed by the decided cuts without paths, freed with real paths.
  const hookTakesAuto = cuts.length > 0 && enough(beforeChars - mostFreed(messages, opts)) && enough(sizeOf(applyCuts(messages, cuts, () => '', opts))) && enough(afterChars);
  return { cuts, after, ms, beforeChars, afterChars, hookTakesAuto };
}

// ---------------------------------------------------------------- points

interface Tally {
  n: number;
  builtin: number;
  fcCtx: number;
  fcArchive: number;
  fcAny: number;
}

// Purpose: count how many tokens each side kept.
// Usage: tally(tokens, builtinText, fcText, archiveText). A token is kept only if distinctiveTokens() of that text contains it (exact identity).
// Gotchas: "fcArchive" means the text sits in the simulated archive file, not that the model can read it.
export function tally(tokens: string[], builtinText: string, fcText: string, archiveText: string): Tally {
  const t: Tally = { n: tokens.length, builtin: 0, fcCtx: 0, fcArchive: 0, fcAny: 0 };
  const bs: Set<string> = distinctiveTokens(builtinText);
  const cs: Set<string> = distinctiveTokens(fcText);
  const ars: Set<string> = distinctiveTokens(archiveText);
  for (const tok of tokens) {
    const b = bs.has(tok);
    const c = cs.has(tok);
    const a = ars.has(tok);
    if (b) t.builtin++;
    if (c) t.fcCtx++;
    if (a) t.fcArchive++;
    if (c || a) t.fcAny++;
  }
  return t;
}

const median = (xs: number[]): number | null => {
  if (xs.length === 0) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
};

const snippet = (text: string, tok: string): string => {
  const i = text.indexOf(tok);
  if (i < 0) return '(not found)';
  return JSON.stringify(text.slice(Math.max(0, i - 40), i + tok.length + 40));
};

const trace: string[] = [];
let traced = 0;

type Point = Record<string, unknown>;

// One shared replay point for the --dump file: the Before messages, the needed tokens and the built-in outcome.
export interface PointDetail {
  before: Message[];
  neededDirect: string[];
  neededRefetched: string[];
  neededDirectNeverRepeated: string[];
  builtinKept: { direct: boolean[]; refetched: boolean[]; directNeverRepeated: boolean[] };
  ceiling: number;
  thinkingChars: number;
  beforeChars: number;
}
// Filled by processFile, keyed `${session}:${index}`. Read by dumpLine.
export const details = new Map<string, PointDetail>();
type Skip = { session: string; project: string; index: number; reason: string };

// Purpose: evaluate every built-in compaction in one transcript file.
// Usage: processFile(path, project). Returns used points and skipped points (with reasons).
// Gotchas: Before for the 2nd+ compaction starts from the earlier summary plus its preserved messages, as the model saw it.
export function processFile(path: string, project: string): { points: Point[]; skipped: Skip[] } {
  const session = basename(path, '.jsonl');
  const recs = readRecords(path);
  const byUuid = new Map<string, Rec>();
  recs.forEach((r) => r.uuid && byUuid.set(r.uuid, r));
  const posOf = new Map<string, number>();
  recs.forEach((r, i) => r.uuid && posOf.set(r.uuid, i));
  const bounds = recs.flatMap((r, i) => (r.type === 'system' && r.subtype === 'compact_boundary' ? [i] : []));
  const points: Point[] = [];
  const skipped: Skip[] = [];
  const isMsg = (r: Rec): boolean => (r.type === 'user' || r.type === 'assistant') && !r.isSidechain;
  const summaryAfter = (bi: number): number => {
    for (let j = bi + 1; j < Math.min(recs.length, bi + 25); j++) if (recs[j]!.type === 'user' && recs[j]!.isCompactSummary) return j;
    return -1;
  };

  bounds.forEach((bi, k) => {
    const b = recs[bi]!;
    const cm = b.compactMetadata ?? {};
    const skip = (reason: string): void => void skipped.push({ session, project, index: k, reason });
    if (isFcBoundary(session, b.timestamp)) return skip('fc compaction (ledger match), not a built-in one');
    const sumIdx = summaryAfter(bi);
    if (sumIdx < 0) return skip('no summary message after the boundary');
    const summary = recs[sumIdx]!;
    const summaryText = typeof summary.message?.content === 'string' ? summary.message.content : corpusOf(toMessages(summary));

    // Preserved messages: looked up across the whole file (the per-segment reader loses them).
    const refs = cm.preservedMessages?.uuids ?? [];
    const resolved = refs.filter((u) => byUuid.has(u)).length;
    const found = refs.map((u) => byUuid.get(u)).filter((r): r is Rec => !!r && (r.type === 'user' || r.type === 'assistant'));
    found.sort((x, y) => posOf.get(x.uuid!)! - posOf.get(y.uuid!)!);
    const preservedUuids = new Set(refs);
    // System records (for example away_summary) carry words in `content`; they are part of the built-in after text.
    const sysText = refs.map((u) => byUuid.get(u)).filter((r): r is Rec => !!r && r.type === 'system' && typeof r.content === 'string' && r.content.length > 0).map((r) => r.content!);
    const preservedMsgs = found.flatMap(toMessages);

    // Before: what the model held at compaction time = (earlier summary + its preserved messages) + this segment.
    // Gotcha: for some auto compactions logicalParentUuid points at a record AFTER the boundary, so it is used only when it sits before it.
    let leaf: string | null | undefined = b.logicalParentUuid && (posOf.get(b.logicalParentUuid) ?? Infinity) < bi && isMsg(byUuid.get(b.logicalParentUuid)!) ? b.logicalParentUuid : undefined;
    if (!leaf) {
      const lo = k > 0 ? bounds[k - 1]! : -1;
      for (let j = bi - 1; j > lo; j--) if (isMsg(recs[j]!)) { leaf = recs[j]!.uuid; break; }
    }
    const leafPos = leaf ? (posOf.get(leaf) ?? bi) : bi;
    const beforeChain = withSiblingResults(chainBack(byUuid, leaf), recs, posOf, k > 0 ? bounds[k - 1]! : 0, leafPos).filter(isMsg);
    let before: EvalMsg[] = beforeChain.flatMap(toMessages);
    let hasPrevSummary = false;
    let beforeRecs: Rec[] = beforeChain;
    if (k > 0 && beforeChain[0]?.isCompactSummary) {
      hasPrevSummary = true;
      const prev = recs[bounds[k - 1]!]!.compactMetadata?.preservedMessages?.uuids ?? [];
      const inChain = new Set(beforeChain.map((r) => r.uuid));
      const prevRecs = prev.map((u) => byUuid.get(u)).filter((r): r is Rec => !!r && isMsg(r) && !inChain.has(r.uuid!));
      prevRecs.sort((x, y) => posOf.get(x.uuid!)! - posOf.get(y.uuid!)!);
      const head = toMessages(beforeChain[0]!);
      before = [...head, ...prevRecs.flatMap(toMessages), ...beforeChain.slice(1).flatMap(toMessages)];
      beforeRecs = [beforeChain[0]!, ...prevRecs, ...beforeChain.slice(1)];
    }
    if (before.length === 0) return skip('empty Before');

    // Window: the first messages after the summary on the surviving branch, up to WINDOW tool calls.
    const end = k + 1 < bounds.length ? bounds[k + 1]! : recs.length;
    let wLeaf: string | undefined;
    for (let j = end - 1; j > sumIdx; j--) if (isMsg(recs[j]!)) { wLeaf = recs[j]!.uuid; break; }
    const wBack = chainBack(byUuid, wLeaf);
    const at = wBack.findIndex((r) => r.uuid === summary.uuid);
    const wChain = withSiblingResults(wBack, recs, posOf, sumIdx, wLeaf ? (posOf.get(wLeaf) ?? end) : end);
    if (at < 0) return skip('no parent chain from the last message back to the summary');
    // Start after the summary AND after every preserved message; a preserved message is never user supply.
    let startAt = wChain.findIndex((r) => r.uuid === summary.uuid);
    wChain.forEach((r, i) => { if (preservedUuids.has(r.uuid!)) startAt = Math.max(startAt, i); });
    const winAll = wChain.slice(startAt + 1).filter((r) => isMsg(r) && !preservedUuids.has(r.uuid!)).flatMap(toMessages);
    const win: EvalMsg[] = [];
    let winCalls = 0;
    for (const m of winAll) {
      win.push(m);
      winCalls += m.toolUses.length;
      if (winCalls >= WINDOW) break;
    }
    if (!win.some((m) => m.role === 'assistant')) return skip('empty window: no assistant message after the summary');

    // First place each distinctive token shows up in Before, and whether words repeat it later.
    const first = new Map<string, { ch: 'result' | 'text'; idx: number }>();
    const echoed = new Set<string>();
    const seeBefore = (text: string, ch: 'result' | 'text', idx: number): void => {
      for (const t of distinctiveTokens(text) as Set<string>) {
        const f = first.get(t);
        if (!f) first.set(t, { ch, idx });
        else if (ch === 'text' && f.ch === 'result') echoed.add(t);
      }
    };
    before.forEach((m, i) => {
      if (m.text) seeBefore(m.text, 'text', i);
      for (const u of m.toolUses) seeBefore(inputText(u.input), 'text', i);
      for (const r of m.toolResults ?? []) seeBefore(r.text, 'result', i);
    });
    const cand = new Set<string>();
    for (const [t, f] of first) if (f.ch === 'result') cand.add(t);

    // Use in the Window: direct, re-fetched (a Window result carried it first) or user-supplied (excluded).
    const userSeen = new Set<string>();
    const resultSeen = new Set<string>();
    const used = new Map<string, { kind: 'direct' | 'refetched' | 'user'; idx: number }>();
    win.forEach((m, i) => {
      if (m.role === 'user') {
        if (!m.host && m.text) for (const t of distinctiveTokens(m.text) as Set<string>) if (cand.has(t)) userSeen.add(t);
        for (const r of m.toolResults ?? []) for (const t of distinctiveTokens(r.text) as Set<string>) if (cand.has(t)) resultSeen.add(t);
      } else {
        const text = [m.text, ...m.toolUses.map((u) => inputText(u.input))].join('\n');
        for (const t of distinctiveTokens(text) as Set<string>) {
          if (cand.has(t) && !used.has(t)) used.set(t, { kind: userSeen.has(t) ? 'user' : resultSeen.has(t) ? 'refetched' : 'direct', idx: i });
        }
      }
    });
    const directToks = [...used].filter(([, u]) => u.kind === 'direct').map(([t]) => t);
    const refetchedToks = [...used].filter(([, u]) => u.kind === 'refetched').map(([t]) => t);
    const userSuppliedExcluded = [...used].filter(([, u]) => u.kind === 'user').length;

    // Repeat work: Window calls that repeat a Before Read path or Bash command.
    const seenCalls = new Set<string>();
    const callKey = (tool: string, input: Record<string, unknown>): string | null =>
      tool === 'Read' && typeof input.file_path === 'string' ? `R:${input.file_path}` : tool === 'Bash' && typeof input.command === 'string' ? `B:${input.command}` : null;
    for (const m of before) for (const u of m.toolUses) { const key = callKey(u.tool, u.input); if (key) seenCalls.add(key); }
    let repeatCalls = 0;
    let windowCalls = 0;
    for (const m of win) for (const u of m.toolUses) {
      windowCalls++;
      const key = callKey(u.tool, u.input);
      if (key && seenCalls.has(key)) repeatCalls++;
    }

    // Built-in after, and the fast-compact run.
    const builtinAfter = [summaryText, corpusOf(preservedMsgs), ...sysText].join('\n');
    const iso = b.timestamp ?? new Date(0).toISOString();
    const runs = [fcRun(before, session, iso), fcRun(before, session, iso), fcRun(before, session, iso)];
    const fc = runs[0]!;
    const fcMs = median(runs.map((r) => r.ms))!;
    const fcText = corpusOf(fc.after);
    const archiveText = fc.cuts.map((c) => c.original).join('\n');
    const preTokens = cm.preTokens ?? 0;
    const fcEstTokensScaled = fc.beforeChars > 0 ? Math.round((preTokens * fc.afterChars) / fc.beforeChars) : 0;
    const echoFree = directToks.filter((t) => !echoed.has(t));
    const sets = {
      all: tally([...directToks, ...refetchedToks], builtinAfter, fcText, archiveText),
      direct: tally(directToks, builtinAfter, fcText, archiveText),
      refetched: tally(refetchedToks, builtinAfter, fcText, archiveText),
      directResultOnly: tally(echoFree, builtinAfter, fcText, archiveText),
    };
    const point: Point = {
      session,
      project,
      index: k,
      time: b.timestamp ?? null,
      trigger: cm.trigger ?? null,
      preTokens,
      postTokens: cm.postTokens ?? null,
      durationMs: cm.durationMs ?? null,
      beforeMessages: before.length,
      beforeHasPrevSummary: k === 0 ? null : hasPrevSummary,
      preservedRefs: refs.length,
      preservedResolved: resolved,
      preservedWithText: found.length + sysText.length,
      preservedSystemText: sysText.length,
      fcBeforeChars: fc.beforeChars,
      fcAfterChars: fc.afterChars,
      fcCuts: fc.cuts.length,
      fcEstTokensAfter: fcEstTokensScaled,
      builtinAfterChars: builtinAfter.length,
      builtinAfterEstTokens: estimateTokens(builtinAfter),
      fcBeforeEstTokens: estimateTokens(corpusOf(before)),
      beforeCoverage: preTokens > 0 ? estimateTokens(corpusOf(before)) / preTokens : null,
      fcAfterEstTokens: estimateTokens(fcText),
      fcCutMs: Math.round(fcMs * 10) / 10,
      fcFreedShare: fc.beforeChars > 0 ? (fc.beforeChars - fc.afterChars) / fc.beforeChars : 0,
      hookTakesAuto: fc.hookTakesAuto,
      needed: sets.all.n,
      neededDirect: sets.direct.n,
      refetched: sets.refetched.n,
      userSuppliedExcluded,
      builtinKept: sets.all.builtin,
      fcKept: sets.all.fcCtx,
      fcInArchive: sets.all.fcArchive,
      fcKeptOrArchive: sets.all.fcAny,
      ...Object.fromEntries(Object.entries(sets).map(([name, t]) => [`t_${name}`, t])),
      repeatCalls,
      windowCalls,
      windowMessages: win.length,
    };
    points.push(point);
    const bs = distinctiveTokens(builtinAfter) as Set<string>;
    let thinkingChars = 0;
    for (const r of beforeRecs) if (r.type === 'assistant' && Array.isArray(r.message?.content)) for (const blk of r.message!.content as Block[]) if (blk.type === 'thinking' && blk.thinking) thinkingChars += blk.thinking.length;
    let toolChars = 0;
    for (const m of before.slice(1)) {
      for (const u of m.toolUses) toolChars += JSON.stringify(u.input).length;
      for (const r of m.toolResults ?? []) toolChars += r.text.length;
    }
    details.set(`${session}:${k}`, {
      before: before.map(({ role, text, toolUses, toolResults }) => (toolResults ? { role, text, toolUses, toolResults } : { role, text, toolUses })),
      neededDirect: directToks,
      neededRefetched: refetchedToks,
      neededDirectNeverRepeated: echoFree,
      builtinKept: { direct: directToks.map((t) => bs.has(t)), refetched: refetchedToks.map((t) => bs.has(t)), directNeverRepeated: echoFree.map((t) => bs.has(t)) },
      ceiling: fc.beforeChars > 0 ? toolChars / fc.beforeChars : 0,
      thinkingChars,
      beforeChars: fc.beforeChars,
    });

    if (TRACE > 0 && traced < TRACE && directToks.length >= 3) {
      traced++;
      const pick = [directToks[0]!, directToks[directToks.length >> 1]!, directToks[directToks.length - 1]!];
      trace.push(`=== TRACE point ${traced}: session ${session.slice(0, 8)} compaction #${k} (${cm.trigger}), Before ${before.length} messages, fc after ${fc.after.length} messages ===`);
      for (const tok of pick) {
        const f = first.get(tok)!;
        const u = used.get(tok)!;
        const um = win[u.idx]!;
        const beforeMsg = before[f.idx]!;
        const beforeText = (beforeMsg.toolResults ?? []).map((r) => r.text).join('\n') + beforeMsg.text;
        const fi = fc.after.findIndex((m) => (distinctiveTokens(corpusOf([m])) as Set<string>).has(tok));
        trace.push(`TOKEN ${JSON.stringify(tok)}`);
        trace.push(`  Before: first seen in a tool result, message ${f.idx}/${before.length}: ${snippet(beforeText, tok)}`);
        trace.push(`  Window: assistant uses it in window message ${u.idx}: ${snippet(corpusOf([um]), tok)}`);
        trace.push(`  Built-in summary: ${(distinctiveTokens(builtinAfter) as Set<string>).has(tok) ? 'KEPT at char ' + builtinAfter.indexOf(tok) + ' ' + snippet(builtinAfter, tok) : 'absent'}`);
        trace.push(`  fc-after messages: ${fi >= 0 ? 'KEPT in message ' + fi + '/' + fc.after.length + ' ' + snippet(corpusOf([fc.after[fi]!]), tok) : 'absent from context'}; in simulated archive: ${(distinctiveTokens(archiveText) as Set<string>).has(tok) ? 'yes' : 'no'}`);
      }
    }
  });
  return { points, skipped };
}

// ---------------------------------------------------------------- summary

// Purpose: list main-session transcript files under the projects root.
// Usage: listFiles(root). Skips agent-*.jsonl (subagents) and anything below the project folder.
// Gotchas: read only. Files still being written are included; a torn last line is tolerated.
export function listFiles(root: string): { path: string; project: string }[] {
  const out: { path: string; project: string }[] = [];
  for (const project of readdirSync(root)) {
    let files: string[];
    try { files = readdirSync(join(root, project)); } catch { continue; }
    for (const f of files) if (f.endsWith('.jsonl') && !f.startsWith('agent-')) out.push({ path: join(root, project, f), project });
  }
  return out.sort((a, b) => a.path.localeCompare(b.path));
}

const pct = (x: number | null): string => (x === null ? 'n/a' : `${(100 * x).toFixed(1)}%`);
const num = (x: number | null, d = 0): string => (x === null ? 'n/a' : x.toLocaleString('en-US', { maximumFractionDigits: d }));
const sum = (xs: number[]): number => xs.reduce((a, b) => a + b, 0);

// Purpose: one markdown table of survival shares for a group of points.
// Usage: survivalTable(points). Pooled share = sum of kept / sum of tokens; median = middle point share.
// Gotchas: medians use only points that have at least one token in that class.
function survivalTable(pts: Point[]): string {
  const rows = ['| Token class | Points | Tokens | Built-in kept | fc in context | fc in archive only* | fc context or archive | Median per point: built-in / fc context / fc any |', '|---|---|---|---|---|---|---|---|'];
  const names: [string, string][] = [['direct', 'Used directly (no re-fetch)'], ['refetched', 'Re-fetched in the window'], ['directResultOnly', 'Direct, never repeated in words before']];
  for (const [key, label] of names) {
    const ts = pts.map((p) => p[`t_${key}`] as Tally).filter((t) => t.n > 0);
    const n = sum(ts.map((t) => t.n));
    const share = (f: (t: Tally) => number): number | null => (n ? sum(ts.map(f)) / n : null);
    const med = (f: (t: Tally) => number): string => pct(median(ts.map((t) => f(t) / t.n)));
    const archOnly = n ? (sum(ts.map((t) => t.fcAny)) - sum(ts.map((t) => t.fcCtx))) / n : null;
    rows.push(`| ${label} | ${ts.length} | ${n} | ${pct(share((t) => t.builtin))} | ${pct(share((t) => t.fcCtx))} | ${pct(archOnly)} | ${pct(share((t) => t.fcAny))} | ${med((t) => t.builtin)} / ${med((t) => t.fcCtx)} / ${med((t) => t.fcAny)} |`);
  }
  return rows.join('\n');
}

// Purpose: build the whole summary markdown from used and skipped points.
// Usage: summarize(points, skipped, totalFound). Splits all / auto / manual.
// Gotchas: medians describe, they do not prove which method is better; the Limits list says why.
export function summarize(points: Point[], skipped: Skip[], found: number): string {
  const L: string[] = [];
  const n = (p: Point, k: string): number => (p[k] as number | null) ?? 0;
  const groups: [string, Point[]][] = [['All triggers', points], ['Auto', points.filter((p) => p.trigger === 'auto')], ['Manual', points.filter((p) => p.trigger === 'manual')]];
  L.push('# Backtest summary: built-in compaction vs fast-compact (/fc)', '');
  L.push(`Run: ${new Date().toISOString()}. Transcripts: \`${ROOT}\`. fast-compact: \`${FC}\`. Window: ${WINDOW} tool calls. fc setting: DEFAULT_OPTIONS, no Jev, newest outputs kept whole.`, '');
  L.push('## Points', '');
  L.push(`- Built-in compactions found: ${found}. Used: ${points.length}. Skipped: ${skipped.length}. Auto: ${groups[1]![1].length}. Manual: ${groups[2]![1].length}.`);
  if (skipped.length) { L.push('', '| Session | Project | Compaction # | Reason |', '|---|---|---|---|'); for (const s of skipped) L.push(`| ${s.session.slice(0, 8)} | ${s.project} | ${s.index} | ${s.reason} |`); }
  const refs = sum(points.map((p) => n(p, 'preservedRefs')));
  const res = sum(points.map((p) => n(p, 'preservedResolved')));
  const withText = sum(points.map((p) => n(p, 'preservedWithText')));
  L.push('', `- Preserved-message references: ${refs}; found by whole-file lookup: ${res} (${pct(refs ? res / refs : null)}); unresolved: ${refs - res}. Of the found ones, ${withText} carry words (user or assistant messages, plus ${sum(points.map((p) => n(p, 'preservedSystemText')))} system records with text, all included in built-in after). The rest are system records with no text (hook summaries, turn timers).`);
  L.push(`- Rebuilt Before as a share of the measured preTokens (median): ${pct(median(points.map((p) => (p.beforeCoverage as number | null) ?? 0)))}. The rest is system prompt, tool list, thinking and host attachments that the transcript does not hold as text.`);
  const bad = points.filter((p) => n(p, 'fcAfterChars') >= n(p, 'fcBeforeChars'));
  L.push(`- Points where fc-after is NOT smaller than before: ${bad.length} of ${points.length}${bad.length ? ' (fc found nothing to cut; the hook would skip)' : ''}.`);
  const noPrev = points.filter((p) => p.beforeHasPrevSummary === false).length;
  L.push(`- Points after the first compaction in a file whose Before did not start from the earlier summary: ${noPrev}.`);
  L.push('', '## What the assistant used after the compaction (descriptive only)', '');
  L.push('A "token" is a path, number or id of 8+ characters that first appeared in a tool result before the compaction and that the assistant then used in its words or tool inputs in the window. The built-in outcome shaped what the assistant did next, so this replay describes, it does not prove.', '');
  for (const [name, pts] of groups) { L.push(`### ${name}`, '', survivalTable(pts), ''); }
  L.push('*"fc in archive only" = text that fc cut from context but saved to a file. The model must spend a tool call to read it, so it is not the same as kept.', '');
  const tot = (pts: Point[], k: string): number => sum(pts.map((p) => n(p, k)));
  L.push('## Re-fetch rate after built-in compaction', '');
  for (const [name, pts] of groups) {
    const d = tot(pts, 'neededDirect'), r = tot(pts, 'refetched');
    L.push(`- ${name}: re-fetched ${r} of ${d + r} used tokens (${pct(d + r ? r / (d + r) : null)}). Direct: ${d}. Tokens dropped because the person supplied them again: ${tot(pts, 'userSuppliedExcluded')}.`);
  }
  L.push('', '## Repeat work after the built-in compaction', '');
  for (const [name, pts] of groups) {
    const rc = tot(pts, 'repeatCalls'), wc = tot(pts, 'windowCalls');
    L.push(`- ${name}: ${rc} of ${wc} window tool calls repeat a Before Read path or Bash command (${pct(wc ? rc / wc : null)}). Median per point: ${pct(median(pts.filter((p) => n(p, 'windowCalls') > 0).map((p) => n(p, 'repeatCalls') / n(p, 'windowCalls'))))}.`);
  }
  L.push('', '## Context left after', '');
  L.push('Same units on both sides: "est tokens" uses fast-compact\'s own estimateTokens on the message text only. "postTokens" is the measured number that Claude Code recorded (it also counts system prompt and tools). "fc scaled" = preTokens x fc after chars / fc before chars (the spec formula).', '');
  L.push('| Group | Points | Built-in postTokens (median) | Built-in est tokens (median) | fc est tokens (median) | fc scaled tokens (median) | Before est tokens (median) | fc frees (median) | fc frees under 20% (hook would fall back) |', '|---|---|---|---|---|---|---|---|---|');
  for (const [name, pts] of groups) {
    const under = pts.filter((p) => !(p.hookTakesAuto as boolean)).length;
    L.push(`| ${name} | ${pts.length} | ${num(median(pts.map((p) => n(p, 'postTokens'))))} | ${num(median(pts.map((p) => n(p, 'builtinAfterEstTokens'))))} | ${num(median(pts.map((p) => n(p, 'fcAfterEstTokens'))))} | ${num(median(pts.map((p) => n(p, 'fcEstTokensAfter'))))} | ${num(median(pts.map((p) => n(p, 'fcBeforeEstTokens'))))} | ${pct(median(pts.map((p) => n(p, 'fcFreedShare'))))} | ${under} of ${pts.length} (${pct(pts.length ? under / pts.length : null)}) |`);
  }
  L.push('', 'Chars: median Before chars / fc after chars / built-in after chars: ' + `${num(median(points.map((p) => n(p, 'fcBeforeChars'))))} / ${num(median(points.map((p) => n(p, 'fcAfterChars'))))} / ${num(median(points.map((p) => n(p, 'builtinAfterChars'))))}.`);
  L.push('', '## Time', '');
  for (const [name, pts] of groups) {
    L.push(`- ${name}: built-in durationMs median ${num((median(pts.map((p) => n(p, 'durationMs')).filter((x) => x > 0)) ?? 0) / 1000, 1)} s; fc cut-only median ${num(median(pts.map((p) => n(p, 'fcCutMs'))), 1)} ms, max ${num(Math.max(0, ...pts.map((p) => n(p, 'fcCutMs'))), 1)} ms.`);
  }
  L.push('- fc time is the cut only (plan, choose, cut, apply, merge), median of 3 runs on this machine. It leaves out archive file writes, host overhead and any Jev call (none here). The real /fc is slower than this number by those parts.');
  L.push('', '## Limits', '');
  for (const s of [
    'The token label is a proxy for "the session needed this". It misses needs that are not a path, number or id.',
    'Tokens the built-in summary lost and the session never used again are invisible here.',
    'The built-in outcome shaped what the assistant did next. A better summary may have changed which tokens it used. The replay is descriptive.',
    'fc kept-in-context counts a token that fc left whole or kept at the start or end of a cut output, plus every word of the person and the assistant. A token the assistant already wrote in its own words survives fc by default; the "never repeated in words" row removes that effect.',
    'fc "context or archive" is near 100% by construction: every tool result is either in context (whole or head and tail) or saved in the archive. Reaching the archive costs the model a tool call, so judge fc on the "in context" column.',
    'Kept means exact token identity: distinctiveTokens() of the after-text must contain the token, on both sides. A longer or shortened path does not count.',
    'Built-in after = summary + preserved messages only. fc after = whole conversation with cuts. Neither includes the system prompt or tools.',
    'fc is run without Jev, so it keeps the newest outputs whole. Real /fc with Jev may keep different outputs.',
    'The window is the next 40 tool calls on the surviving branch. A short or rewound branch gives a small window.',
    'Repeat-work only checks Read paths and Bash commands that also appear in Before. A repeat can be legitimate (the file changed).',
    'Before is rebuilt from the transcript, not captured from the hook. Host notices and command echoes may differ from what the hook really sees.',
    `The sample is small: ${points.length} points in ${new Set(points.map((p) => p.session)).size} sessions, mostly manual compactions by one person.`,
  ]) L.push(`- ${s}`);
  return L.join('\n') + '\n';
}

export interface ScoreInput {
  neededDirect: string[];
  neededRefetched: string[];
  neededDirectNeverRepeated: string[];
}
export interface ClassScore {
  n: number;
  kept: number;
}
export interface AfterScore {
  direct: ClassScore;
  refetched: ClassScore;
  directNeverRepeated: ClassScore;
  afterChars: number;
  afterEstTokens: number;
}

// Purpose: score any compactor's output on one point: how many needed tokens stay in context.
// Usage: scoreAfter(point, afterMessages). Point needs the three needed-token lists (a dump line works). Returns n and kept per class, plus after chars and estimated tokens.
// Gotchas: same rule as the backtest: a token is kept only if distinctiveTokens() of the after text holds it exactly. Context only; an archive file does not count.
export function scoreAfter(point: ScoreInput, afterMessages: readonly Message[]): AfterScore {
  const text = corpusOf(afterMessages);
  const have: Set<string> = distinctiveTokens(text);
  const score = (toks: string[]): ClassScore => ({ n: toks.length, kept: toks.filter((t) => have.has(t)).length });
  return {
    direct: score(point.neededDirect),
    refetched: score(point.neededRefetched),
    directNeverRepeated: score(point.neededDirectNeverRepeated),
    afterChars: sizeOf(afterMessages),
    afterEstTokens: estimateTokens(text),
  };
}

// Purpose: turn one used point into one --dump line.
// Usage: dumpLine(point). Needs processFile to have run, so details holds the point.
// Gotchas: the line holds raw transcript text and may hold secrets. Keep the file in out/ (gitignored) and never copy it.
export function dumpLine(p: Point): string {
  const d = details.get(`${p.session}:${p.index}`)!;
  return JSON.stringify({
    id: `${(p.session as string).slice(0, 8)}-${p.index}`,
    session: p.session,
    project: p.project,
    index: p.index,
    trigger: p.trigger,
    preTokens: p.preTokens,
    postTokens: p.postTokens,
    durationMs: p.durationMs,
    before: d.before,
    neededDirect: d.neededDirect,
    neededRefetched: d.neededRefetched,
    neededDirectNeverRepeated: d.neededDirectNeverRepeated,
    builtinKept: d.builtinKept,
    ceiling: d.ceiling,
    thinkingChars: d.thinkingChars,
    beforeChars: d.beforeChars,
  });
}

// Purpose: run the whole backtest and write the output files.
// Usage: bun backtest.ts. Prints a one-line progress per file and the paths written.
// Gotchas: out/ is created if missing; nothing is written under the transcripts root.
function main(): void {
  mkdirSync(OUT, { recursive: true });
  const files = listFiles(ROOT);
  const points: Point[] = [];
  const skipped: Skip[] = [];
  let found = 0;
  for (const f of files) {
    const text = readFileSync(f.path, 'utf8');
    if (!text.includes('"compact_boundary"')) continue;
    const r = processFile(f.path, f.project);
    found += r.points.length + r.skipped.length;
    points.push(...r.points);
    skipped.push(...r.skipped);
    console.log(`${basename(f.path).slice(0, 8)} ${f.project}: used ${r.points.length}, skipped ${r.skipped.length}`);
  }
  writeFileSync(join(OUT, 'backtest-points.jsonl'), points.map((p) => JSON.stringify(p)).join('\n') + '\n');
  writeFileSync(join(OUT, 'backtest-summary.md'), summarize(points, skipped, found));
  if (trace.length) { writeFileSync(join(OUT, 'backtest-trace.txt'), trace.join('\n') + '\n'); console.log(trace.join('\n')); }
  console.log(`found ${found}, used ${points.length}, skipped ${skipped.length}`);
  console.log(`wrote ${join(OUT, 'backtest-points.jsonl')} and ${join(OUT, 'backtest-summary.md')}`);
  const dump = flag('--dump', '');
  if (dump) {
    mkdirSync(dirname(resolve(dump)), { recursive: true });
    writeFileSync(resolve(dump), points.map(dumpLine).join('\n') + '\n');
    console.log(`dumped ${points.length} points to ${resolve(dump)}`);
  }
}

if (import.meta.main) {
  if (!existsSync(ROOT)) throw new Error(`transcripts root not found: ${ROOT}`);
  main();
}

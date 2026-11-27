/**
 * The Claude Code side of fast-compact: `/fast-compact` (and `/fc`) cut old
 * tool output down to its start and end, Jev (when a key is set and
 * `provider` is not `none`) choosing which outputs stay whole, and save
 * everything cut to a file named in its place. Claude Code's own `/compact` is
 * left alone: this module's `session.compact` hook acts on the compaction its
 * own command asked for, and never hands that one to the built-in summary.
 * Auto-compaction is left alone too, unless `autoCompact` is on: then it is cut
 * the same way when that frees enough, and summarised by Claude Code
 * otherwise. Unless `meter` is off, what /fc would free is shown after each
 * turn.
 */
import type { EngineInterface, PluginOptions, Register } from 'claude-code';
import { applyCuts, decide, estimate, fresh, freshBatches, mostFreed, sizeOf, type Decision, type Estimate, type JevAccess } from '../src/compact.js';
import { DEFAULT_MODEL, ENDPOINTS, type Provider } from '../src/jev.js';
import { estimateTokens } from '../src/state.js';
import { DEFAULT_OPTIONS, type Cut, type Message, type Options } from '../src/types.js';
import { deepen, expand, hardOptions, header, liveMessages, render, renderedSize, replayedPath } from '../src/replay.js';

/** Where the meter shows what /fc would free: nowhere, a line under the prompt, a file a status line reads, or both. */
type Meter = 'off' | 'prompt' | 'statusline' | 'both';

/** How /fc frees the context: the compact hook, a clear plus a replayed prompt, or whichever fits this machine. */
type Route = 'auto' | 'hook' | 'replay';

interface Settings {
  options: Options;
  /** `none` never asks Jev, even with a key set: the newest outputs are kept whole and nothing is sent. */
  provider: Provider | 'none';
  /** Why `provider` is `none` when it was not set to it: a value this plugin does not know. */
  providerNote?: string;
  url: string;
  model: string;
  apiKey?: string;
  autoCompact: boolean;
  meter: Meter;
  route: Route;
}

function numberOption(options: PluginOptions, key: string, fallback: number): number {
  const value = options[key];
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function booleanOption(options: PluginOptions, key: string, fallback: boolean): boolean {
  const value = options[key];
  return typeof value === 'boolean' ? value : fallback;
}

function stringOption(options: PluginOptions, key: string): string | undefined {
  const value = options[key];
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : undefined;
}

export function settingsOf(options: PluginOptions): Settings {
  // Anything but a known provider sends nothing: a mistyped `none` must not reach OpenRouter.
  const named = stringOption(options, 'provider')?.toLowerCase();
  const provider = named === undefined || named === 'openrouter' ? 'openrouter' : named === 'typesafe' ? 'typesafe' : 'none';
  const meter = stringOption(options, 'meter')?.toLowerCase();
  const route = stringOption(options, 'route')?.toLowerCase();
  const d = DEFAULT_OPTIONS;
  return {
    provider,
    providerNote: provider === 'none' && named !== 'none' && named !== 'off' ? `unknown provider "${named}"` : undefined,
    url: stringOption(options, 'baseUrl') ?? (provider === 'none' ? '' : ENDPOINTS[provider]),
    model: stringOption(options, 'model') ?? DEFAULT_MODEL,
    apiKey: stringOption(options, 'apiKey'),
    autoCompact: booleanOption(options, 'autoCompact', false),
    meter: meter === 'off' || meter === 'statusline' || meter === 'both' ? meter : 'prompt',
    route: route === 'hook' || route === 'replay' ? route : 'auto',
    options: {
      ...d,
      keepRecentCalls: Math.max(0, Math.floor(numberOption(options, 'keepRecentCalls', d.keepRecentCalls))),
      cutTo: Math.max(200, Math.floor(numberOption(options, 'cutTo', d.cutTo))),
      keepWhole: Math.min(1, Math.max(0, numberOption(options, 'keepWhole', d.keepWhole))),
      minKeepScore: Math.min(1, Math.max(0, numberOption(options, 'minKeepScore', d.minKeepScore))),
      cutInputs: booleanOption(options, 'cutInputs', d.cutInputs),
      sendSamples: booleanOption(options, 'sendSamples', d.sendSamples),
      resumeSafe: booleanOption(options, 'resumeSafe', d.resumeSafe),
    },
  };
}

function pct(part: number, whole: number): string {
  return whole === 0 ? '0%' : `${Math.round((100 * part) / whole)}%`;
}

function kchars(n: number): string {
  return n >= 10_000 ? `${Math.round(n / 1000)}k` : `${(n / 1000).toFixed(1)}k`;
}

/** The one-line account the person sees under the command. */
export function reportOf(decision: Decision, before: number, after: number, cuts: readonly Cut[], dir: string): string {
  const count = (kind: Cut['kind']): number => cuts.filter((c) => c.kind === kind).length;
  const cut = (kind: Cut['kind']): string => `${count(kind)} ${kind}${count(kind) === 1 ? '' : 's'} cut`;
  const parts = [
    cut('output'),
    decision.whole.size > 0
      ? `${decision.whole.size} kept whole ${decision.ranking === 'jev' ? 'on Jev’s ranking' : 'as the newest'}`
      : '',
    count('input') > 0 ? cut('input') : '',
    count('notice') > 0 ? cut('notice') : '',
  ].filter(Boolean);
  const jev = decision.jev
    ? `Jev ${decision.jev.model || 'answered'}: ${decision.jev.requests} request${decision.jev.requests === 1 ? '' : 's'}, ${(decision.jev.ms / 1000).toFixed(1)} s, $${decision.jev.cost.toFixed(4)}`
    : `no Jev (${decision.jevSkipped ?? 'not asked'}), newest kept whole`;
  return `${kchars(before)} → ${kchars(after)} chars (−${pct(before - after, before)}); ${parts.join(', ')}; ${jev}. Full text of every cut: ${dir}/`;
}

/**
 * The instructions the scheduled `/compact` carries. A main-conversation
 * compaction whose instructions start with it is this plugin's, whatever else
 * is pending: it is answered here, never handed to the built-in summary.
 */
export const MARKER = '[fast-compact]';

export function markerOf(focus: string): string {
  return focus ? `${MARKER} ${focus}` : MARKER;
}

/** The focus a marked compaction carries ('' for none), or undefined for one that is not marked. */
export function focusOf(instructions: string | undefined): string | undefined {
  const text = instructions?.trimStart() ?? '';
  return text.startsWith(MARKER) ? text.slice(MARKER.length).trim() : undefined;
}

/** A /fc whose /compact has not settled holds off another; one stuck this long is let go. */
const STUCK_MS = 120_000;
/** The longest one Jev request may wait, and what is kept back of the hook's 10 s budget. */
const JEV_WAIT_MS = 6_000;
const BUDGET_RESERVE_MS = 2_500;
/**
 * Claude Code's security plugin seats itself first, and skips plugin compact hooks, on a machine
 * with this file; route `auto` replays there.
 */
const MANAGED_SETTINGS = '/Library/Application Support/ClaudeCode/managed-settings.json';
/** The replay route's time for the trim step: Jev gets this less BUDGET_RESERVE_MS (3 s), so /fc stays near 10 s. */
const REPLAY_BUDGET_MS = 5_500;
/** $.session.messages() returns at most this many entries; a chat that fills it may have lost its oldest part. */
const MESSAGES_CAP = 4096;
/**
 * The start-up block (system prompt, tools, memory files) a fresh chat loads anyway, in tokens; measured
 * 35.7k to 74.6k on this Mac. The snapshot check compares the chat's messages with the context above it.
 */
const STARTUP_TOKENS = 40_000;
/**
 * The messages /fc reads must cover at least this share of the context above the start-up block, or
 * the read may have missed part of the chat. Message text is about 56% of it at compaction (thinking
 * and attachments are the rest), so this leaves room for chats heavy in either.
 */
const SNAPSHOT_MIN_SHARE = 0.3;
/** A replay goes ahead only when its text is at most this share of the chat it replaces. */
const REPLAY_MIN_LEFT = 0.85;
/** Archive files pass 3 writes at once. */
const WRITE_BATCH = 16;
/** The harder passes run while the replay is still above this share of the chat. */
const DEEPEN_ABOVE = 0.6;
/** Refuse a replay whose prompt would fill more than this share of the context window. */
const REPLAY_MAX_SHARE = 0.8;
/** Characters per archive file: at most 3 MB of UTF-8 whatever the text (the host refuses writes over 4 MiB). */
const PART_CHARS = 1_000_000;

/** A short, stable hash of `text` (FNV-1a, 8 hex digits). */
function hashOf(text: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 0x01000193);
  return (h >>> 0).toString(16).padStart(8, '0');
}

/** `text` in pieces of at most `size` characters, never splitting a surrogate pair. */
function parts(text: string, size: number): string[] {
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

/**
 * Purpose: read back messages saved in parts (`path`, then `path.part2`, ...) and parse them.
 * Usage: await readParts($, savedJsonPath).
 * Gotchas: stops at the first missing part; a parse error throws, so the caller refuses to clear.
 */
async function readParts($: EngineInterface, path: string): Promise<Message[]> {
  let text = await $.fs.read(path);
  for (let i = 2; await $.fs.exists(`${path}.part${i}`); i++) text += await $.fs.read(`${path}.part${i}`);
  return JSON.parse(text) as Message[];
}

/**
 * An auto-compaction is answered with cuts only when they free at least this
 * share of the conversation: with less, the context stays near Claude Code's
 * threshold and it would compact again a few turns later, so its summary runs.
 */
const AUTO_MIN_FREED = 0.2;
/** Under this many tokens, the meter shows nothing. */
const METER_MIN_TOKENS = 2_000;
/** The meter's line says how to hide it this many times a session, then drops the hint. */
const METER_HINTS = 3;

/** Whether this is the main conversation's auto-compaction, and `autoCompact` gives it to this plugin. */
function takesAuto(settings: Settings, e: { trigger: string; agentId?: string }): boolean {
  return settings.autoCompact && e.trigger === 'auto' && !e.agentId;
}

/** What the log says when the compaction /fc scheduled never reached this plugin, after which /fc is off for the session. */
export const MISSED =
  'the compaction did not reach fast-compact, so Claude Code ran its own /compact instead and nothing was cut by this plugin. ' +
  'Where an organization manages Claude Code, plugins you install yourself get no compaction hooks; /fc is off for this session.';

/** The meter's line under the prompt, kept short: what /fc would free, its share of the window, and (with `hint`) how to hide it. */
export function meterLine(freed: Estimate, window?: number, hint = true): string {
  const share = window ? Math.round((100 * freed.tokens) / window) : 0;
  return `/fc frees ~${kchars(freed.tokens)} tokens${share > 0 ? ` (${share}%)` : ''}${hint ? ' · hide: /plugin configure fast-compact → meter' : ''}`;
}

/**
 * Shows what /fc would free (`freed` undefined clears it): a line under the
 * prompt, the token count in ~/.claude/fast-compact/meter/<session id> for a
 * status line command to read, or both.
 */
// ponytail: one small meter file per session, never deleted ($.fs has no delete)
async function showMeter($: EngineInterface, meter: Meter, freed: Estimate | undefined, window?: number, hint?: boolean): Promise<void> {
  try {
    if (meter === 'prompt' || meter === 'both') {
      $.ui.status(freed ? meterLine(freed, window, hint) : undefined);
    }
    if (meter === 'statusline' || meter === 'both') {
      const home = (await $.env.get('HOME')) ?? '';
      await $.fs.write(`${home}/.claude/fast-compact/meter/${await $.session.id()}`, freed ? String(freed.tokens) : '');
    }
  } catch {
    // the meter is a convenience; it never gets in the way of the session
  }
}

/** What the shared trim step decided: hand the event on, skip with a reason, or the trimmed messages. */
type Trimmed =
  | { kind: 'pass' }
  | { kind: 'skip'; why: string; report: string }
  | { kind: 'done'; compacted: Message[]; report: string; dir: string; stamp: string };

/**
 * Purpose: the one trim step both routes use: find the Jev key, ask Jev, save every cut's full text, apply the cuts, log the ledger.
 * Usage: trim($, settings, messages, focus, left, 'fc' | 'auto' | 'replay'); `left` returns the milliseconds still allowed.
 * Gotchas: the hook passes its 10 s budget as `left` ($.clock.sleep counts against it, $.http.fetch does not), so Jev's waits
 * are sized from what is left, keeping a reserve for the archive writes; running short only means ranking newest first.
 * 'pass' happens only for 'auto' (the summary should run instead).
 */
async function trim(
  $: EngineInterface,
  settings: Settings,
  messages: readonly Message[],
  focus: string,
  left: () => number,
  trigger: 'fc' | 'auto' | 'replay',
): Promise<Trimmed> {

  const home = (await $.env.get('HOME')) ?? '';
  const sessionId = await $.session.id();
const auto = trigger === 'auto';
  const dir = `${home}/.claude/fast-compact/${sessionId}`;
  const now = new Date(await $.clock.now()).toISOString();
  const stamp = now.replace(/[-:]/g, '').slice(0, 15);

  const off = settings.provider === 'none';
  let apiKey = off ? undefined : settings.apiKey;
  if (!apiKey && !off) {
    apiKey =
      settings.provider === 'typesafe'
        ? await $.env.get('TYPESAFE_API_KEY')
        : await $.env.get('OPENROUTER_API_KEY');
  }
  if (!apiKey && !off) {
    const env = (await $.settings.read())['env'];
    const name = settings.provider === 'typesafe' ? 'TYPESAFE_API_KEY' : 'OPENROUTER_API_KEY';
    const value = env && typeof env === 'object' ? (env as Record<string, unknown>)[name] : undefined;
    if (typeof value === 'string' && value) apiKey = value;
  }
  const jev: JevAccess | undefined = apiKey
    ? {
        config: { url: settings.url, apiKey, model: settings.model },
        now: () => $.clock.now(),
        transport: {
          post: async (url, headers, body) => {
            const wait = Math.min(JEV_WAIT_MS, left() - BUDGET_RESERVE_MS);
            if (wait < 1000) throw new Error('no time left in the hook budget');
            const stop = new AbortController();
            const timedOut = { status: 0, text: '' };
            try {
              const answer = await Promise.race([
                $.http.fetch(url, { method: 'POST', headers, body }).then((r) => ({ status: r.status, text: r.text })),
                $.clock.sleep(wait, { signal: stop.signal }).then(
                  () => timedOut,
                  () => timedOut,
                ),
              ]);
              if (answer === timedOut) throw new Error(`no answer in ${(wait / 1000).toFixed(1)} s`);
              return answer;
            } finally {
              stop.abort();
            }
          },
          sleep: (ms) => $.clock.sleep(Math.max(0, Math.min(ms, left() - BUDGET_RESERVE_MS - 1000))),
        },
      }
    : undefined;

  const before = sizeOf(messages);
  const enough = (after: number): boolean => before - after >= AUTO_MIN_FREED * before;
  // An auto-compaction that even cutting everything would not shrink enough goes to the summary before Jev is asked.
  if (auto && !enough(before - mostFreed(messages, settings.options))) return { kind: 'pass' };
  const decision = await decide(messages, settings.options, off ? (settings.providerNote ?? 'provider none') : jev, focus || undefined);
  // An auto-compaction the cuts would not shrink enough goes to Claude Code's summary.
  if (auto && !enough(sizeOf(applyCuts(messages, decision.cuts, () => '', settings.options)))) return { kind: 'pass' };
  // A replay with nothing to cut can still free space (it drops what came before the last compaction
  // summary); its own size check decides whether to go ahead.
  if (decision.cuts.length === 0 && trigger === 'replay') {
    return { kind: 'done', compacted: settings.options.resumeSafe ? fresh(messages) : [...messages], report: 'no tool output left to cut;', dir, stamp };
  }
  if (decision.cuts.length === 0) {
    const why = `nothing old enough and long enough to cut (the newest ${settings.options.keepRecentCalls} tool calls are kept as they are)`;
    return { kind: 'skip', why, report: why };
  }

  // A key carries a tool_use_id and, for an input, the field name (an MCP
  // tool's own): only safe characters reach the file name, and a key that
  // had others gets a hash of itself, so `a/b` and `a_b` never share a file.
  const pathOf = (cut: Cut): string => {
    const key = cut.kind === 'notice' ? `${stamp}-${cut.key}-${hashOf(cut.original)}` : cut.key;
    const safe = key.replace(/[^A-Za-z0-9._-]/g, '_').replace(/^\.+/, '_');
    return `${dir}/${cut.kind}-${safe === key ? safe : `${safe}-${hashOf(key)}`}.txt`;
  };
  const partsOf = new Map<Cut, number>();
  const whereOf = (cut: Cut): string => {
    const n = partsOf.get(cut) ?? 1;
    return n > 1 ? `${pathOf(cut)} (continued in .part2 to .part${n} beside it)` : pathOf(cut);
  };
  // Saves run against the time left: a cut whose save has not finished by then is not cut.
  const saving: Cut[] = [];
  const stop = new AbortController();
  const writes = Promise.all(
    decision.cuts.map(async (cut) => {
      try {
        const pieces = parts(cut.original, PART_CHARS);
        for (const [i, piece] of pieces.entries()) {
          await $.fs.write(i === 0 ? pathOf(cut) : `${pathOf(cut)}.part${i + 1}`, piece);
        }
        partsOf.set(cut, pieces.length);
        saving.push(cut);
      } catch {
        // not saved, so not cut; counted in the report
      }
    }),
  );
  try {
    await Promise.race([writes, $.clock.sleep(Math.max(0, left() - 500), { signal: stop.signal }).catch(() => undefined)]);
  } finally {
    stop.abort();
  }
  const saved = [...saving];
  const unsaved = decision.cuts.length - saved.length;
  if (saved.length === 0) {
    if (auto) return { kind: 'pass' };
    return { kind: 'skip', why: 'the full texts could not be saved', report: `nothing cut: none of the ${unsaved} full texts could be saved under ${dir}/` };
  }

  const cut = applyCuts(messages, saved, whereOf, settings.options);
  const compacted = settings.options.resumeSafe ? fresh(cut) : freshBatches(cut);
  const after = sizeOf(compacted);
  if (auto && !enough(after)) return { kind: 'pass' };
  const report = reportOf(decision, before, after, saved, dir) + (unsaved > 0 ? ` ${unsaved} left uncut: their full text could not be saved.` : '');

  // One ledger per month keeps each file far below the host's 4 MiB read limit.
  const ledger = `${home}/.claude/fast-compact/ledger-${now.slice(0, 7)}.jsonl`;
  const line = JSON.stringify({
    at: now,
    session: sessionId,
    trigger,
    before,
    after,
    outputs: saved.filter((c) => c.kind === 'output').length,
    inputs: saved.filter((c) => c.kind === 'input').length,
    notices: saved.filter((c) => c.kind === 'notice').length,
    unsaved,
    whole: decision.whole.size,
    ranking: decision.ranking,
    jev: decision.jev
      ? { model: decision.jev.model, requests: decision.jev.requests, ms: decision.jev.ms, cost: decision.jev.cost, stage: decision.jev.stage, redacted: decision.jev.redacted }
      : { skipped: decision.jevSkipped },
    provider: settings.provider,
  });
  try {
    const previous = (await $.fs.exists(ledger)) ? await $.fs.read(ledger) : '';
    await $.fs.write(ledger, `${previous}${line}\n`);
  } catch {
    // the ledger is a convenience; a compaction never fails over it
  }
  return { kind: 'done', compacted, report, dir, stamp };
}

/** What the replay route keeps across /clear (module variables survive it; /clear starts no new session.start). */
interface ReplayState {
  /** The context window the last measurement reported, for the replay's fit check. */
  window?: number;
  /** A replay waiting for Claude's reply: when /fc started, for the total time logged at turn.complete. */
  replayed?: { at: number };
  /** Whether this machine has managed settings (looked up once). */
  managed?: boolean;
  /** Input tokens the last response was answered over, for the replay's size checks. */
  used?: number;
  /** How to get the full chat back if the replay turn fails: shown on the success line and again on a failed reply. */
  wayBack?: string;
  /** The context size (tokens) when the last replay started, to report the real change after it. */
  before?: number;
}

/**
 * Purpose: the route this /fc takes: the option, or for `auto`, replay where managed settings exist.
 * Usage: if ((await routeOf($)) === 'replay') ...
 * Gotchas: a failed lookup counts as no managed settings, so the hook route is tried.
 */
async function routeOf($: EngineInterface, settings: Settings, state: ReplayState): Promise<'hook' | 'replay'> {
  if (settings.route !== 'auto') return settings.route;
  state.managed ??= await $.fs.exists(MANAGED_SETTINGS).catch(() => false);
  return state.managed ? 'replay' : 'hook';
}

/**
 * Purpose: the replay route: trim the chat, save it, clear, and send it back as the first prompt.
 * Usage: called after /fc's command returns (a command holds the turn); returns the line to log.
 * Gotchas: nothing is cleared until the trimmed messages are saved and fit the window; an earlier
 * replay prompt is swapped for its saved messages, so a second /fc trims real tool calls again.
 */
async function replay($: EngineInterface, settings: Settings, state: ReplayState, focus: string, start: number): Promise<string> {
  // Read the window and its fill now: a plugin reload clears what session.measure stored.
  const { context } = await $.session.usage().catch(() => ({ context: undefined }));
  if (context?.window) state.window = context.window;
  if (context?.tokens) state.used = context.tokens;
  if (!state.window) return 'not cleared: the context window is not known yet; run one turn first';
  // `raw` is the whole transcript, kept for the cap and the changed-chat check. `messages` is what is
  // still in the context: from the last built-in summary on, with every earlier replay prompt (it is
  // not the first message: the /clear echo comes first) swapped for the messages it saved.
  const raw = (await $.session.messages()) as readonly Message[];
  if (raw.length >= MESSAGES_CAP) return `not cleared: the chat has ${MESSAGES_CAP}+ messages, so its oldest part may be missing; use /compact`;
  const earlier = raw.some((m) => m.role === 'user' && replayedPath(m.text) !== undefined);
  let messages: Message[];
  try {
    messages = await expand(raw, (path) => readParts($, path));
  } catch (error) {
    return `not cleared: an earlier replay's saved messages could not be read (${error instanceof Error ? error.message : String(error)})`;
  }
  const seen = estimateTokens(render(messages));
  const above = (state.used ?? 0) - STARTUP_TOKENS;
  if (!earlier && above > 20_000 && seen < SNAPSHOT_MIN_SHARE * above) {
    return `not cleared: /fc read ${messages.length} messages (~${kchars(seen)} tokens), too little for a context of ~${kchars(state.used ?? 0)} tokens; part of the chat may be missing`;
  }
  // What the model holds now: the live chat as it is (an earlier replay counts as its prompt text).
  const before = renderedSize(liveMessages(raw));
  const unpacked = renderedSize(messages);
  const left = (): number => start + REPLAY_BUDGET_MS - Date.now();
  // Pass 1: the usual cut (Jev when a key is set). Pass 2, when that frees under 40%: harder settings,
  // no Jev. Pass 3, still under 40%: shorten old stubs, old long replies and older skill loads.
  const first = await trim($, settings, messages, focus, left, 'replay');
  if (first.kind !== 'done') return first.kind === 'skip' ? `not cleared: ${first.report}` : 'not cleared';
  const done = first;
  let compacted = first.compacted;
  const passes = [first.report];
  if (renderedSize(compacted) > DEEPEN_ABOVE * unpacked) {
    const hard = { ...settings, provider: 'none' as const, providerNote: 'second pass', options: hardOptions(settings.options) };
    const second = await trim($, hard, compacted, focus, left, 'replay');
    if (second.kind === 'done') {
      compacted = second.compacted;
      passes.push(`pass 2: ${second.report}`);
    }
  }
  if (renderedSize(compacted) > DEEPEN_ABOVE * unpacked) {
    const pathOf = (cut: Cut): string => `${done.dir}/text-${done.stamp}-${cut.key}.txt`;
    const deep = deepen(compacted, pathOf);
    // Every text pass 3 replaces is saved first, in parallel batches, within the time budget.
    const writes = deep.cuts.flatMap((cut) => parts(cut.original, PART_CHARS).map((piece, i) => [i === 0 ? pathOf(cut) : `${pathOf(cut)}.part${i + 1}`, piece] as const));
    let savedAll = true;
    for (let i = 0; i < writes.length && savedAll; i += WRITE_BATCH) {
      if (left() <= 0) savedAll = false;
      else {
        const stop = new AbortController();
        const batch = Promise.all(writes.slice(i, i + WRITE_BATCH).map(([path, piece]) => $.fs.write(path, piece))).then(() => true, () => false);
        const late = $.clock.sleep(Math.max(0, left()), { signal: stop.signal }).then(() => false, () => false);
        savedAll = await Promise.race([batch, late]);
        stop.abort();
      }
    }
    if (savedAll) {
      compacted = deep.messages;
      passes.push(`pass 3: ${deep.cuts.length} old texts cut.`);
    } else passes.push('pass 3 skipped: its full texts could not all be saved in time.');
  }
  // Out of time (a slow disk, a slow Jev): nothing is cleared.
  if (left() <= 0) return `not cleared: trimming took over ${(REPLAY_BUDGET_MS / 1000).toFixed(1)} s; run /fc again`;
  const saved = `${done.dir}/replay-${done.stamp}.json`;
  const text = `${header(done.dir, saved)}\n\n${render(compacted)}`;
  const after = text.length;
  // Same unit on both sides: the whole prompt to send (header included) against the live chat's text.
  if (after > REPLAY_MIN_LEFT * before) {
    return `not cleared: the trimmed chat would be ${kchars(before)} → ${kchars(after)} chars (−${pct(before - after, before)}); under ${pct(100 - REPLAY_MIN_LEFT * 100, 100)} is not worth a clear. Little is new since the last /fc; run /compact if the context is nearly full`;
  }
  const tokens = estimateTokens(text);
  if (tokens > REPLAY_MAX_SHARE * state.window) return `not cleared: the trimmed chat (~${kchars(tokens)} tokens) would fill over ${pct(REPLAY_MAX_SHARE * 100, 100)} of the window; use /compact`;
  try {
    for (const [i, piece] of parts(JSON.stringify(compacted), PART_CHARS).entries()) {
      await $.fs.write(i === 0 ? saved : `${saved}.part${i + 1}`, piece);
    }
  } catch {
    return `not cleared: the trimmed chat could not be saved to ${saved}`;
  }
  // A prompt typed while the trim ran is not in the snapshot; clearing now would lose it.
  const latest = (await $.session.messages()) as readonly Message[];
  if (latest.length !== raw.length || latest.at(-1)?.text !== raw.at(-1)?.text) {
    return `not cleared: the chat changed while /fc was trimming; run /fc again (the trimmed copy is in ${saved})`;
  }
  const oldSession = await $.session.id();
  try {
    await $.command.run({ command: 'clear' });
  } catch (error) {
    return `not cleared: /clear failed (${error instanceof Error ? error.message : String(error)})`;
  }
  const sent = await $.prompt.submit({ text, asUser: true }).catch((error: unknown) => ({ drop: error instanceof Error ? error.message : String(error) }));
  if ('drop' in sent && sent.drop !== undefined) {
    return `cleared, but the replay was not sent (${sent.drop || 'no reason given'}). The trimmed chat is in ${saved}; the full chat: claude --resume ${oldSession}`;
  }
  state.replayed = { at: start };
  state.wayBack = `trimmed chat: ${saved}; full chat: claude --resume ${oldSession}`;
  state.before = state.used;
  return `${kchars(before)} → ${kchars(after)} chars (−${pct(before - after, before)}). ${passes.join(' ')} Read ${messages.length} messages; replayed after a clear in ${((Date.now() - start) / 1000).toFixed(1)} s. Way back: ${state.wayBack}`;
}

export const register: Register = (on, options) => {
  const settings = settingsOf(options);
  /** The /fc whose scheduled /compact has not settled yet. */
  let running: { at: number } | undefined;
  /** What the last compaction did, logged once the /compact it rode on has finished (a log line written during a compaction is lost with the screen). */
  let report: string | undefined;
  /** A /fc's compaction ran without reaching this plugin (an organization-managed Claude Code): /fc is refused and the meter hidden from then on. */
  let missed = false;
  /** Meter lines shown so far, the first METER_HINTS saying how to hide it. */
  let lines = 0;
  /** What the replay route remembers across /clear: the window, a replay awaiting its reply, the managed-settings lookup. */
  const state: ReplayState = {};

  on('session.start', async ($, e, next) => {
    const started = await next(e);
    await $.command.register({
      name: 'fast-compact',
      description: 'Cut old tool output to its start and end, every cut saved to a file; /compact is untouched',
      argumentHint: '[what to keep]',
    });
    await $.command.register({
      name: 'fc',
      description: 'fast-compact: cut old tool output to its start and end, every cut saved',
      argumentHint: '[what to keep]',
    });
    return started;
  });

  // The host refuses a compaction started inside a command's own hook (the
  // command holds the turn) and skips this plugin's hooks on one it starts
  // itself, so the command schedules Claude Code's own /compact, marked, for
  // the moment after it returns; the session.compact hook below answers it.
  on('command.run', async ($, e, next) => {
    if (e.command !== 'fast-compact' && e.command !== 'fc') return next(e);
    if (missed) return { text: 'off for this session: its compaction did not reach this plugin last time (see the line above)' };
    const now = await $.clock.now();
    if (running && now - running.at < STUCK_MS) return { text: 'a compaction is already running' };
    const focus = e.args.trim();
    const mine = { at: now };
    running = mine;
    report = undefined;
    if ((await routeOf($, settings, state)) === 'replay') {
      $.clock.after(0, () => {
        replay($, settings, state, focus, Date.now())
          .then((line) => $.ui.log(line))
          .catch((error: unknown) => $.ui.log(`replay failed (${error instanceof Error ? error.message : String(error)})`))
          .finally(() => {
            if (running === mine) running = undefined;
          });
      });
      return { text: `trimming, then clearing and replaying${focus ? ` (keeping: ${focus})` : ''}…` };
    }
    $.clock.after(0, () => {
      $.command
        .run({ command: 'compact', args: markerOf(focus) })
        .then(() => {
          if (report === undefined) missed = true;
          $.ui.log(report ?? MISSED);
        })
        .catch((error: unknown) => {
          $.ui.log(`could not compact (${error instanceof Error ? error.message : String(error)})`);
        })
        .finally(() => {
          report = undefined;
          if (running === mine) running = undefined;
        });
    });
    return { text: `compacting${focus ? ` (keeping: ${focus})` : ''}…` };
  });

  // After each turn: what /fc would free now, worked out without Jev, so no
  // request is made. A measurement where only the rate limits or the cost moved
  // leaves the line as it is, sparing a read of the whole transcript.
  on('session.measure', async ($, e, next) => {
    const result = await next(e);
    if (e.context.window) state.window = e.context.window;
    if (e.context.tokens) state.used = e.context.tokens;
    if (settings.meter !== 'off' && missed) await showMeter($, settings.meter, undefined);
    else if (settings.meter !== 'off' && e.changed.includes('context')) {
      const freed = await $.session
        .messages()
        .then((messages) => estimate(messages as readonly Message[], settings.options))
        .catch(() => undefined);
      const shown = freed && freed.tokens >= METER_MIN_TOKENS ? freed : undefined;
      await showMeter($, settings.meter, shown, e.context.window, lines < METER_HINTS);
      if (shown) lines++;
    }
    return result;
  });

  // The replay's total time: from /fc to the end of Claude's reply to the replayed chat.
  on('turn.complete', async ($, e, next) => {
    const result = await next(e);
    if (state.replayed && !e.agentId) {
      const secs = ((Date.now() - state.replayed.at) / 1000).toFixed(1);
      // The real context size, as the status line has it: the proof a replay freed space.
      const now = (await $.session.usage().catch(() => undefined))?.context.tokens;
      const real = now && state.before ? `; context ${kchars(state.before)} → ${kchars(now)} tokens (−${pct(state.before - now, state.before)})` : '';
      $.ui.log(
        e.reason === 'answer'
          ? `/fc replay: Claude replied ${secs} s after /fc${real}`
          : `/fc replay: Claude's reply ended with "${e.reason}" ${secs} s after /fc. Way back: ${state.wayBack}`,
      );
      state.replayed = undefined;
    }
    return result;
  });

  on('session.compact', async ($, e, next) => {
    // Any compaction changes what /fc could free; the next turn measures again.
    if (!e.agentId && e.trigger !== 'precompute') await showMeter($, settings.meter, undefined);
    // Ours is the main conversation's manual or plugin compaction carrying the
    // marker (the scheduled /compact arrives as `manual` in 2.1.283), and its
    // auto-compaction when `autoCompact` is on; precompute and subagent
    // compactions, and every other one, pass on.
    const auto = takesAuto(settings, e);
    const mainManual = !e.agentId && (e.trigger === 'plugin' || e.trigger === 'manual');
    const focus = auto ? '' : mainManual ? focusOf(e.instructions) : undefined;
    if (focus === undefined) return next(e);
    const done = await trim($, settings, e.messages as readonly Message[], focus, () => next.budget.remainingMs, auto ? 'auto' : 'fc');
    if (done.kind === 'pass') return next(e);
    report = done.report;
    if (done.kind === 'skip') return { skip: done.why };
    return { messages: done.compacted };
  }).catch((_$, e, next) => {
    // A failure on this plugin's own compaction answers a skip, never the
    // built-in summary; one on a compaction it passed on stands as it was.
    // An auto-compaction it took goes to the summary: a skip would leave the
    // context full.
    if (next.called) return undefined;
    if (takesAuto(settings, e)) return next(e);
    const why = `failed (${next.error.kind}${next.error.message ? `: ${next.error.message}` : ''}); nothing was cut`;
    report = why;
    return { skip: `fast-compact ${why}` };
  });
};

/**
 * ABOUTME: The replay route's text: the trimmed chat rendered as one prompt, and its header.
 * ABOUTME: Used where Claude Code skips plugin compact hooks: /fc clears the chat and sends this back.
 * ABOUTME: The header names the JSON file that holds the same messages with their tool structure.
 * ABOUTME: A later /fc finds that path in the first message and trims the real messages again.
 * ABOUTME: Pure functions only: no engine calls, so tests and the bench can use them.
 */
import { cutEnd, cutMiddle, isHostText, wasCut } from './text.js';
import { protectedFrom, typedByPerson } from './compact.js';
import type { Cut, Message, Options } from './types.js';

/** The first line of every replay prompt; a later /fc knows a replay by it. */
export const REPLAY_FIRST_LINE = 'This is the earlier part of this same chat, replayed by /fc after a clear.';
/** The line that names the saved messages; the path follows it. */
const SAVED_LABEL = 'Saved messages: ';

/**
 * Purpose: render trimmed messages as plain text a model reads as the chat so far.
 * Usage: render(messages) -> one string, one block per message, blank line between blocks.
 * Gotchas: a tool's name is in `tool` (not `name`); call ids pair parallel calls with their results.
 */
export function render(messages: readonly Message[]): string {
  return messages
    .map((m) => {
      const lines: string[] = [];
      if (m.text) lines.push(`[${m.role}] ${m.text}`);
      for (const u of m.toolUses) lines.push(`[tool call ${u.tool} ${u.tool_use_id}] ${JSON.stringify(u.input)}`);
      for (const r of m.toolResults ?? []) lines.push(`[tool ${r.isError ? 'error' : 'result'} ${r.tool_use_id}] ${r.text}`);
      return lines.join('\n');
    })
    .filter(Boolean)
    .join('\n\n');
}

/**
 * Purpose: the words before the replayed chat: what it is, where the full texts are, how to answer.
 * Usage: header(cutsDir, savedJsonPath) + '\n\n' + render(messages).
 * Gotchas: `replayedPath` parses the saved line back, so keep SAVED_LABEL on a line of its own.
 */
export function header(dir: string, saved: string): string {
  return [
    REPLAY_FIRST_LINE,
    'The [user] lines are the person’s own words. Old tool output was cut; every full text is saved in this folder:',
    dir,
    `${SAVED_LABEL}${saved}`,
    'Do not use tools now. Reply with one short line saying you have the history, then wait for the person.',
  ].join('\n');
}

/**
 * Purpose: the saved-messages path a replay prompt names, or undefined for any other text.
 * Usage: replayedPath(message.text).
 * Gotchas: only text that starts with REPLAY_FIRST_LINE counts, so a person quoting the label is ignored.
 */
export function replayedPath(text: string): string | undefined {
  text = text.trimStart();
  if (!text.startsWith(REPLAY_FIRST_LINE)) return undefined;
  const line = text.split('\n', 6).find((l) => l.startsWith(SAVED_LABEL));
  return line ? line.slice(SAVED_LABEL.length).trim() || undefined : undefined;
}

/** How Claude Code's own compaction summary starts; messages before it are no longer in the context. */
const SUMMARY_START = 'This session is being continued from a previous conversation';

/**
 * Purpose: the part of the chat still in the context: from the last built-in compaction summary on.
 * Usage: liveMessages(await $.session.messages()). Returns the input when no summary is found.
 * Gotchas: session.messages() returns the whole transcript, pre-compaction messages included;
 * replaying those would undo the earlier compaction (seen 2026-11-26: 216k tokens became 225k).
 */
export function liveMessages<T extends { role: string; text: string }>(messages: readonly T[]): readonly T[] {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i]!;
    if (m.role === 'user' && m.text.trimStart().startsWith(SUMMARY_START)) return messages.slice(i);
  }
  return messages;
}

/**
 * Purpose: the chat as it is in the context, with every earlier replay prompt swapped for the
 * messages it saved (nested replays unpacked too).
 * Usage: await expand(await $.session.messages(), (path) => readParts($, path)).
 * Gotchas: after a /clear the replay is not the first message (the /clear echo comes first), so the
 * LAST replay prompt in the live part is the one used; everything before it is dropped. A summary
 * after the replay wins, since liveMessages cuts before it. Throws when a saved file cannot be read.
 */
export async function expand(
  raw: readonly Message[],
  load: (path: string) => Promise<Message[]>,
  depth = 0,
): Promise<Message[]> {
  const live = liveMessages(raw);
  let at = -1;
  for (let i = live.length - 1; i >= 0; i--) {
    if (live[i]!.role === 'user' && replayedPath(live[i]!.text)) {
      at = i;
      break;
    }
  }
  if (at < 0) return [...live];
  if (depth >= 8) throw new Error('replays nested more than 8 deep');
  const saved = await expand(await load(replayedPath(live[at]!.text)!), load, depth + 1);
  return [...liveMessages([...saved, ...live.slice(at + 1)])];
}

/** The size of the replay prompt `messages` would make, in characters (the unit the gate compares). */
export function renderedSize(messages: readonly Message[]): number {
  return render(messages).length;
}

/** The harder settings a second pass uses: fewer recent calls kept whole, shorter cuts, nothing kept whole on rank. */
export function hardOptions(options: Options): Options {
  return { ...options, keepRecentCalls: Math.min(options.keepRecentCalls, 4), cutTo: Math.min(options.cutTo, 300), keepWhole: 0, noticeCutTo: Math.min(options.noticeCutTo, 200) };
}

/** Text in a message older than the newest DEEP_KEEP_TURNS person turns this long or longer is cut by `deepen`. */
const DEEP_TEXT_MIN = { assistant: 1200, user: 4000 };
const DEEP_TEXT_KEEP = { assistant: 600, user: 1500 };
const DEEP_KEEP_TURNS = 3;
/** The protected tail never reaches back further than this many messages (a /loop chat has few person turns). */
const DEEP_KEEP_MAX = 150;
/** An old cut stub is cut again to this many characters (its current text saved first). */
const DEEP_STUB_KEEP = 300;

/** How a loaded skill's text starts; its first line names the skill. */
const SKILL_START = 'Base directory for this skill: ';
/** A loaded skill's text, older copies of which are cut to this many characters. */
const DEEP_SKILL_KEEP = 300;

/** Whether a user message is something a person typed (not host text, a skill body, a replay or tool results). */
export function isPersonText(m: Message): boolean {
  return typedByPerson(m) && !replayedPath(m.text);
}

/** Index of the `n`-th newest message a person typed; 0 when fewer. */
function turnStart(messages: readonly Message[], n: number): number {
  let seen = 0;
  for (let i = messages.length - 1; i >= 0; i--) {
    if (isPersonText(messages[i]!) && ++seen >= n) return i;
  }
  return 0;
}

/**
 * Purpose: the last, hardest pass of a replay: shorten every old cut stub further, and cut long
 * old text (Claude's replies, and very long pasted text) to its start and end.
 * Usage: const { messages, cuts } = deepen(trimmed, pathOf); save every cut's `original`
 * at pathOf(cut) before using `messages`.
 * Gotchas: what is never touched: the newest 4 tool calls and everything after them; the newest
 * DEEP_KEEP_TURNS person turns; any message newer than both of those limits. In a /loop chat the
 * person turns can sit hundreds of messages back, so for replies and stubs (never person text) the
 * protected tail reaches back at most DEEP_KEEP_MAX messages. Older loads of a skill that loads again
 * later are cut anywhere. Every cut, a re-cut stub included, saves the text it replaces first, so no
 * text is lost even when a field holds new text beside an old marker.
 * Cut kind is 'notice' so the archive names stay apart from tool output cuts.
 */
export function deepen(
  messages: readonly Message[],
  pathOf: (cut: Cut) => string,
): { messages: Message[]; cuts: Cut[] } {
  const callFrom = protectedFrom(messages, 4);
  const personFrom = turnStart(messages, DEEP_KEEP_TURNS);
  const otherFrom = Math.min(callFrom, Math.max(Math.min(personFrom, callFrom), messages.length - DEEP_KEEP_MAX));
  const cuts: Cut[] = [];
  let n = 0;
  /** Cuts `text` to `keep` characters around a marker, saving the whole of it first. */
  const cutText = (text: string, index: number, keep: number, what: string): string => {
    const cut: Cut = { kind: 'notice', key: `t${index}-${n++}`, index, field: 'text', original: text };
    cuts.push(cut);
    return cutMiddle(text, keep, pathOf(cut), what);
  };
  const skillLast = new Map<string, number>();
  messages.forEach((m, i) => {
    if (m.role === 'user' && m.text.startsWith(SKILL_START)) skillLast.set(m.text.split('\n', 1)[0]!, i);
  });
  const out = messages.map((m, index): Message => {
    const role = m.role;
    // An older load of a skill that loads again later goes anywhere, even in the protected tail: the newest copy stays whole.
    if (role === 'user' && m.text.startsWith(SKILL_START) && skillLast.get(m.text.split('\n', 1)[0]!)! > index && m.text.length > DEEP_SKILL_KEEP * 2) {
      const cut: Cut = { kind: 'notice', key: `t${index}-${n++}`, index, field: 'text', original: m.text };
      cuts.push(cut);
      const { handle: _h, ...rest } = m;
      return { ...rest, text: cutEnd(m.text, DEEP_SKILL_KEEP, `${pathOf(cut)} (the same skill loads again later in the chat)`) };
    }
    if (index >= otherFrom || (isPersonText(m) && index >= personFrom)) return m;
    const shrink = (t: string): string => (wasCut(t) && t.length > DEEP_STUB_KEEP * 2 ? cutText(t, index, DEEP_STUB_KEEP, 'this earlier cut') : t);
    let text = m.text;
    if (wasCut(text)) text = shrink(text);
    else if (text.length >= DEEP_TEXT_MIN[role] && !replayedPath(text) && !(role === 'user' && isHostText(text))) {
      text = cutText(text, index, DEEP_TEXT_KEEP[role], role === 'assistant' ? 'this reply' : 'this message');
    }
    const toolUses = m.toolUses.map((u) => {
      const input: Record<string, unknown> = {};
      let changed = false;
      for (const [k, v] of Object.entries(u.input)) {
        const nv = typeof v === 'string' ? shrink(v) : v;
        if (nv !== v) changed = true;
        input[k] = nv;
      }
      const ut = u.text === undefined ? undefined : shrink(u.text);
      return changed || ut !== u.text ? { ...u, input, ...(ut === undefined ? {} : { text: ut }) } : u;
    });
    const toolResults = m.toolResults?.map((r) => {
      const t = shrink(r.text);
      return t === r.text ? r : { ...r, text: t };
    });
    const same = text === m.text && toolUses.every((u, i) => u === m.toolUses[i]) && (toolResults ?? []).every((r, i) => r === m.toolResults![i]);
    if (same) return m;
    const { handle: _handle, ...rest } = m;
    return { ...rest, text, toolUses, ...(toolResults ? { toolResults } : {}) };
  });
  return { messages: out, cuts };
}

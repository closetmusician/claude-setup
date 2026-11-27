// ABOUTME: The /fc replay route end to end in the plugin test host: trim, save, /clear, submit.
// ABOUTME: Covers a replay of a replay found behind the /clear echo, a chat with nothing to free,
// ABOUTME: and a chat that changed while /fc trimmed. Real engine calls are mocked, the plugin code is real.
// ABOUTME: Added 2026-11-26 after a live /fc replayed an earlier replay whole and freed 0%.
// ABOUTME: Run: claude plugin test .
import { describe, expect, mock, test } from 'claude-code/testing';
import type { On, SessionMessage } from 'claude-code';

const REPLAY = { options: { route: 'replay', provider: 'none' } };
const COMMAND = { origin: { kind: 'composer' as const }, presentation: { isFullscreen: false, columns: 100 } };

/** A chat of `turns` person turns, each with a long reply and three long tool reads. */
function work(turns: number, tag: string): SessionMessage[] {
  const out: SessionMessage[] = [];
  for (let t = 0; t < turns; t++) {
    out.push({ role: 'user', text: `${tag} question ${t}`, toolUses: [] });
    for (let k = 0; k < 3; k++) {
      const id = `toolu_${tag}${t}_${k}`;
      const output = `${tag} file ${t}.${k}\n${'line of output\n'.repeat(250)}END`;
      out.push({ role: 'assistant', text: '', toolUses: [{ tool_use_id: id, tool: 'Read', input: { file_path: `/r/${tag}${t}${k}` }, text: output }] });
      out.push({ role: 'user', text: '', toolUses: [], toolResults: [{ tool_use_id: id, text: output, isError: false }] });
    }
    out.push({ role: 'assistant', text: `${tag} answer ${t}: ${'explaining at length. '.repeat(120)}`, toolUses: [] });
  }
  return out;
}

const CLEAR_ECHO: SessionMessage = { role: 'user', text: '<command-name>/clear</command-name>\n<command-message>clear</command-message>', toolUses: [] };

interface World {
  files: Map<string, string>;
  logs: string[];
  submitted: string[];
  clears: number;
  clock: ReturnType<typeof mock.clock>;
}

function world(on: On, messages: () => SessionMessage[], files = new Map<string, string>(), hangWrites = false): World {
  mock.env(on, { HOME: '/Users/tester' });
  const w: World = { files, logs: [], submitted: [], clears: 0, clock: mock.clock(on, { now: 1_790_000_000_000 }) };
  on('command.run', (_$, e) => {
    if (e.command === 'clear') w.clears++;
    return { text: '' };
  });
  on('session.id', () => ({ value: 'sess-1' }));
  on('settings.read', () => ({ value: {} }));
  on('session.usage', () => ({ value: { startedAt: 0, context: { tokens: 60_000, window: 1_000_000, percent: 6 }, rateLimits: [], cost: { usd: 0 } } }));
  on('session.messages', () => ({ value: messages() }));
  on('prompt.submit', (_$, e) => {
    w.submitted.push(e.text);
    return { text: e.text };
  });
  on('ui.log', (_$, e) => {
    w.logs.push(e.text);
    return { value: undefined };
  });
  on('ui.status', () => ({ value: undefined }));
  on('fs.write', (_$, e) => {
    if (hangWrites) return new Promise(() => {});
    w.files.set(e.path, e.text);
    return { value: undefined };
  });
  on('fs.exists', (_$, e) => ({ value: w.files.has(e.path) }));
  on('fs.read', (_$, e) => {
    const text = w.files.get(e.path);
    return text === undefined ? { deny: 'ENOENT' } : { value: text };
  });
  return w;
}

/** Runs /fc and lets the scheduled replay finish. */
async function fc($: { command: { run: (a: never) => Promise<unknown> } }, w: World): Promise<void> {
  await $.command.run({ command: 'fc', args: '', ...COMMAND } as never);
  for (let i = 0; i < 50 && !w.logs.some((l) => /cleared|Replayed|replayed after/.test(l)); i++) await w.clock.advance(10);
}

const FIRST = 'This is the earlier part of this same chat, replayed by /fc after a clear.';

describe('replay route', () => {
  test('a replay of a replay, behind the /clear echo, is unpacked and shrinks', REPLAY, async ($, on) => {
    // Round 1: a plain chat is replayed.
    let chat: SessionMessage[] = work(12, 'a');
    const w = world(on, () => chat);
    await fc($, w);
    expect(w.clears).toBe(1);
    const one = w.submitted[0]!;
    expect(one.startsWith(FIRST)).toBe(true);
    // Round 2: the new session holds the /clear echo first, then the replay, then new work.
    chat = [CLEAR_ECHO, { role: 'user', text: one, toolUses: [] }, { role: 'assistant', text: 'I have the history.', toolUses: [] }, ...work(8, 'b')];
    w.logs.length = 0;
    await fc($, w);
    expect(w.clears).toBe(2);
    const two = w.submitted[1]!;
    // The earlier replay prompt is never sent back inside the new one.
    expect(two.split(FIRST).length - 1).toBe(1);
    // It is smaller than the chat it replaced (the earlier replay text plus the new work).
    const replaced = one.length + JSON.stringify(work(8, 'b')).length;
    expect(two.length).toBeLessThan(0.85 * replaced);
    // The newest person turn is still there, word for word.
    expect(two).toContain('b question 7');
    // Every cut marker in either prompt names a saved file whose text starts as the stub does.
    let checked = 0;
    for (const prompt of [one, two]) {
      for (const m of prompt.matchAll(/([^\n]{0,40})\n\[fast-compact: cut \d+ chars [^\]\n]*?; the full text is in (\/[^\s\]]+\.txt)/g)) {
        const file = w.files.get(m[2]!);
        expect(file, `missing archive ${m[2]}`).toBeDefined();
        const lead = m[1]!.split('] ').pop()!.slice(0, 20);
        if (lead) expect(file!.includes(lead), `archive ${m[2]} does not hold "${lead}"`).toBe(true);
        checked++;
      }
    }
    expect(checked).toBeGreaterThan(20);
  });

  test('a chat with nothing to free is left alone', REPLAY, async ($, on) => {
    const w = world(on, () => work(1, 'c'));
    await fc($, w);
    expect(w.clears).toBe(0);
    expect(w.submitted.length).toBe(0);
    expect(w.logs.some((l) => l.startsWith('not cleared'))).toBe(true);
  });

  test('a chat that changed while /fc trimmed is left alone', REPLAY, async ($, on) => {
    let reads = 0;
    const base = work(12, 'd');
    const w = world(on, () => (++reads === 1 ? base : [...base, { role: 'user', text: 'typed meanwhile', toolUses: [] }]));
    await fc($, w);
    expect(w.clears).toBe(0);
    expect(w.logs.some((l) => l.includes('chat changed')), JSON.stringify(w.logs)).toBe(true);
  });

  test('a repeated paste among the newest three person turns is never cut', REPLAY, async ($, on) => {
    const paste = `PASTE ${'pasted log line\n'.repeat(725)}`;
    const calls = (tag: string): SessionMessage[] =>
      Array.from({ length: 12 }, (_, i) => [
        { role: 'assistant' as const, text: '', toolUses: [{ tool_use_id: `${tag}${i}`, tool: 'Read', input: { file_path: `/x${i}` }, text: `${'out\n'.repeat(400)}` }] },
        { role: 'user' as const, text: '', toolUses: [], toolResults: [{ tool_use_id: `${tag}${i}`, text: `${'out\n'.repeat(400)}`, isError: false }] },
      ]).flat();
    const chat: SessionMessage[] = [...work(10, 'e'), { role: 'user', text: 'start', toolUses: [] }, { role: 'user', text: paste, toolUses: [] }, ...calls('p'), { role: 'user', text: paste, toolUses: [] }, ...calls('q')];
    const w = world(on, () => chat);
    await fc($, w);
    expect(w.clears).toBe(1);
    expect(w.submitted[0]!.split(paste).length - 1).toBe(2);
  });

  test('a save that never finishes leaves the chat alone', REPLAY, async ($, on) => {
    const w = world(on, () => work(12, 'f'), new Map(), true);
    await $.command.run({ command: 'fc', args: '', ...COMMAND } as never);
    for (let i = 0; i < 80 && !w.logs.some((l) => /cleared|replayed after/.test(l)); i++) await w.clock.advance(1000);
    expect(w.clears).toBe(0);
    expect(w.logs.some((l) => l.startsWith('not cleared')), JSON.stringify(w.logs)).toBe(true);
  });
});

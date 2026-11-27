// ABOUTME: Scenario matrix for the /fc replay route, run on real transcripts with the plugin's own pure steps.
// ABOUTME: Per chat: first run, re-run right after, two runs after new work, replay then built-in compact.
// ABOUTME: Checks: no earlier replay sent back whole, newest 3 person turns kept, clears only at 15%+ freed.
// ABOUTME: Usage: bun replay_matrix.ts <outdir> <work-transcript.jsonl> <chat.jsonl>...
// ABOUTME: Plugin code: ~/.claude/plugins/local/fast-compact. Written 2026-11-27.
// Offline scenario matrix for the /fc replay route: same pure steps as hooks/fast-compact.ts replay().
import { readFileSync, existsSync, writeFileSync, mkdirSync } from 'node:fs';
const FC = '/Users/yklin/.claude/plugins/local/fast-compact';
const { readSegments } = await import(`${FC}/bench/transcript.ts`);
const { decide, applyCuts, fresh } = await import(`${FC}/src/compact.ts`);
const { expand, renderedSize, hardOptions, deepen, header, render, replayedPath, liveMessages } = await import(`${FC}/src/replay.ts`);
const { cutMiddle } = await import(`${FC}/src/text.ts`);
const { DEFAULT_OPTIONS } = await import(`${FC}/src/types.ts`);
const OUT = process.argv[2]!; mkdirSync(OUT, { recursive: true });
const opts = { ...DEFAULT_OPTIONS, cutTo: 600 };
const load = async (p: string) => { let s = readFileSync(p, 'utf8'); for (let i = 2; existsSync(`${p}.part${i}`); i++) s += readFileSync(`${p}.part${i}`, 'utf8'); return JSON.parse(s); };
const strip = (m: any) => ({ role: m.role, text: m.text ?? '', toolUses: m.toolUses ?? [], ...(m.toolResults ? { toolResults: m.toolResults } : {}) });
const raw = (f: string) => readSegments(f, 'x').flatMap((s: any) => s.messages).map(strip);
async function once(o: any, msgs: any[]) { const d = await decide(msgs, o, 'off'); return fresh(applyCuts(msgs, d.cuts, () => '/a/x.txt', o)); }
async function pipeline(rawMsgs: any[]) {
  const msgs = await expand(rawMsgs, load);
  const before = renderedSize(liveMessages(rawMsgs)); const un = renderedSize(msgs); const st: string[] = [];
  let cur = await once(opts, msgs); st.push(`p1 ${(100 - 100 * renderedSize(cur) / before).toFixed(0)}%`);
  if (renderedSize(cur) > 0.6 * un) { cur = await once(hardOptions(opts), cur); st.push(`p2 ${(100 - 100 * renderedSize(cur) / before).toFixed(0)}%`); }
  if (renderedSize(cur) > 0.6 * un) { cur = deepen(cur, () => '/a/t.txt').messages; st.push(`p3 ${(100 - 100 * renderedSize(cur) / before).toFixed(0)}%`); }
  const leftover = cur.filter((m: any) => m.role === 'user' && replayedPath(m.text)).length;
  const { isHostText } = await import(`${FC}/src/text.ts`);
  const { isPersonText } = await import(`${FC}/src/replay.ts`);
  const userTail = (a: any[]) => a.filter((m) => isPersonText(m)).slice(-3).map((m) => m.text).join('|');
  return { msgs, cur, before, after: header('/d', '/d/replay-0.json').length + 2 + renderedSize(cur), st, leftover, tailKept: userTail(msgs) === userTail(cur) };
}
let n = 0;
async function round(label: string, rawMsgs: any[], expect: 'free' | 'refuse' | 'either' = 'free') {
  const t = Date.now(); const r = await pipeline(rawMsgs); const ms = Date.now() - t;
  const saved = `${OUT}/replay-${++n}.json`; writeFileSync(saved, JSON.stringify(r.cur));
  const text = `${header(OUT, saved)}\n\n${render(r.cur)}`;
  const frees = r.after <= 0.85 * r.before;
  const ok = (expect === 'either' || (expect === 'free' ? frees : !frees)) && r.leftover === 0 && r.tailKept;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${(frees ? 'clears ' : 'refuses') } ${label.padEnd(40)} live ${String(r.msgs.length).padStart(4)} msgs ${Math.round(r.before / 1000)}k -> ${Math.round(r.after / 1000)}k chars (-${(100 - 100 * r.after / r.before).toFixed(0)}%) [${r.st.join(', ')}] nested-left ${r.leftover} tail-kept ${r.tailKept} ${ms}ms`);
  return text;
}
const clearEcho = { role: 'user', text: '<command-name>/clear</command-name>\n<command-message>clear</command-message>', toolUses: [] };
const files = process.argv.slice(4);
const WORK = raw(process.argv[3]!).filter((m: any) => !m.text.trimStart().startsWith('This session is being continued')).slice(-400);
for (const f of files) {
  const base = raw(f); const name = f.split('/').pop()!.slice(0, 8);
  const summary = base.some((m: any) => m.text.trimStart().startsWith('This session is being continued'));
  let text = await round(`${name} r1${summary ? ' (had built-in compact)' : ''}`, base, base.length < 40 ? 'refuse' : 'free');
  // A re-run straight after: little new to cut, so /fc must refuse rather than clear for nothing.
  const echo = (t: string) => [clearEcho, { role: 'user', text: t, toolUses: [] }, { role: 'assistant', text: 'I have the history.', toolUses: [] }];
  await round(`${name} re-run right after`, [...echo(text), ...base.slice(-6)], 'either');
  // Re-runs after real new work: 200 messages of another chat's work appended each round.
  for (const r of [2, 3]) text = await round(`${name} r${r} after new work`, [...echo(text), ...WORK.slice((r - 2) * 200, (r - 1) * 200)]);
  // Replay then a built-in compact: the summary after the replay must win.
  const afterSummary = [clearEcho, { role: 'user', text, toolUses: [] }, { role: 'user', text: 'This session is being continued from a previous conversation. Summary: did things.', toolUses: [] }, ...WORK.slice(0, 30)];
  await round(`${name} replay then built-in compact`, afterSummary);
}

// Codex repros: a long newest person message before 4 calls stays whole; a stub with new text beside it is saved before a re-cut.
{
  const long = 'P'.repeat(5014);
  const calls = Array.from({ length: 4 }, (_, i) => [{ role: 'assistant', text: '', toolUses: [{ tool_use_id: `c${i}`, tool: 'Bash', input: { command: 'x' } }] }, { role: 'user', text: '', toolUses: [], toolResults: [{ tool_use_id: `c${i}`, text: 'ok', isError: false }] }]).flat();
  const old = Array.from({ length: 10 }, (_, i) => ({ role: 'assistant', text: `old reply ${i} ` + 'r'.repeat(1500), toolUses: [] }));
  const d1 = deepen([...old, { role: 'user', text: long, toolUses: [] }, ...calls], () => '/a/t.txt');
  console.log((d1.messages[10].text === long ? 'PASS' : 'FAIL') + ' codex repro 1: newest person text before 4 calls stays whole');
  const stub = cutMiddle('o'.repeat(5000), 600, '/old.txt', 'this output') + 'NEW_UNARCHIVED_DATA' + 'n'.repeat(1000);
  const msgs2 = [{ role: 'assistant', text: '', toolUses: [{ tool_use_id: 's1', tool: 'Read', input: {} }] }, { role: 'user', text: '', toolUses: [], toolResults: [{ tool_use_id: 's1', text: stub, isError: false }] }, ...['a', 'b', 'c'].map((t) => ({ role: 'user', text: `turn ${t}`, toolUses: [] })), ...calls];
  const d2 = deepen(msgs2, () => '/a/t.txt');
  const savedNew = d2.cuts.some((c: any) => c.original.includes('NEW_UNARCHIVED_DATA'));
  const gone = !JSON.stringify(d2.messages).includes('NEW_UNARCHIVED_DATA');
  console.log((!gone || savedNew ? 'PASS' : 'FAIL') + ` codex repro 2: new text beside an old marker is saved before a re-cut (saved ${savedNew}, still inline ${!gone})`);
}

// ABOUTME: Counts facts lost when /fc cuts old agent messages (rule from ~/.claude/plugins/local/fast-compact).
// ABOUTME: A lost fact is a distinctiveTokens token found only in the cut part of an agent message.
// ABOUTME: It counts the ones Claude uses first in the 40 tool calls after each past built-in compaction.
// ABOUTME: Read only. Run: bun agent_loss.ts out/backtest-points.jsonl
// ABOUTME: Written 2026-11-26 for WINDOW-SPLIT.md.
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
const FC = `${homedir()}/.claude/plugins/local/fast-compact`;
const { plan } = await import(`${FC}/src/compact.ts`);
const { DEFAULT_OPTIONS } = await import(`${FC}/src/types.ts`);
const { distinctiveTokens } = await import(`${FC}/bench/points.ts`);
const AGENT = ['Another Claude session sent a message', '<agent-message', '<cross-session-message'];
const isAgent = (t: string) => AGENT.some((p) => t.trimStart().startsWith(p));
const rtext = (c: any) => (typeof c === 'string' ? c : Array.isArray(c) ? c.map((p: any) => (p.type === 'text' ? p.text ?? '' : '')).join('\n') : '');
function toMsg(r: any): any | null {
  const c = r.message?.content;
  if (r.type === 'assistant') {
    if (!Array.isArray(c)) return null;
    return { role: 'assistant', text: c.filter((b: any) => b.type === 'text').map((b: any) => b.text).join('\n'), toolUses: c.filter((b: any) => b.type === 'tool_use').map((b: any) => ({ tool_use_id: b.id, tool: b.name, input: b.input ?? {} })) };
  }
  if (r.type !== 'user') return null;
  if (typeof c === 'string') return { role: 'user', text: c, toolUses: [] };
  if (!Array.isArray(c)) return null;
  const tr = c.filter((b: any) => b.type === 'tool_result').map((b: any) => ({ tool_use_id: b.tool_use_id, text: rtext(b.content), isError: !!b.is_error }));
  const m: any = { role: 'user', text: c.filter((b: any) => b.type === 'text').map((b: any) => b.text).join('\n'), toolUses: [] };
  if (tr.length) m.toolResults = tr;
  return m;
}
const all = (m: any) => [m.text, ...m.toolUses.map((u: any) => JSON.stringify(u.input)), ...(m.toolResults ?? []).map((r: any) => r.text)].join('\n');
let cutMsgs = 0, cutChars = 0, lostTok = 0, needed = 0, refetched = 0, supplied = 0; const pts = new Set<string>();
for (const line of readFileSync(process.argv[2], 'utf8').trim().split('\n')) {
  const p = JSON.parse(line);
  const recs = readFileSync(`${homedir()}/.claude/projects/${p.project}/${p.session}.jsonl`, 'utf8').split('\n').flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
  const b = recs.flatMap((r, i) => (r.type === 'system' && r.subtype === 'compact_boundary' ? [i] : []));
  const bi = b[p.index], lo = p.index > 0 ? b[p.index - 1] : -1, hi = p.index + 1 < b.length ? b[p.index + 1] : recs.length;
  const before = recs.slice(lo + 1, bi).filter((r) => !r.isSidechain).map(toMsg).filter(Boolean);
  const notices = plan(before, DEFAULT_OPTIONS).notices.filter((n: any) => isAgent(n.text));
  if (!notices.length) continue;
  const idx = new Set(notices.map((n: any) => n.index));
  const elsewhere = new Set<string>();
  before.forEach((m: any, i: number) => { if (!idx.has(i)) for (const t of distinctiveTokens(all(m))) elsewhere.add(t); });
  const lost = new Set<string>();
  for (const n of notices) {
    cutMsgs++; cutChars += n.text.length - 300;
    const kept = distinctiveTokens(n.text.slice(0, 300));
    for (const t of distinctiveTokens(n.text.slice(300))) if (!elsewhere.has(t) && !kept.has(t)) lost.add(t);
  }
  lostTok += lost.size;
  // Window: after the boundary, up to 40 tool calls. First sighting decides who supplied the token.
  const seen = new Map<string, string>(); let calls = 0;
  for (const r of recs.slice(bi + 1, hi)) {
    if (r.isSidechain || r.isCompactSummary) continue;
    const m = toMsg(r); if (!m) continue;
    if (m.role === 'assistant') {
      for (const t of distinctiveTokens(m.text + '\n' + m.toolUses.map((u: any) => JSON.stringify(u.input)).join('\n'))) if (lost.has(t) && !seen.has(t)) seen.set(t, 'assistant');
      calls += m.toolUses.length; if (calls >= 40) break;
    } else {
      for (const t of distinctiveTokens(m.text)) if (lost.has(t) && !seen.has(t)) seen.set(t, 'user');
      for (const tr of m.toolResults ?? []) for (const t of distinctiveTokens(tr.text)) if (lost.has(t) && !seen.has(t)) seen.set(t, 'result');
    }
  }
  for (const v of seen.values()) { if (v === 'assistant') { needed++; pts.add(p.session + p.index); } else if (v === 'result') refetched++; else supplied++; }
}
console.log({ agentMessagesCut: cutMsgs, charsCut: cutChars, tokensOnlyInCutPart: lostTok, usedByClaudeFirst: needed, pointsWithAUsedToken: pts.size, cameBackInAToolResultFirst: refetched, personResupplied: supplied });

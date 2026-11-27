# ai-guardrails-recap

```yaml
audience: boss or exec
reply_type: plan hand-off
channel: mail
words: 163
```

## Situation

After the chat debate in ai-code-output-rebuttal, a meeting finds the real worry is token cost.
Yu-Kuan sends a recap to the GM, <exec>, the VP of Engineering and the CFO. The General Counsel is on copy.

## Sent

### <date>

`````text
Hi everyone,

Just to recap, per our discussion earlier today for guardrails on AGAI

1. Account Usage report & tracking - we'll work with the platform team to provide regular token usage & financial reporting.
2. Cost Cap - we'll turn on cost cap controls.
3. Tighten prompts - as everyone has seen and <eng lead> has described, we already have guardrails in place, but we will review and tighten it even more around things like code snippets and anything of a personal nature.

@<engineer> since we're already using LLM proxy, can you look into 1-2? And then for #3 let's make some initial changes then work with platform team to eval this as well.

Everyone raised a good I think there is a bigger discussion we should have on how we think about and build for token costs, usage-based pricing or not, etc. That's not an AGAI-only topic, it might be good for the company to develop a stance on this.

YL
`````

## Why it works

- "Just to recap" sets the record of what the meeting agreed.
- Three numbered actions, one line each. Each is a commitment.
- He hands two items to a named engineer in one sentence.
- He keeps his position ("we already have guardrails in place") but still agrees to tighten prompts.
- He lifts the cost question to a company topic: "it might be good for the company to develop a stance on this."

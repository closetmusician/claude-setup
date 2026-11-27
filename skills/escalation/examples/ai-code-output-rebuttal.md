# ai-code-output-rebuttal

```yaml
audience: legal-security
reply_type: rebuttal
channel: Teams chat
words: 413
```

## Situation

The General Counsel asks in a group chat if the AI agent has safeguards, because a basic prompt returned code.
The GM has already posted a refusal example.
Yu-Kuan replies the next morning with a run of chat messages. All are on <date>.

## Sent

### 12:47 UTC

`````text
Hi team, I think we have quite a bit of guardrails in place - as <GM> has shown above. and I have more examples here. It will not discuss things totally off topic or obviously dangerous.
`````

### 12:49 UTC

`````text
A few thoughts on this - to my knoweldge, there are many POVs on what's a true "guard rail" and there's not an industry agreed standard

Code output is just text - It's not clear to me that somehow generic code text output is dangerous I don't think banning code output outright makes it "safer". To the LLM almost everything is code. The pretty board graphic, the nice board slides, and even the nice risk report. That's all formatted code, just doesn't appear to us that way. The python code is not much differentWe have disabled code execution - that's arguably the more dangerous part and that won't work. In fact that is why unfortunately a lot of our interactive artifacts won't work which is an unfortunate loss.All state of the art LLMs will give you code output by default - try it yourself.If we want to ban code output entirely or try to confine our LLM to "only" talk about GRC we're going to neuter a lot of our LLM's capabilities - Part of the power of LLMs is it's ability think and work in code, and solve general problems. I think attempting to narrow this will likely greatly neuter the LLM, be extremely difficult, also not very fruitful given that we don't own the underlying model weights. We can't even fine-tune if we wanted to.
Lastly, I just want to point out that some of the best minds of the industry still haven't solved this problem, and there's a generally a tradeoff between guardrails vs capability. I'd recommend we should decide what's truly dangerous vs what's not, then decide what to do?
`````

### 12:50 UTC

`````text
I think this is a great discussion btw and we should certainly have it since we may eventually turn this into some sort of marketing material on what our stance is. But just sharing what I know
`````

### 12:51 UTC

`````text
Look that's part of the power of LLMs - text is code is text. What's wrong with a redline?? I think many of our customers might even find that to be extremely helpful, no?
`````

### 12:52 UTC

`````text
OHHH is that what we're talking about?
`````

### 12:52 UTC

`````text
Ahh, I thought you were hauling me in front of a firing squad
`````

### 12:55 UTC

`````text
Of course, I am happy to discuss and share what I know
`````

## Why it works

- He opens by saying guardrails exist and points at the proof already in the chat.
- He reframes the question: "Code output is just text". Board graphics and slides are code too.
- He names the real control (code execution is off) and the cost of more limits ("neuter a lot of our LLM's capabilities").
- He ends the long message with a decision ask: "decide what's truly dangerous vs what's not, then decide what to do?"
- When the real worry turns out to be token cost, he lightens the tone with humour ("firing squad").
- The messages are fast and informal, with typos. There are no headings.

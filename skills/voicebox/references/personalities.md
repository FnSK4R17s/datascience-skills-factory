# Voice Personalities

A voice personality is a free-form prompt attached to a voice profile. It defines how the voice "thinks" and speaks — tone, vocabulary, mannerisms, context.

## What It Enables

| Feature | What It Does |
|---------|-------------|
| Persona-rewrite | Rewrites input text in the voice's style before TTS (LLM → TTS pipeline) |
| Compose | Generate fresh lines from a topic prompt — no input text required |
| Style hint | Subtle influence on TTS prosody (engine-dependent) |

Personalities are optional. Any profile works without one.

## Setup

Voices tab → open a profile → Personality section → write a free-form prompt.

**Example prompts:**
- "A dry, sardonic British commentator who never uses more than two syllables when one will do."
- "An enthusiastic science teacher who makes every fact sound like the most exciting thing ever discovered."
- "A warm grandmother who reminds everyone of their own grandmother."

No structured format required. The LLM interprets the prompt at generation time.

## Persona-Rewrite

When `personality: true` is set (toggle in floating generate box or profile settings):

```
Input: "The weather is nice today."
Personality: "A pirate captain obsessed with treasure."
Rewritten: "Arr, the skies be calm — perfect weather for huntin' gold, matey!"
TTS speaks the rewritten version.
```

Adds latency proportional to input length and LLM size.

## Compose Mode

Compose button (floating generate box, when personality is set) opens a topic prompt field. Instead of providing text to speak, you describe what you want said:

```
Topic: "Introduce yourself"
Personality: "A sardonic British commentator"
Output: "Right, well, here we are. Another introduction nobody asked for..."
```

Uses full LLM context — longer prompts, more coherent output, more latency.

## LLM Models

| Model | Size | VRAM | Best For |
|-------|------|------|----------|
| Qwen3 0.6B | ~600M params | ~1.2 GB | Low latency, simple rewrites |
| Qwen3 1.7B | ~1.7B params | ~3.5 GB | Balanced quality / speed |
| Qwen3 4B | ~4B params | ~8 GB | Best quality, complex personalities |

Select in Settings → Generation → Personality LLM.

Same model is used for dictation refinement — picking larger improves both.

## MCP Usage

```javascript
voicebox.speak({
  text: "The deployment completed successfully.",
  profile: "Morgan",
  personality: true  // routes through profile's personality LLM
})
```

Profile must have a personality prompt set. If not, the text is spoken as-is.

Per-client default: Voicebox → Settings → MCP → set `default_personality: true` for a client binding.

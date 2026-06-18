# Dictation and Captures

## Dictation

Hold a chord anywhere on your machine, speak, release — transcript lands in the focused text field.

### Setup

Settings → Dictation:
- **Push-to-talk chord** — any key combo (default: Right Option / Right Alt)
- **Toggle mode** — press once to start, once again to stop (vs. hold-to-record)
- **Auto-refine** — uses Qwen3 LLM to clean up raw Whisper output
- **Whisper model** — Base by default

**Platform permissions:**
- macOS: grant Accessibility permissions when prompted (required for auto-paste)
- Windows: no extra permissions needed
- Linux: transcription works; paste support varies by window manager

### How It Works

1. Hotkey press → microphone opens
2. Hotkey released → recording stops → Whisper transcribes
3. Optional: Qwen3 LLM refines the transcript
4. Text pasted into last focused input

Transcript also lands in Captures tab.

### Hotkey Modes

| Mode | Behavior |
|------|----------|
| Push-to-talk | Hold to record, release to transcribe and paste |
| Toggle | Press once to start, press again to stop |

### Refinement Modes

| Mode | Behavior |
|------|----------|
| Auto | Refines only if transcript looks noisy (heuristic) |
| Always | Always refines before pasting (+0.5-2s latency) |
| Off | Raw Whisper output — fastest |

### Tips

- Short pauses are fine — Whisper handles mid-sentence pauses naturally
- Speak in complete sentences for best refinement
- If paste lands in wrong field, check which window had focus before hotkey
- Use toggle mode for longer dictations

## Captures

Paired audio recording + transcript archive. Three sources:

1. **Dictation** — auto-created on each push-to-talk
2. **In-app recording** — Captures tab → Record button
3. **File upload** — drag .wav, .mp3, .m4a, .webm, .opus, .flac

### Features

- **Re-transcribe** with any Whisper model
- **Inline transcript editing** — click to edit, saves immediately
- **LLM refinement** — removes filler words, fixes hallucinations
- **Play as Voice** — play capture through any voice profile
- **Promote to Sample** — use capture as a voice cloning sample (confirms reference_text match)

### API

```
POST /captures
{
  "audio": "<base64-encoded audio>",
  "model": "base",
  "refine": true
}
```

Returns capture ID, transcript, and duration.

## Transcription Models

All paths share the same Whisper models:

| Model | Size | When to pick |
|-------|------|-------------|
| Whisper Base | ~300 MB | Fast, default, good for clean speech |
| Whisper Small | ~500 MB | Better quality, still fast |
| Whisper Medium | ~1.5 GB | High quality |
| Whisper Large | ~3 GB | Best quality, slow on CPU |
| Whisper Turbo | ~1.5 GB | Large-tier quality, ~5x faster than Large |

Apple Silicon: runs through MLX-Whisper (~8x faster). Everywhere else: PyTorch transformers. Backend picks automatically.

For noisy clips, prefer Turbo or Large. Base can hallucinate ("thanks for watching" loop) — Voicebox strips these loops deterministically.

### Language

Pass a language hint for short clips (<5s) where auto-detect is unreliable. Set default in Settings → Captures → Transcription → Language, or override per capture.

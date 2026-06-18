# TTS Engines and Voice Catalogs

## Engine Overview

Seven engines with different strengths, switchable per-generation:

| Engine | Profile Type | Languages | VRAM (GPU) | Strengths |
|--------|-------------|-----------|------------|-----------|
| Qwen3-TTS 1.7B | Cloned | 10 | ~3.5 GB | Best overall quality, multilingual cloning |
| Qwen3-TTS 0.6B | Cloned | 10 | ~1.2 GB | Faster, lighter variant |
| Qwen CustomVoice 1.7B | Preset (9) | 4 | ~3.5 GB | Natural-language delivery control |
| Qwen CustomVoice 0.6B | Preset (9) | 4 | ~1.2 GB | Lighter variant |
| LuxTTS | Cloned | English | ~1 GB | 48kHz, 150x realtime on CPU |
| Chatterbox Multilingual | Cloned | 23 | ~3.5 GB | Broadest language coverage |
| Chatterbox Turbo | Cloned | English | ~1.5 GB | Paralinguistic tags, fast |
| TADA 1B | Cloned | 10 | ~4 GB | Long-form generation |
| TADA 3B | Cloned | 10 | ~8 GB | 700s+ coherent audio |
| Kokoro 82M | Preset (50) | 9 | ~150 MB | CPU realtime, smallest footprint |

## Engine Selection Guide

| If you want… | Pick |
|-------------|------|
| Best overall quality on common languages | Qwen3-TTS 1.7B |
| Faster generation, slightly lower quality | Qwen3-TTS 0.6B |
| Languages outside Qwen's 10 (Arabic, Hindi, etc.) | Chatterbox Multilingual |
| Expressive English with `[laugh]` `[sigh]` tags | Chatterbox Turbo |
| CPU-only or GPU-light setup, English | LuxTTS |
| Long-form generation (audiobooks, chapters) | TADA 3B |
| Smallest footprint, instant voices | Kokoro 82M |
| Delivery control (tone, pace, emotion) | Qwen CustomVoice |

## Voice Cloning

Zero-shot cloning from a short audio sample. No fine-tuning, no cloud upload.

### Reference Audio Requirements

- **Duration:** 10-30 seconds
- **Clarity:** clean speech, no background noise, no music
- **Quality:** 44.1/48 kHz sample rate preferred
- **Formats:** .wav (recommended), .mp3, .m4a, .flac

### Tips

- Trim silence from start/end
- Use speech from same recording session
- Avoid heavy background music or reverb
- Multiple diverse samples improve quality (different tones, content, conditions)
- All samples must be from the same speaker

### Cloning Engine Languages

| Engine | Languages |
|--------|-----------|
| Qwen3-TTS | English, Chinese, Japanese, Korean, French, German, Spanish, Italian, Portuguese, Arabic |
| Chatterbox Multilingual | English, Spanish, French, German, Italian, Portuguese, Polish, Turkish, Russian, Dutch, Czech, Arabic, Chinese, Japanese, Korean, Hungarian, Hindi, Finnish, Greek, Romanian, Swedish, Danish, Norwegian |
| Chatterbox Turbo | English |
| LuxTTS | English |
| TADA 3B | 10 multilingual; TADA 1B English |

## Preset Voices

### Kokoro 82M — 50 Voices

82M parameters, Apache 2.0 licensed, CPU realtime with ~150 MB.

**American English Female:** Alloy, Aoede, Bella, Heart, Jessica, Kore, Nicole, Nova, River, Sarah, Sky
**American English Male:** Adam, Echo, Eric, Fenrir, Liam, Michael, Onyx, Puck, Santa
**British English Female:** Alice, Emma, Isabella, Lily
**British English Male:** Daniel, Fable, George, Lewis

**Other Languages:**

| Language | Voices |
|----------|--------|
| Spanish | Dora (f), Alex (m), Santa (m) |
| French | Siwis (f) |
| Hindi | Alpha (f), Beta (f), Omega (m), Psi (m) |
| Italian | Sara (f), Nicola (m) |
| Japanese | Alpha (f), Gongitsune (f), Nezumi (f), Tebukuro (f), Kumo (m) |
| Portuguese | Dora (f), Alex (m), Santa (m) |
| Chinese | Xiaobei (f), Xiaoni (f), Xiaoxiao (f), Xiaoyi (f) |

### Qwen CustomVoice — 9 Premium Voices

Natural-language style control (instruct mode). Two sizes: 1.7B and 0.6B.

| Speaker | Gender | Language | Description |
|---------|--------|----------|-------------|
| Vivian | female | Chinese | Bright, slightly edgy young female |
| Serena | female | Chinese | Warm, gentle young female |
| Uncle Fu | male | Chinese | Seasoned, low, mellow timbre |
| Dylan | male | Chinese | Youthful Beijing, clear natural timbre |
| Eric | male | Chinese | Lively Chengdu, slightly husky brightness |
| Ryan | male | English | Dynamic, strong rhythmic drive (default) |
| Aiden | male | English | Sunny American, clear midrange |
| Ono Anna | female | Japanese | Playful, light nimble timbre |
| Sohee | female | Korean | Warm, rich emotion |

**Instruct mode examples:**
- "Speak slowly with emphasis, like reading bedtime stories"
- "Warm and friendly, conversational tone"
- "Professional and authoritative, broadcast quality"
- "Whisper, intimate and close"
- "Excited and energetic, like sports commentary"

## Performance Benchmarks

### Speed (approximate)

| Engine | CPU | GPU (RTX 3080) | Apple Silicon (M2) |
|--------|-----|----------------|-------------------|
| Kokoro 82M | ~1x realtime | ~10x | ~5x |
| Qwen3-TTS 0.6B | ~0.5x realtime | ~8x | ~4x |
| Qwen3-TTS 1.7B | ~0.2x realtime | ~6x | ~3x |
| LuxTTS | ~150x realtime | ~500x | ~200x |
| Chatterbox Turbo | ~1x realtime | ~8x | ~4x |
| TADA 1B | ~0.1x realtime | ~5x | ~3x |
| TADA 3B | ~0.05x realtime | ~3x | ~2x |

### Memory Requirements

| Engine | VRAM (GPU) | RAM (CPU) |
|--------|-----------|-----------|
| Kokoro 82M | ~150 MB | ~300 MB |
| LuxTTS | ~1 GB | ~2 GB |
| Qwen3-TTS 0.6B | ~1.2 GB | ~2.5 GB |
| Chatterbox Turbo | ~1.5 GB | ~3 GB |
| Qwen3-TTS 1.7B | ~3.5 GB | ~7 GB |
| Chatterbox Multilingual | ~3.5 GB | ~7 GB |
| TADA 1B | ~4 GB | ~8 GB |
| TADA 3B | ~8 GB | ~16 GB |

With 8GB VRAM: Kokoro + Qwen3-TTS 0.6B + LuxTTS + Chatterbox Turbo comfortably.

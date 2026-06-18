name: voicebox

description: Local-first AI voice studio — TTS, voice cloning, dictation, and MCP server for agent voice I/O. Use when generating speech, cloning voices, transcribing audio, setting up voice-enabled agents, configuring Voicebox MCP integration, or troubleshooting TTS issues. Triggers on mentions of Voicebox, voice cloning, text-to-speech, TTS, voice generation, dictation, voice profiles, speech synthesis, or local voice AI. Also use when the user asks about giving agents a voice, local TTS alternatives to ElevenLabs, or voice-first workflows.

# Voicebox Skill

Open-source, local-first AI voice studio. Free alternative to ElevenLabs (TTS/cloning) and WisprFlow (dictation). Everything runs on your hardware — no cloud, no API keys, no accounts.

**Repo:** github.com/jamiepine/voicebox
**Docs:** docs.voicebox.sh
**Default endpoint:** http://127.0.0.1:17493

## Decision Tree

### 1. Installation

**Desktop app (recommended):**
- macOS: download `.dmg` from GitHub releases
- Windows: download `.exe` installer
- Linux: download `.AppImage`, `chmod +x`, run

**Docker (headless/server):**
```bash
git clone https://github.com/jamiepine/voicebox.git
cd voicebox
docker compose up
```
Web UI at http://localhost:17493

First launch installs Python backend + dependencies (1-2 min). Green indicator = ready.

System requirements: 8 GB RAM minimum, 16 GB+ recommended. GPU optional but faster.

### 2. MCP Server Setup (Agent Integration)

Voicebox ships a built-in MCP server at `/mcp` over Streamable HTTP. No separate process needed.

**Claude Code:**
```bash
claude mcp add voicebox \
  --transport http \
  http://127.0.0.1:17493/mcp \
  --header "X-Voicebox-Client-Id: claude-code" \
  --scope user
```

**Claude Desktop** (`claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "voicebox": {
      "url": "http://127.0.0.1:17493/mcp"
    }
  }
}
```

**Cursor / Windsurf / VS Code** (`.mcp.json`):
```json
{
  "mcpServers": {
    "voicebox": {
      "url": "http://127.0.0.1:17493/mcp",
      "headers": { "X-Voicebox-Client-Id": "cursor" }
    }
  }
}
```

**Stdio shim** (for clients that don't speak HTTP):
```json
{
  "mcpServers": {
    "voicebox": {
      "command": "C:\\Program Files\\Voicebox\\voicebox-mcp.exe",
      "env": { "VOICEBOX_CLIENT_ID": "claude-desktop" }
    }
  }
}
```
Shim waits 30s for backend, then proxies JSON-RPC over HTTP.

**MCP Tools available:**

| Tool | What It Does |
|------|-------------|
| `voicebox.speak` | Speak text in a voice profile |
| `voicebox.transcribe` | Whisper transcription of audio |
| `voicebox.list_captures` | Recent captures with transcripts |
| `voicebox.list_profiles` | Available voice profiles |

For full tool schemas and parameters, read `references/mcp-server.md`.

### 3. Voice Profiles

Two types:

**Cloned** — provide 10-30s of clear speech, engine extracts a voice embedding:
- Qwen3-TTS 1.7B: best quality, 10 languages, ~3.5 GB VRAM
- Qwen3-TTS 0.6B: faster, lighter
- Chatterbox Multilingual: 23 languages
- Chatterbox Turbo: English, paralinguistic tags `[laugh]` `[sigh]`
- LuxTTS: English, CPU-friendly, 48kHz, 150x realtime
- TADA 3B: long-form (700s+ coherent), ~8 GB VRAM

**Preset** — pick from a built-in catalog, no audio needed:
- Kokoro 82M: 50 voices, 9 languages, CPU realtime, ~150 MB
- Qwen CustomVoice: 9 voices, instruct mode (tone/pace/emotion control)

For engine comparison tables and voice catalogs, read `references/engines-and-voices.md`.

### 4. Generating Speech

**Via MCP (agent):**
```python
voicebox.speak({
    "text": "Hello world",
    "profile": "Ryan",          # name or ID
    "engine": "qwen_custom_voice",  # optional override
    "personality": True,        # rewrite via LLM before TTS
    "language": "en"
})
```

**Via REST API (scripts, CI, etc.):**
```bash
curl -X POST http://127.0.0.1:17493/speak \
  -H 'Content-Type: application/json' \
  -H 'X-Voicebox-Client-Id: ci' \
  -d '{"text":"Build complete.","profile":"Morgan"}'
```

**Voice resolution order:**
1. Explicit `profile` name/ID in the request
2. Per-client binding (Voicebox → Settings → MCP)
3. Default playback voice

### 5. Voice Personalities

Optional LLM-powered layer on any voice profile. Three features:

- **Persona-rewrite:** rewrites input text in character before TTS (`personality: true`)
- **Compose:** generates fresh lines from a topic prompt, no input text needed
- **Style hint:** subtle influence on TTS prosody

Setup: Voices tab → profile → Personality section → write a free-form prompt.

LLM models: Qwen3 0.6B (~1.2 GB), 1.7B (~3.5 GB), 4B (~8 GB).

### 6. Dictation

Global hotkey, push-to-talk or toggle mode. Hold chord → speak → release → transcript lands in focused text field.

Setup: Settings → Dictation → set hotkey → grant permissions (macOS: Accessibility; Windows: none needed).

Refinement modes: Auto (default), Always, Off. Uses local Qwen3 LLM.

### 7. Transcription

```python
voicebox.transcribe({
    "audio_path": "/path/to/file.wav",  # or audio_base64
    "model": "turbo",  # base|small|medium|large|turbo
    "language": "en"
})
```

Models: Base (~300 MB, fast), Small (~500 MB), Medium (~1.5 GB), Large (~3 GB, best), Turbo (~1.5 GB, Large-quality at 5x speed).

### 8. Post-Processing Effects

Voicebox includes audio effects powered by Spotify's Pedalboard library:
- Pitch shift, reverb, delay, chorus, compression, filters
- Applied per-generation in the app UI

### 9. Stories Editor

Multi-track timeline for multi-voice narratives (podcasts, audiobooks, game dialogue):
- Up to 16 tracks, 60 min max
- Per-track voice profile assignment
- Generate-in-place or drag audio files
- Render to single .wav/.mp3

### 10. GPU Acceleration

| Platform | Backend | Notes |
|----------|---------|-------|
| macOS (Apple Silicon) | MLX (Metal) | Automatic, 4-5x speedup |
| Windows/Linux (NVIDIA) | CUDA | Auto-downloads CUDA PyTorch |
| Linux (AMD) | ROCm | Auto-configures |
| Windows (any GPU) | DirectML | Universal fallback |
| Intel Arc | IPEX/XPU | Experimental |
| Any | CPU | Works everywhere, slower |

Verify: Settings → Server → Backend Info, or `curl http://localhost:17493/health`.

### 11. Troubleshooting

Common issues:

- **Backend won't start:** check port 17493 not in use, check logs
- **No audio:** check system audio settings, try exporting .wav
- **CUDA OOM:** use smaller engine (Kokoro, Qwen 0.6B), close GPU apps
- **MCP not connecting:** ensure Voicebox app is running (backend only listens while app is open)
- **flash-attn warning:** harmless, PyTorch SDPA runs instead
- **First gen slow:** expected — model downloads on first use (350 MB to 8 GB)

For full troubleshooting, read `references/troubleshooting.md`.

### 12. Docker / Remote Mode

Docker for headless servers. Remote Mode to connect desktop app to a GPU server elsewhere.

Read `references/deployment.md` for Docker compose config, GPU passthrough, security, and cloud deployment guides.

## Security Notes

- Localhost only (127.0.0.1). No auth in 0.5.0 — bearer token on roadmap.
- Any local process can call the MCP endpoint. Same trust boundary as the REST API.
- Voice cloning consent applies regardless of how the clone is triggered.
- Never expose to non-trusted networks without a reverse proxy + auth.

## Reference Docs

| File | Contents |
|------|----------|
| `references/engines-and-voices.md` | TTS engines, voice cloning, preset voice catalogs, language tables |
| `references/mcp-server.md` | MCP tool schemas, per-client bindings, REST API, debugging |
| `references/dictation-and-captures.md` | Dictation setup, captures, recording, transcription |
| `references/personalities.md` | Voice personalities, persona-rewrite, compose mode |
| `references/deployment.md` | Docker, remote mode, GPU acceleration, cloud deployment |
| `references/stories-editor.md` | Multi-track timeline, tracks, clips, rendering |
| `references/troubleshooting.md` | Installation, generation, audio, model, and remote issues |

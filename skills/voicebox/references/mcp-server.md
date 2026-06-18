# MCP Server Reference

Voicebox ships a built-in MCP server. Any MCP-aware agent can call Voicebox directly — speak text, transcribe audio, list profiles and captures. Server runs inside the same process as the desktop app, mounted at `/mcp` over Streamable HTTP.

## Endpoint

```
http://127.0.0.1:17493/mcp
```

Transport: Streamable HTTP (Nov-2025 MCP spec). Supported by Claude Code, Cursor, Windsurf, VS Code MCP extensions.

## Quick Install

### Claude Code
```bash
claude mcp add voicebox \
  --transport http \
  http://127.0.0.1:17493/mcp \
  --header "X-Voicebox-Client-Id: claude-code" \
  --scope user
```

### Cursor / Windsurf / VS Code MCP
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

### Claude Desktop
```json
{
  "mcpServers": {
    "voicebox": {
      "url": "http://127.0.0.1:17493/mcp"
    }
  }
}
```

### Stdio Shim (clients that only speak stdio)

Bundled binary `voicebox-mcp`. Point client at absolute path:

**Windows:**
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

**macOS:**
```json
{
  "mcpServers": {
    "voicebox": {
      "command": "/Applications/Voicebox.app/Contents/MacOS/voicebox-mcp",
      "env": { "VOICEBOX_CLIENT_ID": "claude-desktop" }
    }
  }
}
```

Shim waits up to 30s for backend, then proxies JSON-RPC from stdio over Streamable HTTP.

## Tool Reference

### voicebox.speak

Speak text in a voice profile. Returns a generation_id to poll.

```javascript
voicebox.speak({
  text: "Deploy complete.",           // required
  profile: "Morgan",                  // name or ID; falls back to per-client binding
  engine: "qwen",                     // qwen | qwen_custom_voice | luxtts | chatterbox | chatterbox_turbo | tada | kokoro
  personality: true,                  // rewrite via profile's personality LLM before TTS
  language: "en"
})
```

Returns:
```json
{
  "generation_id": "...",
  "status": "generating",
  "profile": "Morgan",
  "source": "mcp",
  "poll_url": "/generate/<id>/status"
}
```

- `personality: false` (or omitted): text spoken as-is (plain TTS)
- `personality: true`: LLM rewrites text in character before TTS (profile must have a personality prompt set)

### voicebox.transcribe

```javascript
voicebox.transcribe({
  audio_base64: "<base64>",    // exactly one of these two
  audio_path: "/absolute/path/to/file.wav",
  language: "en",
  model: "turbo"               // base | small | medium | large | turbo
})
```

Returns `{ text, duration, language, model }`. 200 MB ceiling on input.

### voicebox.list_captures

```javascript
voicebox.list_captures({
  limit: 20,    // optional, clamped to 1..200
  offset: 0
})
```

Returns `{ captures: [...], total }`.

### voicebox.list_profiles

No arguments. Returns `{ profiles: [{ id, name, voice_type, language, has_personality }] }`.

## Voice Resolution Order

Every `voicebox.speak` call resolves the voice profile in this order:

1. **Explicit** — passed as name (case-insensitive) or ID. If name/ID doesn't match, errors (no silent fallback).
2. **Per-client binding** — looked up by `X-Voicebox-Client-Id` header. Managed in Voicebox → Settings → MCP.
3. **Default voice** — `capture_settings.default_playback_voice_id`.

If none produce a profile, returns a helpful error pointing at Settings.

## Per-Client Bindings

Voicebox → Settings → MCP shows one row per client_id that Voicebox has heard from.

| Field | Purpose |
|-------|---------|
| label | Display name in Settings UI |
| profile_id | Default voice when `profile` isn't passed |
| default_engine | Override TTS engine for this client |
| default_personality | When true, `voicebox.speak` routes through personality LLM by default |
| last_seen_at | Last request timestamp |

## Non-MCP REST API

`POST /speak` — thin wrapper on same code path, for shell scripts, CI, etc.:

```bash
curl -X POST http://127.0.0.1:17493/speak \
  -H 'Content-Type: application/json' \
  -H 'X-Voicebox-Client-Id: ci' \
  -d '{"text":"Build complete.","profile":"Morgan"}'
```

Body fields match MCP tool: `text`, `profile`, `engine`, `personality`, `language`.

## Speaking Pill

Every agent-initiated speak surfaces a floating pill showing profile name + elapsed timer. Intentionally unmissable — silent background TTS is a trust hazard.

## Debugging

Use MCP Inspector:
```bash
npx @modelcontextprotocol/inspector http://127.0.0.1:17493/mcp
```

Start with `voicebox.list_profiles` to confirm wiring, then `voicebox.speak` for end-to-end.

If agent can't reach server: check Voicebox app is running — backend only listens while desktop app is open.

## Security

- **Localhost only.** Binds to 127.0.0.1.
- **No auth in 0.5.0.** Any local process can call MCP. Bearer token on roadmap.
- **audio_path reads unrestricted** against same trust boundary. Prefer `audio_base64` on shared hosts.
- **Voice cloning consent applies** regardless of how the clone is triggered.

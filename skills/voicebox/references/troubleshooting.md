# Troubleshooting

## Installation Issues

### macOS: "App is damaged and can't be opened"
App isn't signed with Apple Developer certificate.
```bash
xattr -cr /Applications/Voicebox.app
```

### Windows: SmartScreen Warning
Click "More info" → "Run anyway". Expected for unsigned apps.

### Linux: AppImage Won't Run
```bash
chmod +x voicebox-*.AppImage
./voicebox-*.AppImage
```
Requires FUSE 2: `sudo apt install libfuse2`

## Server Issues

### Backend Won't Start
- Check port 17493 not in use: `lsof -i :17493` (macOS/Linux) or `netstat -ano | findstr 17493` (Windows)
- Check logs in app
- Red status indicator = server not running

### flash-attn Warning
```
"flash-attn is not installed. Will only run the manual PyTorch version."
```
**Harmless.** FlashAttention is optional. PyTorch SDPA runs instead.
- Windows: no official flash-attn support
- macOS (Apple Silicon): CUDA-only, MLX has own optimized kernels
- Linux: install manually if desired

## Generation Issues

### First Generation Very Slow
Expected — model downloads on first use. Sizes: 350 MB (Kokoro) to 8 GB (TADA 3B). Subsequent generations reuse cached model.

### Poor Voice Quality
- Use 10-30s of clear audio for cloning
- Avoid background noise
- Use proper punctuation in text
- Try different engine
- Add multiple samples for cloned profiles

### CUDA Out of Memory
- Use smaller engine (Kokoro ~150 MB, LuxTTS ~1 GB, Qwen 0.6B ~1.2 GB)
- Close other GPU applications
- Check `nvidia-smi` for VRAM usage

### MLX "Failed to load metallib" (Apple Silicon)
- Rebuild server binary
- Reinstall MLX dependencies
- Verify backend detection in Settings → Server → Backend Info

## Audio Issues

### No Audio Playback
- Check system audio output device
- Try exporting .wav and playing externally
- Check volume levels

### Crackling/Distortion
- Check input samples for distortion
- Reduce playback volume
- Re-generate with cleaner voice samples

## MCP Issues

### Agent Can't Reach Server
1. Verify Voicebox app is running (backend only listens while app is open)
2. Test endpoint: `curl http://127.0.0.1:17493/health`
3. Check MCP config has correct URL and transport type
4. Stdio shim: waits 30s then errors if backend not up

### Double Audio Playback
Check Voicebox Settings for auto-play settings on captures. May be playing generation + capture simultaneously.

## Model Issues

### Download Fails
- Check internet connection
- Check HuggingFace Hub status
- Try VPN if HuggingFace blocked
- Manual download:
```bash
pip install huggingface_hub
huggingface-cli download Qwen/Qwen3-TTS-12Hz-1.7B-Base
```

### Wrong Model Version
Clear cache and re-download:
```bash
# macOS/Linux
rm -rf ~/.cache/huggingface/hub/models--Qwen*
# Windows
rmdir /s %USERPROFILE%\.cache\huggingface\hub\models--Qwen*
```

## Database Issues

### "Database is locked"
Close all Voicebox instances. Delete lock files:
```bash
# macOS
rm ~/Library/Application\ Support/sh.voicebox.app/data/voicebox.db-shm
rm ~/Library/Application\ Support/sh.voicebox.app/data/voicebox.db-wal
```

### Corrupted Database
**WARNING: deletes all profiles and history. Export first.**
```bash
# macOS
rm ~/Library/Application\ Support/sh.voicebox.app/data/voicebox.db
# Windows
del %APPDATA%\sh.voicebox.app\data\voicebox.db
```

## Remote Mode Issues

### Can't Connect
```bash
curl http://<server-ip>:17493/health
# Should return {"status": "ok"}
```
Check firewall, port 17493 open, both machines on same network.

## Performance Issues

### Slow on GPU
- First generation always slower (model loading into VRAM)
- Check thermal throttling: `nvidia-smi dmon`
- Verify GPU detected: Settings → Server → Backend Info

### High Memory Usage
- Close unused voice profiles
- Clear generation history
- Restart app periodically

## Diagnostic Info

```bash
# OS info
uname -a          # macOS/Linux
systeminfo        # Windows

# GPU
nvidia-smi        # NVIDIA

# Voicebox health
curl http://localhost:17493/health
```

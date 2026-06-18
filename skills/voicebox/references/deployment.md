# Deployment — Docker, Remote Mode, GPU

## Docker Deployment

Run Voicebox as a headless server with web UI.

### Quick Start

```bash
git clone https://github.com/jamiepine/voicebox.git
cd voicebox
docker compose up
```

Web UI at http://localhost:17493. First build takes a few minutes (frontend compile + Python deps). Subsequent starts are fast.

### docker-compose.yml

```yaml
services:
  voicebox:
    build: .
    container_name: voicebox
    restart: unless-stopped
    ports:
      - "127.0.0.1:17493:17493"
    volumes:
      - ./output:/app/data/generations
      - voicebox-data:/app/data
      - huggingface-cache:/home/voicebox/.cache/huggingface
    environment:
      - LOG_LEVEL=info
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G
```

### Expose to Network

Change port binding to `"0.0.0.0:17493:17493"`. No built-in auth — only expose to trusted networks or put a reverse proxy with auth in front.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| LOG_LEVEL | info | debug, info, warning, error |
| VOICEBOX_MODELS_DIR | (HuggingFace cache) | Custom model storage path |
| VOICEBOX_CORS_ORIGINS | (local origins) | Additional CORS origins |

### GPU in Docker

**NVIDIA (CUDA):**
```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: 1
          capabilities: [gpu]
```

**AMD (ROCm):**
```yaml
devices:
  - /dev/kfd
  - /dev/dri
group_add:
  - video
```

### Volumes

| Volume | Container Path | Purpose |
|--------|---------------|---------|
| ./output | /app/data/generations | Generated audio (bind-mount) |
| voicebox-data | /app/data | Profiles, database, cache |
| huggingface-cache | /home/voicebox/.cache/huggingface | Models (persists across rebuilds) |

Without huggingface-cache volume, models re-download on every rebuild.

### Security

- Non-root user (voicebox)
- Localhost binding by default
- Health checks at /health every 30s
- CORS restricted to local origins

### Reverse Proxy (Production)

```nginx
server {
    listen 443 ssl;
    server_name voicebox.example.com;
    ssl_certificate /etc/ssl/certs/voicebox.pem;
    ssl_certificate_key /etc/ssl/private/voicebox.key;
    auth_basic "Voicebox";
    auth_basic_user_file /etc/nginx/.htpasswd;
    location / {
        proxy_pass http://127.0.0.1:17493;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## Remote Mode

Connect desktop app to a backend on another machine (home server, cloud GPU, shared workstation).

### Server Setup

**Docker (recommended):**
```bash
docker compose up
```

**Bare Python:**
```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 17493
```

Ensure port 17493 is open.

### Client Setup

Settings → Server → Enable Remote Mode → enter `http://<server-ip>:17493` → Connect.

### Cloud Deployment

**AWS EC2:** g4dn.xlarge+, install Docker, clone repo, `docker compose up`, open port 17493 (restrict to your IP).

**Vast.ai:** PyTorch instance, expose port 17493, `docker compose up`.

**RunPod:** GPU pod with PyTorch, add port 17493, `docker compose up`.

### Performance

| Network | Additional Latency |
|---------|-------------------|
| LAN (gigabit) | <100ms |
| WAN (VPN) | 100-300ms |
| Cloud (same region) | 50-150ms |

Audio streams in chunks — playback starts before full file transfers.

## GPU Acceleration

| Platform | Backend | Notes |
|----------|---------|-------|
| macOS (Apple Silicon) | MLX (Metal) | Automatic, 4-5x speedup |
| Windows/Linux (NVIDIA) | CUDA | Auto-downloads CUDA PyTorch. Requires compute 7.0+, driver 520+ |
| Linux (AMD) | ROCm 5.6+ | Auto-configures HSA_OVERRIDE_GFX_VERSION |
| Windows (any GPU) | DirectML | Universal fallback, slower than CUDA |
| Intel Arc | IPEX/XPU | Linux supported, Windows experimental |
| Any | CPU | Always works, slower |

Verify: Settings → Server → Backend Info, or `curl http://localhost:17493/health`.

### Manual CUDA Install

```bash
cd backend
source venv/bin/activate
pip install torch --index-url https://download.pytorch.org/whl/cu121
```

## Data Locations

| Platform | Path |
|----------|------|
| macOS | ~/Library/Application Support/sh.voicebox.app/ |
| Windows | %APPDATA%\sh.voicebox.app\ |
| Linux | ~/.local/share/sh.voicebox.app/ |
| Docker | /app/data/ (+ bind-mount ./output for generations) |

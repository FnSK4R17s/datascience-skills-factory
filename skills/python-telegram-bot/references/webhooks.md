# Webhooks

## How Telegram webhooks work

Instead of your bot polling `getUpdates`, Telegram pushes each update as an
HTTPS POST request to a URL you register. Requirements:

1. The URL must be reachable by Telegram's servers (public, not `localhost`).
2. The URL must use HTTPS with a valid TLS certificate (self-signed accepted if
   you pass the certificate to `set_webhook`; CA-signed is simpler).
3. Port must be one of: 443, 80, 88, 8443.

## PTB built-in webhook server

The simplest option — PTB runs its own HTTPS server (via `aiohttp`):

```python
app.run_webhook(
    listen="0.0.0.0",
    port=8443,
    url_path="/webhook",
    webhook_url="https://yourdomain.com/webhook",
    secret_token="a-random-string-you-choose",   # optional but recommended
    # cert="path/to/cert.pem",                   # only for self-signed certs
    # key="path/to/key.pem",
)
```

PTB sets the webhook with Telegram automatically when `webhook_url` is
provided. If you manage webhook registration separately, omit `webhook_url`.

## Secret token

Pass `secret_token` to `run_webhook()` and set the same value in
`setWebhook`. Telegram includes it as `X-Telegram-Bot-Api-Secret-Token`
header on every request. PTB validates the header and rejects requests that
omit or mismatch it. This prevents spoofed updates from non-Telegram senders.

## Integrating with FastAPI (ASGI)

Use PTB's `Application` as a handler inside a FastAPI app when you need to
share the same HTTP server (e.g. mixing a REST API and a bot):

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, Response
from telegram import Update
from telegram.ext import ApplicationBuilder

ptb_app = ApplicationBuilder().token(TOKEN).build()

@asynccontextmanager
async def lifespan(app: FastAPI):
    await ptb_app.initialize()
    await ptb_app.start()
    yield
    await ptb_app.stop()
    await ptb_app.shutdown()

fastapi_app = FastAPI(lifespan=lifespan)

@fastapi_app.post("/webhook")
async def telegram_webhook(request: Request) -> Response:
    body = await request.json()
    secret = request.headers.get("X-Telegram-Bot-Api-Secret-Token", "")
    if secret != EXPECTED_SECRET:
        return Response(status_code=403)
    update = Update.de_json(body, ptb_app.bot)
    await ptb_app.process_update(update)
    return Response(status_code=200)
```

Key points:
- `ptb_app.initialize()` + `ptb_app.start()` in lifespan startup.
- `ptb_app.process_update(update)` dispatches to registered handlers.
- `ptb_app.stop()` + `ptb_app.shutdown()` in lifespan shutdown.
- Do NOT call `run_webhook()` or `run_polling()` — they block and own the loop.

## Local development with webhooks

Telegram cannot reach `localhost`. Options:

- Use polling during development (`run_polling()`) — simplest.
- Use a tunneling service (e.g. ngrok, bore, cloudflared tunnel) to expose
  a local port via a public HTTPS URL.
- Deploy to a staging environment that has a real public URL.

Do not hardcode tunnel URLs — they change. Keep them in environment variables.

## Webhook registration and deletion

```python
# Set webhook manually (PTB also does this if you pass webhook_url to run_webhook)
await app.bot.set_webhook(
    url="https://yourdomain.com/webhook",
    secret_token="your-secret",
)

# Check current webhook status
info = await app.bot.get_webhook_info()
print(info.url, info.pending_update_count)

# Delete webhook (switch back to polling)
await app.bot.delete_webhook()
```

Switching between polling and webhook: always delete the webhook before
calling `run_polling()`, otherwise `getUpdates` returns an error.

## Common webhook problems

| Symptom | Likely cause |
|---------|-------------|
| No updates received | Webhook URL not set, or certificate invalid |
| `409 Conflict` on `getUpdates` | Webhook still set; call `delete_webhook()` first |
| Updates arriving twice | Two bot instances running (one polling, one webhook) |
| `403 Forbidden` from your server | Secret token mismatch or IP allowlist blocking Telegram |

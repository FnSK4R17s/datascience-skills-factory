# Webhooks

Sources: `telegram.webhookinfo.rst`, `telegram.ext.updater.rst`,
`examples.customwebhookbot.rst`, `examples.rst`.

## How Telegram webhooks work

Instead of polling `getUpdates`, Telegram pushes each update as an HTTPS POST
to a URL you register. Requirements:

1. URL must be publicly reachable by Telegram's servers.
2. URL must use HTTPS (self-signed cert accepted if passed to `set_webhook`;
   CA-signed is simpler).
3. Port must be one of: 443, 80, 88, 8443.

## PTB built-in webhook server

The simplest option — PTB runs its own HTTPS server (via `aiohttp`):

```python
app.run_webhook(
    listen="0.0.0.0",
    port=8443,
    url_path="/webhook",
    webhook_url="https://yourdomain.com/webhook",
    secret_token="a-random-string-you-choose",
    # cert="path/to/cert.pem",   # only for self-signed certs
    # key="path/to/key.pem",
)
```

PTB registers the webhook with Telegram automatically when `webhook_url` is
provided. Omit `webhook_url` if you manage webhook registration separately.

## Secret token

Pass `secret_token` to `run_webhook()` and configure the same value in
`set_webhook`. Telegram includes it as `X-Telegram-Bot-Api-Secret-Token`
header on every request. PTB validates and rejects mismatched requests.
This prevents spoofed updates.

## Integrating with FastAPI (ASGI)

Use when you need to share one HTTP server between a REST API and a bot.
Do NOT call `run_polling()` or `run_webhook()` in this mode.
(Source: `examples.customwebhookbot.rst`, `inclusions__application_run_tip.rst`)

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
- `initialize()` + `start()` in lifespan startup.
- `process_update(update)` dispatches to registered handlers.
- `stop()` + `shutdown()` in lifespan teardown.

## Local development with webhooks

Telegram cannot reach `localhost`. Options:
- Use `run_polling()` during development — simplest.
- Use a tunneling tool (ngrok, bore, cloudflared) to expose a local port.

Do not hardcode tunnel URLs — they change. Store in environment variables.

## Webhook registration and deletion

```python
# Register manually
await app.bot.set_webhook(
    url="https://yourdomain.com/webhook",
    secret_token="your-secret",
)

# Check current status
info = await app.bot.get_webhook_info()
print(info.url, info.pending_update_count)

# Delete (switch back to polling)
await app.bot.delete_webhook()
```

Always call `delete_webhook()` before switching to polling — an active webhook
causes `getUpdates` to return a `409 Conflict`.

## Common webhook problems

| Symptom | Likely cause |
|---------|-------------|
| No updates received | Webhook URL not set or certificate invalid |
| `409 Conflict` on `getUpdates` | Webhook still set; call `delete_webhook()` |
| Updates arriving twice | Two bot instances running simultaneously |
| `403 Forbidden` from your server | Secret token mismatch |

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

The simplest production option — PTB runs its own HTTP server (via `aiohttp`):

```python
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

TOKEN = "YOUR_BOT_TOKEN"
WEBHOOK_URL = "https://yourdomain.com"
PORT = 8443
WEBHOOK_PATH = "/webhook"
SECRET_TOKEN = "a-random-string-you-choose"


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text("Hello!")


def main() -> None:
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start", start))

    app.run_webhook(
        listen="0.0.0.0",
        port=PORT,
        url_path=WEBHOOK_PATH,
        webhook_url=f"{WEBHOOK_URL}{WEBHOOK_PATH}",
        secret_token=SECRET_TOKEN,
        drop_pending_updates=True,
        # cert="path/to/cert.pem",   # only for self-signed certs
        # key="path/to/key.pem",
    )


if __name__ == "__main__":
    main()
```

PTB registers the webhook with Telegram automatically when `webhook_url` is
provided. The built-in server handles TLS termination if you pass `cert` and `key`.

In most production setups, a reverse proxy (nginx, Caddy) handles TLS and
forwards plain HTTP to PTB on a non-public port.

## Secret token

Pass `secret_token` to `run_webhook()`. Telegram includes it as
`X-Telegram-Bot-Api-Secret-Token` header on every request. PTB validates and
rejects requests with a missing or wrong token. This prevents spoofed updates.

```python
app.run_webhook(
    ...,
    secret_token="my-super-secret-token-32chars",
)
```

Same token must be used in `set_webhook` if registered manually:

```python
await app.bot.set_webhook(
    url="https://yourdomain.com/webhook",
    secret_token="my-super-secret-token-32chars",
)
```

## Manual webhook registration

```python
import asyncio

async def register():
    async with Application.builder().token(TOKEN).build() as app:
        await app.bot.set_webhook(
            url="https://yourdomain.com/webhook",
            secret_token="my-secret",
            allowed_updates=["message", "callback_query", "inline_query"],
            max_connections=100,    # Telegram connects up to this many simultaneously
            drop_pending_updates=True,
        )
        info = await app.bot.get_webhook_info()
        print(f"Webhook: {info.url}")
        print(f"Pending: {info.pending_update_count}")

asyncio.run(register())
```

## Delete webhook (switch back to polling)

```python
async def clear():
    async with Application.builder().token(TOKEN).build() as app:
        await app.bot.delete_webhook(drop_pending_updates=True)
        print("Webhook deleted. Safe to use polling now.")

asyncio.run(clear())
```

Always call `delete_webhook()` before switching to polling — an active webhook
causes `getUpdates` to return `409 Conflict`.

## FastAPI integration

Use when you need to share one HTTP server between a REST API and a bot.
Do NOT call `run_polling()` or `run_webhook()` — they block forever.

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, Response
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

TOKEN = "YOUR_BOT_TOKEN"
WEBHOOK_URL = "https://yourdomain.com/telegram"
WEBHOOK_SECRET = "secret-token"

# Build PTB app (no token conflict with FastAPI)
ptb_app = Application.builder().token(TOKEN).build()

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text("Hi from FastAPI bot!")

ptb_app.add_handler(CommandHandler("start", start))


@asynccontextmanager
async def lifespan(fastapi_app: FastAPI):
    # Startup
    await ptb_app.initialize()
    await ptb_app.start()
    await ptb_app.bot.set_webhook(url=WEBHOOK_URL, secret_token=WEBHOOK_SECRET)
    yield
    # Shutdown
    await ptb_app.stop()
    await ptb_app.shutdown()


app = FastAPI(lifespan=lifespan)


@app.post("/telegram")
async def telegram_webhook(request: Request) -> Response:
    secret = request.headers.get("X-Telegram-Bot-Api-Secret-Token", "")
    if secret != WEBHOOK_SECRET:
        return Response(status_code=403)
    body = await request.json()
    update = Update.de_json(body, ptb_app.bot)
    await ptb_app.process_update(update)
    return Response(status_code=200)


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}
```

Run with: `uvicorn mybot:app --host 0.0.0.0 --port 8080`

## Starlette integration

```python
from contextlib import asynccontextmanager
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import Response
from starlette.routing import Route
from telegram import Update
from telegram.ext import Application

TOKEN = "YOUR_BOT_TOKEN"
WEBHOOK_URL = "https://yourdomain.com/webhook"
SECRET = "my-secret"

ptb_app = Application.builder().token(TOKEN).build()
ptb_app.add_handler(...)  # add handlers


async def telegram_webhook(request: Request) -> Response:
    secret = request.headers.get("X-Telegram-Bot-Api-Secret-Token", "")
    if secret != SECRET:
        return Response(status_code=403)
    data = await request.json()
    update = Update.de_json(data, ptb_app.bot)
    await ptb_app.process_update(update)
    return Response()


async def startup() -> None:
    await ptb_app.initialize()
    await ptb_app.start()
    await ptb_app.bot.set_webhook(url=WEBHOOK_URL, secret_token=SECRET)


async def shutdown() -> None:
    await ptb_app.stop()
    await ptb_app.shutdown()


starlette_app = Starlette(
    routes=[Route("/webhook", telegram_webhook, methods=["POST"])],
    on_startup=[startup],
    on_shutdown=[shutdown],
)
```

## Flask integration

Flask is WSGI, but with the `asgiref` or `quart` adapters you can run it
alongside an async PTB. The recommended Flask approach uses Quart (async Flask):

```python
# quartbot.py — uses Quart (async Flask)
from quart import Quart, request, Response
from telegram import Update
from telegram.ext import Application

TOKEN = "YOUR_BOT_TOKEN"
WEBHOOK_URL = "https://yourdomain.com/webhook"
SECRET = "my-secret"

ptb_app = Application.builder().token(TOKEN).build()
ptb_app.add_handler(...)

quart_app = Quart(__name__)


@quart_app.before_serving
async def startup():
    await ptb_app.initialize()
    await ptb_app.start()
    await ptb_app.bot.set_webhook(url=WEBHOOK_URL, secret_token=SECRET)


@quart_app.after_serving
async def shutdown():
    await ptb_app.stop()
    await ptb_app.shutdown()


@quart_app.post("/webhook")
async def webhook():
    secret = request.headers.get("X-Telegram-Bot-Api-Secret-Token", "")
    if secret != SECRET:
        return Response(status_code=403)
    data = await request.get_json()
    update = Update.de_json(data, ptb_app.bot)
    await ptb_app.process_update(update)
    return Response()
```

Run with: `hypercorn quartbot:quart_app --bind 0.0.0.0:8080`

(Source: `examples.customwebhookbot.rst`)

## Local development with webhooks

Telegram cannot reach `localhost`. Options:

1. **Use `run_polling()` during development** — simplest, no tunnel needed.
2. **Ngrok**: `ngrok http 8443` → use the `https://<id>.ngrok.io` URL.
3. **Cloudflared**: `cloudflared tunnel --url http://localhost:8443`
4. **bore**: `bore local 8443 --to bore.pub`

Do not hardcode tunnel URLs — they change on each restart.
Store in environment variables:

```python
import os
WEBHOOK_URL = os.environ["WEBHOOK_URL"]   # set to ngrok URL in dev, real domain in prod
```

## Checking webhook status

```python
async def check_webhook():
    async with Application.builder().token(TOKEN).build() as app:
        info = await app.bot.get_webhook_info()
        print(f"URL: {info.url}")
        print(f"Pending updates: {info.pending_update_count}")
        print(f"Last error: {info.last_error_message}")
        print(f"Last error date: {info.last_error_date}")
        print(f"Max connections: {info.max_connections}")
        print(f"Allowed updates: {info.allowed_updates}")

import asyncio
asyncio.run(check_webhook())
```

## Common webhook problems

| Symptom | Likely cause | Fix |
|---|---|---|
| No updates received | Webhook URL not set, or wrong URL | Check `get_webhook_info()`, re-register |
| Certificate error | Self-signed cert not passed | Pass `cert=` to `set_webhook` or use CA cert |
| `409 Conflict` on `getUpdates` | Webhook still set | Call `delete_webhook()` |
| Updates arriving twice | Two bot instances running | Stop the duplicate; ensure single instance |
| `403 Forbidden` from your server | Secret token mismatch | Check `X-Telegram-Bot-Api-Secret-Token` header |
| Updates delayed | `pending_update_count` growing | Check server health, increase `max_connections` |
| `InvalidToken` on startup | Wrong token | Double-check token from BotFather |

## nginx reverse proxy setup

Put nginx in front of PTB's built-in server for TLS termination:

```nginx
# /etc/nginx/sites-available/mybot
server {
    listen 443 ssl;
    server_name yourdomain.com;

    ssl_certificate     /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    location /webhook {
        proxy_pass http://127.0.0.1:8443;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Telegram-Bot-Api-Secret-Token $http_x_telegram_bot_api_secret_token;
    }
}
```

With this setup, PTB listens on `localhost:8443` (plain HTTP), nginx handles TLS.
Call `run_webhook(listen="127.0.0.1", port=8443, url_path="/webhook")` without
passing `cert`/`key` — nginx handles the certificate.

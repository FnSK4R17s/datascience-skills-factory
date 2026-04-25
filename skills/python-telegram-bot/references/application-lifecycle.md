# Application Lifecycle

Sources: `telegram.ext.application.rst`, `telegram.ext.applicationbuilder.rst`,
`telegram.ext.updater.rst`, `inclusions__application_run_tip.rst`,
`inclusions__pool_size_tip.rst`, `examples.customwebhookbot.rst`.

## The v20+ entry point

`Application` is the central object. Build it via `ApplicationBuilder` — never
construct it directly. `ApplicationBuilder` uses the builder pattern: each method
returns `self` for chaining.

```python
from telegram.ext import Application, ApplicationBuilder

app = (
    ApplicationBuilder()
    .token("YOUR_BOT_TOKEN")      # required
    .build()
)
```

Register handlers before starting, then call `run_polling()` or `run_webhook()`:

```python
from telegram.ext import CommandHandler, MessageHandler, filters

async def start(update, context):
    await update.message.reply_text("Hello!")

app.add_handler(CommandHandler("start", start))
app.run_polling()          # blocks until SIGINT/SIGTERM
```

## ApplicationBuilder options — full reference

`ApplicationBuilder` is the only way to create an `Application`. Every option
is set by chaining method calls before `.build()`.

```python
from telegram.ext import ApplicationBuilder, PicklePersistence, ContextTypes, AIORateLimiter

persistence = PicklePersistence(filepath="bot.pickle")

app = (
    ApplicationBuilder()
    .token("BOT_TOKEN")

    # Lifecycle hooks (see below)
    .post_init(on_startup)
    .post_stop(on_stop)
    .post_shutdown(on_shutdown)

    # Persistence
    .persistence(persistence)

    # Concurrency (tune these together for high-load bots)
    .concurrent_updates(32)           # how many updates process in parallel
    .connection_pool_size(32)         # HTTP pool size — should >= concurrent_updates
    .pool_timeout(10.0)               # seconds to wait for free connection

    # Rate limiting
    .rate_limiter(AIORateLimiter(max_retries=5))

    # Arbitrary callback data (requires [callback-data] extra)
    .arbitrary_callback_data(True)

    # Custom context types
    .context_types(ContextTypes(user_data=MyUserData))

    # Private key for Telegram Passport decryption
    .private_key(open("private.key", "rb").read())

    # Telegram Passport proxy settings
    .proxy_url("socks5://user:pass@host:port")

    .build()
)
```

## Polling mode

For local development and simple deployments. PTB long-polls `getUpdates` in a loop.

```python
from telegram import Update

app.run_polling(
    allowed_updates=Update.ALL_TYPES,  # which update types to receive
    poll_interval=0.0,                 # seconds between polls (default: 0)
    timeout=10,                        # getUpdates long-poll timeout in seconds
    drop_pending_updates=True,         # ignore updates that piled up while offline
)
```

Always call `delete_webhook()` before switching to polling — an active webhook
causes `getUpdates` to return `409 Conflict`.

```python
# One-shot cleanup before first run
import asyncio

async def clear_webhook():
    async with app:
        await app.bot.delete_webhook(drop_pending_updates=True)

asyncio.run(clear_webhook())  # safe here: not inside a running event loop
```

## Webhook mode

Telegram pushes each update via HTTPS POST to your URL. Requirements:

1. URL must be publicly reachable by Telegram's servers.
2. Must use HTTPS (self-signed cert accepted if passed in `cert=`).
3. Port must be one of: 443, 80, 88, 8443.

```python
app.run_webhook(
    listen="0.0.0.0",                         # bind address
    port=8443,                                 # listen port
    url_path="/webhook",                       # path component of the URL
    webhook_url="https://yourdomain.com/webhook",  # full public URL (registers automatically)
    secret_token="a-random-string-you-choose", # validates X-Telegram-Bot-Api-Secret-Token
    drop_pending_updates=True,                 # clear queue on startup
    # cert="path/to/cert.pem",  # only for self-signed certs
    # key="path/to/key.pem",
)
```

PTB registers the webhook with Telegram automatically when `webhook_url` is
provided. To manage webhook registration separately, omit `webhook_url`.

## Startup and shutdown hooks

Four lifecycle hook points — all are builder methods that accept an `async def` coroutine:

```python
async def on_startup(app: Application) -> None:
    """Runs after initialize() completes, before the bot starts processing updates."""
    app.bot_data["db"] = await create_db_connection()
    await app.bot.send_message(chat_id=ADMIN_ID, text="Bot online")

async def on_stop(app: Application) -> None:
    """Runs after stop() completes — updates are no longer processed."""
    await app.bot.send_message(chat_id=ADMIN_ID, text="Stopped")

async def on_shutdown(app: Application) -> None:
    """Runs after shutdown() completes — connections are closed."""
    await app.bot_data["db"].close()

app = (
    ApplicationBuilder()
    .token(TOKEN)
    .post_init(on_startup)        # runs after app.initialize()
    .post_stop(on_stop)           # runs after app.stop()
    .post_shutdown(on_shutdown)   # runs after app.shutdown()
    .build()
)
```

| Builder method | When it runs |
|---|---|
| `post_init` | After `app.initialize()` — safe to call Bot methods |
| `post_stop` | After `app.stop()` — no more updates processed |
| `post_shutdown` | After `app.shutdown()` — HTTP connections closed |

## Graceful shutdown

`run_polling()` and `run_webhook()` install signal handlers for `SIGINT`
(Ctrl+C) and `SIGTERM`. The shutdown sequence:

1. Stop accepting new updates.
2. Finish all in-flight update handlers.
3. Cancel pending jobs (JobQueue).
4. Call `post_stop` hook.
5. Flush persistence to disk / database.
6. Close HTTP connections.
7. Call `post_shutdown` hook.

Do not install your own `SIGINT`/`SIGTERM` handlers — they fight with PTB's.
Use the hooks above to run cleanup code.

To stop the bot from within a handler or job:

```python
async def admin_stop(update, context):
    await update.message.reply_text("Shutting down...")
    context.application.stop_running()   # signals run_polling/run_webhook to exit
```

(Source: `inclusions__application_run_tip.rst`)

## Manual lifecycle — integrating with external asyncio frameworks

When combining PTB with FastAPI, Starlette, or any other asyncio framework,
`run_polling()` and `run_webhook()` are the wrong choice — they block the event
loop. Use the manual lifecycle instead.

### Pattern 1: `async with Application`

The context manager handles `initialize()` / `shutdown()` automatically:

```python
import asyncio
from telegram import Update
from telegram.ext import ApplicationBuilder

TOKEN = "BOT_TOKEN"

async def polling_with_other_tasks():
    app = ApplicationBuilder().token(TOKEN).build()
    app.add_handler(...)  # add handlers first

    async with app:
        await app.updater.start_polling()
        await app.start()

        # do other async work here
        await asyncio.sleep(60)

        await app.updater.stop()
        await app.stop()

asyncio.run(polling_with_other_tasks())
```

### Pattern 2: FastAPI lifespan

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, Response
from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler

TOKEN = "BOT_TOKEN"
WEBHOOK_SECRET = "a-random-string-you-choose"

ptb_app = ApplicationBuilder().token(TOKEN).build()
ptb_app.add_handler(CommandHandler("start", start))

@asynccontextmanager
async def lifespan(fastapi_app: FastAPI):
    # Startup: initialize PTB and register webhook
    await ptb_app.initialize()
    await ptb_app.start()
    await ptb_app.bot.set_webhook(
        url="https://yourdomain.com/webhook",
        secret_token=WEBHOOK_SECRET,
    )
    yield
    # Shutdown: clean up PTB
    await ptb_app.stop()
    await ptb_app.shutdown()

fastapi_app = FastAPI(lifespan=lifespan)

@fastapi_app.post("/webhook")
async def telegram_webhook(request: Request) -> Response:
    secret = request.headers.get("X-Telegram-Bot-Api-Secret-Token", "")
    if secret != WEBHOOK_SECRET:
        return Response(status_code=403)
    body = await request.json()
    update = Update.de_json(body, ptb_app.bot)
    await ptb_app.process_update(update)
    return Response(status_code=200)
```

Key points for manual lifecycle:
- `initialize()` + `start()` in startup. `stop()` + `shutdown()` in teardown.
- `process_update(update)` dispatches to registered handlers.
- Do NOT call `run_polling()` or `run_webhook()` — they block forever.

(Source: `examples.customwebhookbot.rst`, `inclusions__application_run_tip.rst`)

## Connection pool and concurrency tuning

When using concurrent updates (`block=False`, `create_task`, `concurrent_updates`,
or `JobQueue`), multiple coroutines call the Bot API simultaneously. The three
parameters must be tuned together to avoid pool timeouts:

(Source: `inclusions__pool_size_tip.rst`)

```python
app = (
    ApplicationBuilder()
    .token(TOKEN)
    .concurrent_updates(32)        # max updates processed simultaneously
    .connection_pool_size(32)      # HTTP pool — set >= concurrent_updates
    .pool_timeout(10.0)            # seconds to wait for a free connection
    .build()
)
```

Rule of thumb:
- `connection_pool_size` must be >= `concurrent_updates` + number of background jobs
  that might run simultaneously.
- If pool exhaustion still occurs under load, raise `pool_timeout` first, then
  `connection_pool_size`.
- A `TimedOut` error under high load usually means pool exhaustion, not a real
  network timeout.

## Setting bot commands (BotFather menu)

Register the bot's command list so Telegram shows autocomplete:

```python
from telegram import BotCommand

async def set_commands(app: Application) -> None:
    await app.bot.set_my_commands([
        BotCommand("start", "Start the bot"),
        BotCommand("help", "Show help"),
        BotCommand("settings", "Change settings"),
    ])

app = (
    ApplicationBuilder()
    .token(TOKEN)
    .post_init(set_commands)
    .build()
)
```

## Defaults — setting global send parameters

```python
from telegram.ext import Defaults
from telegram.constants import ParseMode

defaults = Defaults(
    parse_mode=ParseMode.HTML,    # all reply_text calls use HTML by default
    tzinfo=pytz.timezone("UTC"), # timezone for JobQueue
    block=False,                  # all handlers run non-blocking by default
)

app = ApplicationBuilder().token(TOKEN).defaults(defaults).build()
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `asyncio.run(app.run_polling(...))` inside running event loop | Never nest — PTB creates its own loop |
| Registering handlers after `run_polling()` starts | Register all handlers before calling `run_*` |
| Switching polling→webhook without `delete_webhook()` | Call `delete_webhook()` first |
| `connection_pool_size` < `concurrent_updates` | Set them equal or pool > updates |
| Calling Bot methods in `__init__` before `initialize()` | Use `post_init` hook |

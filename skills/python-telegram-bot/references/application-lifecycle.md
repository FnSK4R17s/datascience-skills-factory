# Application Lifecycle

## The v20+ entry point

`Application` replaced `Updater` as the central object. Build it with
`ApplicationBuilder` — never construct it directly.

```python
from telegram.ext import ApplicationBuilder

app = (
    ApplicationBuilder()
    .token("BOT_TOKEN")
    .build()
)
```

Add handlers, then start:

```python
app.add_handler(handler)
app.run_polling()          # blocks until SIGINT/SIGTERM
# OR
app.run_webhook(listen="0.0.0.0", port=8443, url_path="/webhook")
```

## Polling vs webhook

| Mode | When to use |
|------|-------------|
| `run_polling()` | Local dev, simple deployments, no public URL required |
| `run_webhook()` | Production; Telegram pushes updates rather than the bot pulling |

Polling is simpler to start with. Switch to webhook when you need lower latency
or when running on a platform that bills per outbound connection (e.g. some
serverless hosts).

## Startup and shutdown hooks

Register coroutines that run after the bot starts receiving updates but before
it stops:

```python
async def on_startup(app):
    # called after app.initialize() and before run_polling/run_webhook loop
    await app.bot.send_message(chat_id=ADMIN_ID, text="Bot online")

async def on_shutdown(app):
    await app.bot.send_message(chat_id=ADMIN_ID, text="Bot shutting down")

app = (
    ApplicationBuilder()
    .token("BOT_TOKEN")
    .post_init(on_startup)
    .post_shutdown(on_shutdown)
    .build()
)
```

Hooks available on `ApplicationBuilder`:

| Builder method | Runs |
|----------------|------|
| `post_init` | After `app.initialize()` completes |
| `post_stop` | After `app.stop()` completes |
| `post_shutdown` | After `app.shutdown()` completes |

## Graceful shutdown

`run_polling()` and `run_webhook()` install signal handlers for `SIGINT`
(Ctrl+C) and `SIGTERM`. They:
1. Stop accepting new updates.
2. Finish processing in-flight updates.
3. Call `post_stop` and `post_shutdown` hooks.
4. Flush persistence (if configured).

Do not install your own `SIGINT`/`SIGTERM` handlers — PTB's are correct and
composable via the hooks above.

## Running without blocking (advanced)

If you must integrate into an existing event loop (e.g. a FastAPI app managing
its own loop), use the lower-level async context manager instead of `run_*`:

```python
async with ApplicationBuilder().token(TOKEN).build() as app:
    await app.updater.start_polling()
    await app.start()
    # ... your other code ...
    await app.updater.stop()
    await app.stop()
```

This is advanced usage; prefer `run_polling()` unless you have a specific reason.

## Common mistakes

- Calling `asyncio.run(app.run_polling(...))` — PTB creates its own event loop
  internally; double-nesting causes a `RuntimeError: This event loop is already
  running` in Python 3.10+ or silent hang in earlier versions.
- Not calling `app.run_polling()` at all and instead awaiting individual bot
  methods — updates will never be dispatched to handlers.
- Registering handlers after `run_polling()` returns — they will never fire.
  Register all handlers before starting.

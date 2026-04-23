# Application Lifecycle

Sources: `telegram.ext.application.rst`, `telegram.ext.applicationbuilder.rst`,
`telegram.ext.updater.rst`, `inclusions__application_run_tip.rst`,
`inclusions__pool_size_tip.rst`, `examples.customwebhookbot.rst`.

## The v20+ entry point

`Application` replaced `Updater` as the central object. Build via
`ApplicationBuilder` — never construct it directly.

```python
from telegram.ext import ApplicationBuilder

app = (
    ApplicationBuilder()
    .token("BOT_TOKEN")
    .build()
)
```

Add handlers before starting:

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

Always call `delete_webhook()` before switching to polling — an active webhook
causes `getUpdates` to return a conflict error.

## Startup and shutdown hooks

Register coroutines on `ApplicationBuilder` that run at lifecycle boundaries:

```python
async def on_startup(app):
    await app.bot.send_message(chat_id=ADMIN_ID, text="Bot online")

async def on_shutdown(app):
    await app.bot.send_message(chat_id=ADMIN_ID, text="Shutting down")

app = (
    ApplicationBuilder()
    .token("BOT_TOKEN")
    .post_init(on_startup)
    .post_shutdown(on_shutdown)
    .build()
)
```

| Builder method | Runs |
|----------------|------|
| `post_init` | After `app.initialize()` completes |
| `post_stop` | After `app.stop()` completes |
| `post_shutdown` | After `app.shutdown()` completes |

## Graceful shutdown

`run_polling()` and `run_webhook()` install signal handlers for `SIGINT`
(Ctrl+C) and `SIGTERM`. Sequence:
1. Stop accepting new updates.
2. Finish processing in-flight updates.
3. Call `post_stop` and `post_shutdown` hooks.
4. Flush persistence (if configured).

Do not install your own `SIGINT`/`SIGTERM` handlers. Use the hooks above.
To stop from within a handler or job, call `app.stop_running()`.
(Source: `inclusions__application_run_tip.rst`)

## Integrating with an external asyncio framework

When combining PTB with another asyncio framework (FastAPI, etc.), `run_polling()`
and `run_webhook()` are the wrong choice — they block the event loop.
Use the manual lifecycle instead:

```python
async with ApplicationBuilder().token(TOKEN).build() as app:
    await app.updater.start_polling()
    await app.start()
    # ... your other async code ...
    await app.updater.stop()
    await app.stop()
```

Or wire into FastAPI lifespan (see `references/webhooks.md`).

## Connection pool and concurrency

When using concurrent updates (`block=False`, `create_task`, `JobQueue`), tune
these three `ApplicationBuilder` parameters together to avoid pool timeouts:

- `.concurrent_updates(N)` — max updates processed in parallel
- `.connection_pool_size(N)` — HTTP connection pool (should be >= concurrent_updates)
- `.pool_timeout(seconds)` — time to wait for a free connection

(Source: `inclusions__pool_size_tip.rst`)

## Common mistakes

- Calling `asyncio.run(app.run_polling(...))` — PTB creates its own event loop;
  nesting causes `RuntimeError: This event loop is already running`.
- Not calling `app.run_polling()` and instead awaiting bot methods directly —
  updates will never be dispatched to handlers.
- Registering handlers after `run_polling()` returns — they will never fire.
  Register all handlers before starting.
- Switching from webhook to polling without calling `delete_webhook()` first.

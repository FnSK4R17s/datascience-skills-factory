# Rate Limiting

Sources: `telegram.ext.rate-limiting-tree.rst`, `telegram.ext.aioratelimiter.rst`,
`telegram.ext.baseratelimiter.rst`, `inclusions__pool_size_tip.rst`,
`telegram.ext.applicationbuilder.rst`.

## Why rate limiting matters

Telegram enforces per-bot API rate limits:
- ~30 messages/second globally across all chats.
- ~1 message/second per individual chat.
- Inline query answers: ~25/second.

Exceeding these limits causes `RetryAfter` errors (HTTP 429). The `retry_after`
attribute on the exception tells you how many seconds to wait.

PTB's rate limiter intercepts outgoing API calls and automatically queues them
to stay within limits, handling `RetryAfter` responses by sleeping and retrying.

## AIORateLimiter — built-in rate limiter

Requires `pip install "python-telegram-bot[rate-limiter]"` (installs `aiolimiter`).

```python
from telegram.ext import ApplicationBuilder, AIORateLimiter

app = (
    ApplicationBuilder()
    .token(TOKEN)
    .rate_limiter(AIORateLimiter(
        max_retries=5,        # retry up to 5 times after RetryAfter
        # overall_max_rate=30,  # optional global rate cap (messages/second)
        # group_max_rate=20,    # optional per-group rate cap
    ))
    .build()
)
```

`AIORateLimiter` handles `RetryAfter` responses by sleeping `retry_after` seconds
and then retrying the request, up to `max_retries` times. After max retries,
the exception propagates to your error handler.

## BaseRateLimiter — custom implementation

Implement `BaseRateLimiter` to apply custom throttling strategies:
- Per-chat sliding windows.
- Token bucket per Bot API method.
- Priority queues (admin messages before broadcast).

```python
from telegram.ext import BaseRateLimiter

class MyRateLimiter(BaseRateLimiter):
    async def initialize(self) -> None:
        # Set up internal state (semaphores, token buckets, etc.)
        self._global_semaphore = asyncio.Semaphore(30)   # 30 req/s global

    async def shutdown(self) -> None:
        # Clean up
        pass

    async def process_request(
        self,
        callback,          # the actual Bot API request coroutine
        args,              # positional args to callback
        kwargs,            # keyword args to callback
        endpoint,          # Bot API method name (e.g., "sendMessage")
        data,              # request data dict
        rate_limit_args,   # extra args passed via rate_limit_args= kwarg
    ):
        async with self._global_semaphore:
            return await callback(*args, **kwargs)

app = ApplicationBuilder().token(TOKEN).rate_limiter(MyRateLimiter()).build()
```

Pass `rate_limit_args` in individual Bot method calls to send extra data to
your limiter's `process_request`:

```python
await context.bot.send_message(
    chat_id=chat_id,
    text="High priority",
    rate_limit_args={"priority": "high"},
)
```

## Connection pool and concurrency (three-way tuning)

When using concurrent updates (`block=False`, `create_task`, `concurrent_updates`,
or `JobQueue`), multiple coroutines call the Bot API simultaneously. If more
requests are in flight than there are HTTP connections in the pool, coroutines
block waiting. Tune these three parameters together:

(Source: `inclusions__pool_size_tip.rst`)

```python
app = (
    ApplicationBuilder()
    .token(TOKEN)
    .concurrent_updates(32)         # max updates processed in parallel
    .connection_pool_size(32)       # HTTP connections — set >= concurrent_updates
    .pool_timeout(10.0)             # seconds to wait for a free connection
    .rate_limiter(AIORateLimiter())
    .build()
)
```

Rule: `connection_pool_size` >= `concurrent_updates` + number of background jobs
that might be sending simultaneously. When in doubt, set pool size 20-50% higher
than concurrent updates.

Symptoms of pool exhaustion:
- `TimedOut` errors under load when individual requests should not be slow.
- Handlers appear to hang for several seconds before completing.
- `pool_timeout` errors in logs.

## Broadcast patterns

### Simple sequential broadcast

```python
import asyncio
from telegram.error import Forbidden, RetryAfter, TimedOut

async def broadcast_to_all(context, text: str) -> None:
    """Broadcast a message to all known users at ~20 msg/s."""
    user_ids = await get_all_user_ids()   # your DB call

    for uid in user_ids:
        try:
            await context.bot.send_message(chat_id=uid, text=text)
        except Forbidden:
            await remove_user(uid)
        except RetryAfter as e:
            logger.warning("Rate limited — sleeping %ss", e.retry_after)
            await asyncio.sleep(e.retry_after + 1)
            # Retry once after the wait
            try:
                await context.bot.send_message(chat_id=uid, text=text)
            except Exception:
                logger.error("Retry failed for user %s", uid)
        except (TimedOut, Exception) as e:
            logger.error("Failed to send to %s: %s", uid, e)

        await asyncio.sleep(0.05)    # 20 msg/s — well under Telegram's 30/s limit
```

### Batched concurrent broadcast (faster, with AIORateLimiter)

```python
import asyncio
from telegram.error import Forbidden

async def broadcast_concurrent(context, user_ids: list[int], text: str) -> dict:
    """Broadcast using asyncio.gather with concurrency limit."""
    semaphore = asyncio.Semaphore(10)   # max 10 concurrent sends
    results = {"success": 0, "failed": 0}

    async def send_one(uid: int) -> None:
        async with semaphore:
            try:
                await context.bot.send_message(chat_id=uid, text=text)
                results["success"] += 1
            except Forbidden:
                results["failed"] += 1
                await remove_user(uid)
            except Exception as e:
                results["failed"] += 1
                logger.error("Failed for %s: %s", uid, e)

    await asyncio.gather(*[send_one(uid) for uid in user_ids])
    return results
```

The `AIORateLimiter` handles `RetryAfter` automatically when enabled, so you
don't need explicit `asyncio.sleep(e.retry_after)` in every send.

### JobQueue broadcast (non-blocking)

Schedule a broadcast as a job so it doesn't block the main handler:

```python
async def start_broadcast_command(update, context):
    """Trigger a broadcast without blocking the handler."""
    await update.message.reply_text("Starting broadcast...")
    context.job_queue.run_once(
        callback=do_broadcast,
        when=0,   # run immediately, but in a job (non-blocking)
        data={"text": "Hello from the bot!"},
        name="broadcast",
    )

async def do_broadcast(context: ContextTypes.DEFAULT_TYPE) -> None:
    text = context.job.data["text"]
    user_ids = await get_all_user_ids()
    success = 0
    for uid in user_ids:
        try:
            await context.bot.send_message(chat_id=uid, text=text)
            success += 1
        except Forbidden:
            pass
        await asyncio.sleep(0.05)
    await context.bot.send_message(
        chat_id=ADMIN_CHAT_ID,
        text=f"Broadcast done: {success}/{len(user_ids)} sent",
    )
```

## Telegram rate limit reference

| Limit | Value | Notes |
|---|---|---|
| Global send rate | ~30 messages/second | Across all chats |
| Per-chat send rate | ~1 message/second | Burst of a few, then throttled |
| Inline query answer rate | ~25/second | Per bot |
| File upload size | 50 MB (via Bot API) | 2 GB with local Bot API server |
| File download size | 20 MB via API; use `get_file` for larger | — |
| Message length | 4096 characters | Split long messages |
| Caption length | 1024 characters | For photos, videos, documents |

These limits are set by Telegram servers — PTB's rate limiter adapts to them.
`RetryAfter` carries the exact wait time when a limit is exceeded.

## Defaults — set parse_mode and other send defaults globally

```python
from telegram.ext import Defaults
from telegram.constants import ParseMode

defaults = Defaults(
    parse_mode=ParseMode.HTML,       # all messages use HTML unless overridden
    disable_notification=False,
    block=False,                     # all handlers non-blocking by default
)

app = ApplicationBuilder().token(TOKEN).defaults(defaults).build()
```

With `ParseMode.HTML` as default, you don't need to pass `parse_mode=` on
every `reply_text` call. Override per-call as needed:
`await update.message.reply_text("plain text", parse_mode=None)`.

## Checking current rate limit status

There is no API endpoint to check your current rate limit status. The only
signal is a `RetryAfter` exception with the `retry_after` attribute set.

Log and monitor `RetryAfter` events to understand when your bot is approaching
limits:

```python
async def error_handler(update, context):
    if isinstance(context.error, RetryAfter):
        wait = context.error.retry_after
        logger.warning(
            "RATE LIMIT: RetryAfter=%ss | endpoint inferred from context",
            wait,
        )
        # If using AIORateLimiter, this should be rare/never
```

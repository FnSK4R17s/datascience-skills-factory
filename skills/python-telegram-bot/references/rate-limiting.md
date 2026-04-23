# Rate Limiting

Sources: `telegram.ext.rate-limiting-tree.rst`, `telegram.ext.aioratelimiter.rst`,
`telegram.ext.baseratelimiter.rst`, `inclusions__pool_size_tip.rst`,
`telegram.ext.applicationbuilder.rst`.

## Why rate limiting matters

Telegram enforces per-bot API limits (roughly 30 messages/second globally,
1 message/second per chat). Exceeding them causes `RetryAfter` errors (HTTP 429).
PTB's rate limiter intercepts outgoing API calls and queues them to stay within
limits automatically.

## AIORateLimiter (built-in)

Requires `pip install "python-telegram-bot[rate-limiter]"` (installs `aiolimiter`).

```python
from telegram.ext import ApplicationBuilder
from telegram.ext import AIORateLimiter

app = (
    ApplicationBuilder()
    .token(TOKEN)
    .rate_limiter(AIORateLimiter(max_retries=5))
    .build()
)
```

`AIORateLimiter` handles `RetryAfter` responses by sleeping the specified
duration and then retrying the request, up to `max_retries` times.

## BaseRateLimiter (custom implementation)

Implement `BaseRateLimiter` to apply custom throttling strategies (e.g., per-chat
sliding windows, token bucket per method).

```python
from telegram.ext import BaseRateLimiter

class MyLimiter(BaseRateLimiter):
    async def initialize(self) -> None: ...
    async def shutdown(self) -> None: ...

    async def process_request(
        self,
        callback,
        args,
        kwargs,
        endpoint,
        data,
        rate_limit_args,
    ):
        # Apply your logic, then call the actual request:
        return await callback(*args, **kwargs)
```

Pass via `ApplicationBuilder().rate_limiter(MyLimiter())`.

## Interaction with concurrent updates and connection pool

When using `block=False`, `create_task`, `concurrent_updates`, or `JobQueue`,
multiple coroutines make API calls simultaneously. The three parameters must be
tuned together:
(Source: `inclusions__pool_size_tip.rst`)

```python
ApplicationBuilder()
    .token(TOKEN)
    .concurrent_updates(32)        # max parallel update processing
    .connection_pool_size(32)      # must be >= concurrent_updates to avoid pool waits
    .pool_timeout(10.0)            # seconds to wait for a free connection
    .rate_limiter(AIORateLimiter())
    .build()
```

If `connection_pool_size` is smaller than the number of simultaneous API calls,
coroutines block waiting for a connection — even with a generous `pool_timeout`,
this can cause apparent hangs under load.

## Sending to many users (broadcast)

For broadcast loops, add per-message delays at the application level rather than
relying solely on the rate limiter:

```python
import asyncio

async def broadcast(app, user_ids, text):
    for uid in user_ids:
        try:
            await app.bot.send_message(chat_id=uid, text=text)
        except Forbidden:
            # User blocked the bot
            pass
        except RetryAfter as e:
            await asyncio.sleep(e.retry_after)
            await app.bot.send_message(chat_id=uid, text=text)
        await asyncio.sleep(0.04)   # ~25 msgs/sec per chat spread
```

## Default limits (informational — set by Telegram, not PTB)

| Limit | Value |
|-------|-------|
| Global send rate | ~30 messages/second |
| Per-chat send rate | ~1 message/second |
| Inline query answer rate | ~25/second |
| File upload size | 50 MB |

These limits are enforced by Telegram's servers. The `RetryAfter` exception
carries the exact wait time when a limit is hit.

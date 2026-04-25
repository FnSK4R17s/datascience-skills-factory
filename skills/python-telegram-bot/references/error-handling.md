# Error Handling

Sources: `examples.errorhandlerbot.rst`, `telegram.error.rst`,
`telegram.ext.handlers-tree.rst`, `telegram.ext.application.rst`.

## How PTB handles exceptions

PTB catches all exceptions raised in handlers and jobs, then routes them to
registered error handlers. Without an error handler:
- The exception is logged at `ERROR` level.
- The bot continues running — it does not crash.
- The user gets no feedback.

Register at least one error handler that notifies you (even if it only logs).

## Registering an error handler

```python
app.add_error_handler(error_handler_callback)
```

The callback signature:

```python
async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
    # context.error holds the raised exception
    # update may be None (if error occurred outside an update handler)
    ...
```

## Full error handler with developer notification

```python
import traceback
import html
import json
import logging

from telegram import Update
from telegram.constants import ParseMode
from telegram.ext import ContextTypes

logger = logging.getLogger(__name__)

DEVELOPER_CHAT_ID = 123456789   # your personal Telegram chat ID


async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Log the error and send a telegram message to notify the developer."""
    # Log
    logger.error("Exception while handling update:", exc_info=context.error)

    # Format traceback
    tb_list = traceback.format_exception(None, context.error, context.error.__traceback__)
    tb_string = "".join(tb_list)

    # Build message
    update_str = update.to_dict() if isinstance(update, Update) else str(update)
    message = (
        "An exception was raised while handling an update:\n"
        f"<pre>update = {html.escape(json.dumps(update_str, indent=2, ensure_ascii=False))}</pre>\n\n"
        f"<pre>{html.escape(tb_string)}</pre>"
    )

    # Telegram messages cap at 4096 chars
    await context.bot.send_message(
        chat_id=DEVELOPER_CHAT_ID,
        text=message[:4096],
        parse_mode=ParseMode.HTML,
    )


app.add_error_handler(error_handler)
```

(Source: `examples.errorhandlerbot.rst` — full working example)

## telegram.error exception hierarchy

All PTB errors inherit from `TelegramError`. Import selectively:

```python
from telegram.error import (
    TelegramError,
    Forbidden,
    InvalidToken,
    NetworkError,
    BadRequest,
    TimedOut,
    ChatMigrated,
    RetryAfter,
    Conflict,
)
```

| Exception | When it's raised | Key attributes |
|---|---|---|
| `TelegramError` | Base class — catch-all | `message` |
| `Forbidden` | Bot blocked by user, or lacks permission | — |
| `InvalidToken` | Bot token is invalid or revoked | — |
| `NetworkError` | Network-level failure (wraps httpx errors) | — |
| `BadRequest` | Malformed request (wrong parameters, entity out of range) | `message` |
| `TimedOut` | Bot API did not respond in time (not a flood error) | — |
| `ChatMigrated` | Group upgraded to supergroup; new chat_id available | `new_chat_id` |
| `RetryAfter` | Flood-controlled by Telegram; bot must wait | `retry_after` (seconds) |
| `Conflict` | Another bot instance is polling simultaneously | — |

## Handling specific errors in the error handler

```python
async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
    err = context.error

    if isinstance(err, Forbidden):
        # User blocked the bot — remove from any mailing list
        if update and isinstance(update, Update) and update.effective_user:
            user_id = update.effective_user.id
            logger.info("User %s blocked the bot — removing from DB", user_id)
            await remove_user_from_db(user_id)

    elif isinstance(err, RetryAfter):
        # Flood control — wait the specified time
        wait = err.retry_after
        logger.warning("Flood control: wait %s seconds", wait)
        # The request that failed is NOT automatically retried — handle upstream
        # Consider using AIORateLimiter to prevent this automatically

    elif isinstance(err, TimedOut):
        # Transient network issue — usually safe to retry once
        logger.warning("Bot API timed out: %s", err)

    elif isinstance(err, ChatMigrated):
        # Group was converted to supergroup
        new_id = err.new_chat_id
        logger.info("Chat migrated to %s", new_id)
        await update_chat_id_in_db(
            old_id=update.effective_chat.id if update else None,
            new_id=new_id,
        )

    elif isinstance(err, NetworkError):
        logger.error("Network error: %s", err)

    elif isinstance(err, BadRequest):
        logger.error("Bad request: %s", err)
        # Often means a bug in your code (wrong param types, message too long, etc.)

    else:
        logger.error("Unhandled error", exc_info=err)
```

## Handling errors inline (not in error handler)

For expected errors that you want to handle at the call site, wrap the
Bot API call in a try/except:

```python
async def safe_send(chat_id: int, text: str, context) -> bool:
    """Send a message, return True on success, False if blocked."""
    try:
        await context.bot.send_message(chat_id=chat_id, text=text)
        return True
    except Forbidden:
        logger.info("User %s blocked the bot", chat_id)
        return False
    except RetryAfter as e:
        await asyncio.sleep(e.retry_after)
        await context.bot.send_message(chat_id=chat_id, text=text)
        return True
    except TimedOut:
        logger.warning("Timed out sending to %s", chat_id)
        return False
```

## Broadcast loops — error handling pattern

When sending to many users, handle per-message errors to avoid aborting the loop:

```python
import asyncio
from telegram.error import Forbidden, RetryAfter, TimedOut

async def broadcast(context, user_ids: list[int], text: str) -> dict:
    results = {"success": 0, "blocked": 0, "other_error": 0}

    for user_id in user_ids:
        try:
            await context.bot.send_message(chat_id=user_id, text=text)
            results["success"] += 1
        except Forbidden:
            results["blocked"] += 1
            await remove_user_from_db(user_id)
        except RetryAfter as e:
            await asyncio.sleep(e.retry_after + 1)
            try:
                await context.bot.send_message(chat_id=user_id, text=text)
                results["success"] += 1
            except Exception:
                results["other_error"] += 1
        except (TimedOut, NetworkError):
            results["other_error"] += 1
        except ChatMigrated as e:
            await update_chat_id_in_db(user_id, e.new_chat_id)
            results["other_error"] += 1

        await asyncio.sleep(0.05)   # ~20 msg/sec, well under rate limit

    return results
```

## CallbackQuery expiry (TimedOut / BadRequest)

If you don't answer a `CallbackQuery` within ~30 seconds, Telegram stops waiting.
Attempting to `answer()` after expiry raises `BadRequest: Query is too old`.

```python
async def slow_button_handler(update, context):
    query = update.callback_query
    # Answer immediately to stop the spinner, before any slow operations
    await query.answer()

    # Now do slow work...
    result = await slow_database_query()
    await query.edit_message_text(f"Result: {result}")
```

## ApplicationHandlerStop — abort without error

Raise `ApplicationHandlerStop` inside a handler to:
1. Stop subsequent handlers in the same group from running.
2. NOT trigger the error handler.

```python
from telegram.ext import ApplicationHandlerStop

async def auth_middleware(update, context):
    if not is_authenticated(update.effective_user):
        await update.message.reply_text("Please /login first.")
        raise ApplicationHandlerStop   # stops group; error handler not called

app.add_handler(TypeHandler(Update, auth_middleware), group=0)
app.add_handler(CommandHandler("dashboard", dashboard), group=0)
```

(Source: `telegram.ext.applicationhandlerstop.rst`)

## Common error scenarios and fixes

| Error | Scenario | Fix |
|---|---|---|
| `Forbidden` | User blocked the bot | Remove from DB, don't message again |
| `Forbidden: bot is not a member` | Bot was kicked | Remove group from DB |
| `ChatMigrated` | Group → supergroup | Update stored chat_id |
| `RetryAfter` | Too many messages | Add delays; use `AIORateLimiter` |
| `BadRequest: message is not modified` | `edit_message_text` with same content | Check if content changed before editing |
| `BadRequest: can't parse entities` | HTML/Markdown syntax error | Escape user input with `html.escape()` |
| `BadRequest: message to edit not found` | Message was deleted externally | Catch and ignore |
| `TimedOut` | Slow API response under load | Increase `pool_timeout`; reduce concurrency |
| `Conflict` | Two instances polling | Ensure only one bot instance per token |
| `InvalidToken` | Wrong or expired token | Get fresh token from BotFather |

## Escaping HTML and Markdown safely

```python
import html

# Always escape user-provided text when using ParseMode.HTML
user_name = update.effective_user.full_name
await update.message.reply_html(
    f"Hello, <b>{html.escape(user_name)}</b>!"
)

# For MarkdownV2, use the built-in helper
from telegram.helpers import escape_markdown
user_name_escaped = escape_markdown(user_name, version=2)
await update.message.reply_text(
    f"Hello, *{user_name_escaped}*!",
    parse_mode="MarkdownV2",
)
```

## Logging setup

```python
import logging

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)
# Reduce noise from httpx
logging.getLogger("httpx").setLevel(logging.WARNING)
logger = logging.getLogger(__name__)
```

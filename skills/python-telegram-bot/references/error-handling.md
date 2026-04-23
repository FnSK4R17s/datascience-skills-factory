# Error Handling

Sources: `examples.errorhandlerbot.rst`, `telegram.error.rst`,
`telegram.ext.handlers-tree.rst`, `telegram.ext.application.rst`.

## Registering an error handler

PTB catches all exceptions raised in handlers and jobs and routes them to
registered error handlers. Without one, PTB logs the traceback but does not
crash the bot.

```python
import traceback
import html
import json

async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
    # Log the error
    logger.error("Exception while handling update:", exc_info=context.error)

    # Build a developer-friendly message
    tb_list = traceback.format_exception(None, context.error, context.error.__traceback__)
    tb_string = "".join(tb_list)

    update_str = update.to_dict() if isinstance(update, Update) else str(update)
    message = (
        f"An exception was raised:\n"
        f"<pre>update = {html.escape(json.dumps(update_str, indent=2))}</pre>\n\n"
        f"<pre>{html.escape(tb_string)}</pre>"
    )

    # Send to a developer chat
    await context.bot.send_message(
        chat_id=DEVELOPER_CHAT_ID,
        text=message,
        parse_mode=ParseMode.HTML,
    )

app.add_error_handler(error_handler)
```

(Source: `examples.errorhandlerbot.rst` — full example with traceback formatting)

## telegram.error exception hierarchy

From `telegram.error.rst` (automodule — consult installed package docstrings for
full details):

| Exception | Meaning |
|-----------|---------|
| `TelegramError` | Base class for all PTB errors |
| `Forbidden` | Bot lacks permission (e.g., blocked by user) |
| `InvalidToken` | Bot token is invalid or revoked |
| `NetworkError` | Network-level failure (wraps httpx errors) |
| `BadRequest` | Malformed request (wrong parameters) |
| `TimedOut` | Bot API did not respond in time |
| `ChatMigrated` | Group was upgraded to supergroup; new `chat_id` in exception |
| `RetryAfter` | Flood-controlled; `retry_after` attribute holds wait time in seconds |
| `Conflict` | Another bot instance is polling simultaneously |

All are in `telegram.error`. Import selectively:

```python
from telegram.error import Forbidden, RetryAfter, TimedOut, BadRequest
```

## Handling specific errors in a handler

Error handlers receive all uncaught exceptions. Filter by type:

```python
async def error_handler(update, context):
    if isinstance(context.error, Forbidden):
        # User blocked the bot — remove from mailing list, etc.
        pass
    elif isinstance(context.error, RetryAfter):
        wait = context.error.retry_after
        logger.warning("Flood control: retry after %s seconds", wait)
    elif isinstance(context.error, TimedOut):
        # Transient; can usually retry
        pass
    else:
        logger.error("Unhandled error", exc_info=context.error)
```

## Raising errors intentionally

To abort handler processing and surface to the error handler, raise any
exception. To abort without triggering the error handler, raise
`ApplicationHandlerStop` (prevents subsequent handlers in the same group from
running but does not call the error handler).

## Common pitfalls

- Not calling `await query.answer()` in a `CallbackQueryHandler` before the
  callback times out causes Telegram to show a persistent spinner. This is a
  `BadRequest` if the query is too old.
- Sending to a deleted or migrated chat raises `Forbidden` or `ChatMigrated`.
  Always handle these in long-running broadcast loops.
- A missing error handler means exceptions in jobs are only logged, not acted on.
  Register one even if it only sends to a monitoring chat.

# Handlers

Sources: `telegram.ext.handlers-tree.rst`, `telegram.ext.commandhandler.rst`,
`telegram.ext.messagehandler.rst`, `telegram.ext.callbackqueryhandler.rst`,
`telegram.ext.filters.rst`, `telegram.ext.basehandler.rst`,
`telegram.ext.applicationhandlerstop.rst`, `examples.echobot.rst`,
`examples.errorhandlerbot.rst`.

## Handler registration

```python
from telegram.ext import CommandHandler, MessageHandler, CallbackQueryHandler, filters

app.add_handler(CommandHandler("start", start_callback))
app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, echo_callback))
app.add_handler(CallbackQueryHandler(button_callback))
```

Every callback is `async def` and receives `(update, context)`:

```python
async def start_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text("Hello!")
```

## CommandHandler

Matches messages starting with `/command`.

```python
CommandHandler("help", help_callback)
CommandHandler(["start", "begin"], start_callback)   # multiple triggers
```

Arguments after the command are available as `context.args` (list of strings):

```python
# User sends: /set 10 hello
async def set_callback(update, context):
    value, label = context.args[0], context.args[1]
```

## MessageHandler

Always provide a filter. A bare `MessageHandler(filters.ALL, ...)` fires on
everything including commands, edited messages, and channel posts.

```python
MessageHandler(filters.TEXT & ~filters.COMMAND, text_callback)
MessageHandler(filters.PHOTO, photo_callback)
MessageHandler(filters.Document.FileExtension("pdf"), pdf_callback)
```

## Filter composition

`filters` is a module (`telegram.ext.filters`), not a class.
(Source: `telegram.ext.filters.rst`)

| Operator | Meaning |
|----------|---------|
| `A & B` | AND |
| `A \| B` | OR |
| `~A` | NOT |

Common built-in filters: `filters.TEXT`, `filters.PHOTO`, `filters.COMMAND`,
`filters.Regex(r"pattern")`, `filters.ChatType.PRIVATE`, `filters.FORWARDED`.

Custom filter:

```python
from telegram.ext.filters import MessageFilter

class MyFilter(MessageFilter):
    def filter(self, message):
        return message.text and "hello" in message.text.lower()

app.add_handler(MessageHandler(MyFilter(), hello_callback))
```

## CallbackQueryHandler

Fires when a user presses an `InlineKeyboardButton`. The `pattern` parameter
is a regex applied to `callback_query.data`.

```python
CallbackQueryHandler(yes_callback, pattern=r"^yes$")
CallbackQueryHandler(any_callback)    # no pattern = catch-all
```

Always answer the callback query to dismiss the spinner:

```python
async def yes_callback(update, context):
    query = update.callback_query
    await query.answer()           # required
    await query.edit_message_text("You said yes.")
```

## Handler priority (groups)

`add_handler` accepts an optional `group` integer (default `0`). Lower group
numbers run first. Within a group, handlers are checked in registration order.

```python
app.add_handler(high_priority_handler, group=0)
app.add_handler(low_priority_handler,  group=1)
```

Raising `ApplicationHandlerStop` inside a handler prevents subsequent handlers
in the same group from running.
(Source: `telegram.ext.applicationhandlerstop.rst`)

## Error handler

```python
async def error_handler(update, context):
    # context.error holds the raised exception
    logger.error("Update %s caused error %s", update, context.error)

app.add_error_handler(error_handler)
```

Without an error handler, PTB logs the traceback but does not crash.
See `examples.errorhandlerbot.rst` for a full example with traceback formatting.

## Handler types available

From `telegram.ext.handlers-tree.rst`:
`CommandHandler`, `MessageHandler`, `CallbackQueryHandler`, `InlineQueryHandler`,
`ChatMemberHandler`, `ChatJoinRequestHandler`, `PollHandler`, `PollAnswerHandler`,
`PreCheckoutQueryHandler`, `ShippingQueryHandler`, `TypeHandler` (catch-all by
update type), `ConversationHandler` (see `conversation-handler.md`).

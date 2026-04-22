# Handlers

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

Matches messages starting with `/command`. The `commands` parameter accepts
a string or list of strings (without the leading `/`).

```python
CommandHandler("help", help_callback)
CommandHandler(["start", "begin"], start_callback)   # multiple triggers
```

Arguments after the command are available as `context.args` (a list of strings):

```
/set 10 hello
```
```python
async def set_callback(update, context):
    value, label = context.args[0], context.args[1]
```

## MessageHandler

Catches non-command messages. Always provide a filter — a bare
`MessageHandler(filters.ALL, ...)` fires on everything including commands,
edited messages, and channel posts, which is rarely what you want.

```python
MessageHandler(filters.TEXT & ~filters.COMMAND, text_callback)
MessageHandler(filters.PHOTO, photo_callback)
MessageHandler(filters.Document.FileExtension("pdf"), pdf_callback)
```

## Filter composition

Filters compose with Python bitwise operators:

| Operator | Meaning |
|----------|---------|
| `A & B` | A AND B |
| `A \| B` | A OR B |
| `~A` | NOT A |

`filters` is a module (`telegram.ext.filters`), not a class. Predefined
filters include `filters.TEXT`, `filters.PHOTO`, `filters.COMMAND`,
`filters.Regex(r"pattern")`, `filters.ChatType.PRIVATE`, and many more.

Custom filter:

```python
from telegram.ext.filters import MessageFilter

class MyFilter(MessageFilter):
    def filter(self, message):
        return message.text and "hello" in message.text.lower()

my_filter = MyFilter()
app.add_handler(MessageHandler(my_filter, hello_callback))
```

## CallbackQueryHandler

Fires when a user presses an `InlineKeyboardButton`. The `pattern` argument
is a regex applied to `callback_query.data`:

```python
CallbackQueryHandler(yes_callback, pattern=r"^yes$")
CallbackQueryHandler(no_callback,  pattern=r"^no$")
CallbackQueryHandler(any_callback)    # no pattern = catch-all
```

Always answer the callback query to dismiss the "loading" spinner:

```python
async def yes_callback(update, context):
    query = update.callback_query
    await query.answer()           # required; optionally pass text= for toast
    await query.edit_message_text("You said yes.")
```

## Handler priority (groups)

`add_handler` accepts an optional `group` integer (default `0`). Lower group
numbers run first. Within a group, handlers are checked in registration order.
A handler returning `ApplicationHandlerStop` prevents lower-priority handlers
in the same group from running.

```python
app.add_handler(high_priority_handler, group=0)
app.add_handler(low_priority_handler,  group=1)
```

## Error handler

Register a single error handler to catch exceptions from any handler:

```python
async def error_handler(update, context):
    # context.error holds the raised exception
    logger.error("Update %s caused error %s", update, context.error)

app.add_error_handler(error_handler)
```

Without an error handler, PTB logs the traceback but does not crash.

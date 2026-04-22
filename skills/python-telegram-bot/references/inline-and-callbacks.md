# Inline Keyboards and Callback Queries

## Sending an inline keyboard

```python
from telegram import InlineKeyboardButton, InlineKeyboardMarkup

keyboard = [
    [
        InlineKeyboardButton("Yes", callback_data="yes"),
        InlineKeyboardButton("No",  callback_data="no"),
    ],
    [InlineKeyboardButton("Cancel", callback_data="cancel")],
]
reply_markup = InlineKeyboardMarkup(keyboard)

await update.message.reply_text("Choose:", reply_markup=reply_markup)
```

`InlineKeyboardMarkup` takes a list-of-lists structure. Each inner list is
one row; each `InlineKeyboardButton` is one button in that row.

## callback_data

`callback_data` is a string (max 64 bytes). When the user presses the button,
Telegram sends a `CallbackQuery` update with `callback_query.data` set to
that string.

For structured data, encode to a compact string format:

```python
# simple pattern
InlineKeyboardButton("Item 1", callback_data="item:1")
InlineKeyboardButton("Item 2", callback_data="item:2")

# handler
CallbackQueryHandler(item_callback, pattern=r"^item:(\d+)$")

async def item_callback(update, context):
    query = update.callback_query
    item_id = context.matches[0].group(1)
    await query.answer()
    await query.edit_message_text(f"You picked item {item_id}")
```

For arbitrary Python objects as callback data, enable `arbitrary_callback_data`:

```python
app = (
    ApplicationBuilder()
    .token(TOKEN)
    .arbitrary_callback_data(True)
    .build()
)

# Now callback_data can be any picklable object:
InlineKeyboardButton("Go", callback_data={"action": "go", "id": 42})
```

This stores data server-side in a `CallbackDataCache`. The button sends only
a UUID to Telegram; PTB resolves it back on arrival. Avoids the 64-byte limit.

## Answering a callback query

Always call `answer()` when handling a callback query. Telegram shows a
spinner on the button until you do; leaving it unanswered looks broken.

```python
async def button_handler(update, context):
    query = update.callback_query
    await query.answer()                          # dismiss spinner
    # OR: await query.answer(text="Processing...")  # show toast
    # OR: await query.answer(text="Done!", show_alert=True)  # modal alert

    await query.edit_message_text("Updated text")
```

Methods on `CallbackQuery`:

| Method | Effect |
|--------|--------|
| `answer()` | Dismiss spinner |
| `edit_message_text(text)` | Replace the message text |
| `edit_message_reply_markup(markup)` | Replace the keyboard only |
| `edit_message_caption(caption)` | Replace caption on a photo/video |
| `delete_message()` | Delete the message |

## Inline query mode

Inline queries let users trigger your bot from any chat by typing
`@botusername <query>`. Enable via BotFather (`/setinline`).

```python
from telegram import InlineQueryResultArticle, InputTextMessageContent
from telegram.ext import InlineQueryHandler
import uuid

async def inline_query_handler(update, context):
    query = update.inline_query.query
    results = [
        InlineQueryResultArticle(
            id=str(uuid.uuid4()),
            title=f"Echo: {query}",
            input_message_content=InputTextMessageContent(query),
        )
    ]
    await update.inline_query.answer(results)

app.add_handler(InlineQueryHandler(inline_query_handler))
```

`answer()` takes a list of `InlineQueryResult*` objects. Up to 50 results per
call. Use `cache_time=0` during development to see changes immediately.

## Keyboard persistence across edits

When you `edit_message_text`, pass `reply_markup=reply_markup` again to keep
the keyboard. Without it, the keyboard is removed from the edited message.

## ReplyKeyboardMarkup (chat keyboard, not inline)

`ReplyKeyboardMarkup` is different from `InlineKeyboardMarkup`. It replaces
the user's text input area with persistent buttons. It does not produce
`CallbackQuery` updates — pressing a button sends a regular text message with
the button's label.

```python
from telegram import ReplyKeyboardMarkup, ReplyKeyboardRemove

keyboard = [["Option A", "Option B"], ["Cancel"]]
await update.message.reply_text(
    "Pick one:",
    reply_markup=ReplyKeyboardMarkup(keyboard, one_time_keyboard=True),
)

# To remove:
await update.message.reply_text("Done.", reply_markup=ReplyKeyboardRemove())
```

Use `InlineKeyboardMarkup` for action buttons tied to a specific message.
Use `ReplyKeyboardMarkup` for persistent navigation (main menu, mode selection).

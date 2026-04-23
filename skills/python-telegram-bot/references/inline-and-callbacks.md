# Inline Keyboards and Callback Queries

Sources: `telegram.inlinekeyboardmarkup.rst`, `telegram.inlinekeyboardbutton.rst`,
`telegram.callbackquery.rst`, `telegram.ext.callbackqueryhandler.rst`,
`telegram.ext.callbackdatacache.rst`, `telegram.ext.extbot.rst`,
`telegram.ext.inlinequeryhandler.rst`, `examples.inlinekeyboard.rst`,
`examples.inlinekeyboard2.rst`, `examples.inlinebot.rst`,
`examples.arbitrarycallbackdatabot.rst`.

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

`InlineKeyboardMarkup` takes a list-of-lists. Each inner list is one row.

## callback_data

`callback_data` is a string (max 64 bytes). When pressed, Telegram sends a
`CallbackQuery` update with `callback_query.data` set to that string.

For structured data, encode to a compact string:

```python
InlineKeyboardButton("Item 1", callback_data="item:1")

CallbackQueryHandler(item_callback, pattern=r"^item:(\d+)$")

async def item_callback(update, context):
    item_id = context.matches[0].group(1)
    await update.callback_query.answer()
    await update.callback_query.edit_message_text(f"Item {item_id}")
```

## Arbitrary callback data (objects, not strings)

For complex data that exceeds 64 bytes, enable `arbitrary_callback_data`.
Requires `pip install "python-telegram-bot[callback-data]"`.
PTB stores data server-side in `CallbackDataCache` and sends only a UUID to
Telegram. (Source: `telegram.ext.callbackdatacache.rst`, `telegram.ext.extbot.rst`,
`examples.arbitrarycallbackdatabot.rst`)

```python
app = (
    ApplicationBuilder()
    .token(TOKEN)
    .arbitrary_callback_data(True)
    .build()
)

# callback_data can now be any picklable object:
InlineKeyboardButton("Go", callback_data={"action": "go", "id": 42})
```

## Answering a callback query

Always call `answer()` when handling a callback query. Telegram shows a
spinner on the button until you do.

```python
async def button_handler(update, context):
    query = update.callback_query
    await query.answer()                          # dismiss spinner
    # OR: await query.answer(text="Processing...")  # show toast
    # OR: await query.answer(text="Done!", show_alert=True)  # modal alert
    await query.edit_message_text("Updated text")
```

| Method | Effect |
|--------|--------|
| `answer()` | Dismiss spinner |
| `edit_message_text(text)` | Replace message text |
| `edit_message_reply_markup(markup)` | Replace keyboard only |
| `edit_message_caption(caption)` | Replace caption on photo/video |
| `delete_message()` | Delete the message |

When calling `edit_message_text`, pass `reply_markup=reply_markup` again to
keep the keyboard — omitting it removes the keyboard.

## Inline query mode

Lets users trigger the bot from any chat via `@botusername <query>`.
Enable inline mode with BotFather (`/setinline`).
(Source: `examples.rst`, `examples.inlinebot.rst`)

```python
from telegram import InlineQueryResultArticle, InputTextMessageContent
from telegram.ext import InlineQueryHandler
import uuid

async def inline_handler(update, context):
    query = update.inline_query.query
    results = [
        InlineQueryResultArticle(
            id=str(uuid.uuid4()),
            title=f"Echo: {query}",
            input_message_content=InputTextMessageContent(query),
        )
    ]
    await update.inline_query.answer(results)

app.add_handler(InlineQueryHandler(inline_handler))
```

`answer()` takes up to 50 `InlineQueryResult*` objects. Use `cache_time=0`
during development.

## ReplyKeyboardMarkup (chat keyboard, not inline)

Different from `InlineKeyboardMarkup` — replaces the text input area with
persistent buttons. Pressing a button sends a regular text message; no
`CallbackQuery` is produced.

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

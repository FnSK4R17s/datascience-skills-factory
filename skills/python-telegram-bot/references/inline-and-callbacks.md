# Inline Keyboards and Callback Queries

Sources: `telegram.inlinekeyboardmarkup.rst`, `telegram.inlinekeyboardbutton.rst`,
`telegram.callbackquery.rst`, `telegram.ext.callbackqueryhandler.rst`,
`telegram.ext.callbackdatacache.rst`, `telegram.ext.extbot.rst`,
`telegram.ext.inlinequeryhandler.rst`, `examples.inlinekeyboard.rst`,
`examples.inlinekeyboard2.rst`, `examples.inlinebot.rst`,
`examples.arbitrarycallbackdatabot.rst`.

## InlineKeyboardMarkup — basics

Inline keyboards are attached to a specific message. Pressing a button sends a
`CallbackQuery` update (not a regular text message).

```python
from telegram import InlineKeyboardButton, InlineKeyboardMarkup

# 2-row keyboard
keyboard = [
    [
        InlineKeyboardButton("Yes", callback_data="yes"),
        InlineKeyboardButton("No",  callback_data="no"),
    ],
    [InlineKeyboardButton("Cancel", callback_data="cancel")],
]
reply_markup = InlineKeyboardMarkup(keyboard)

await update.message.reply_text("Are you sure?", reply_markup=reply_markup)
```

`InlineKeyboardMarkup` takes a list-of-lists:
- Outer list = rows.
- Inner list = buttons in that row.
- Each button is an `InlineKeyboardButton`.

## InlineKeyboardButton types

An `InlineKeyboardButton` does exactly one of three things:

```python
# 1. Sends a callback_data string to the bot
InlineKeyboardButton("Click me", callback_data="action:42")

# 2. Opens a URL in the browser (or t.me links in the Telegram app)
InlineKeyboardButton("Visit website", url="https://example.com")

# 3. Opens a Mini App (Web App)
from telegram import WebAppInfo
InlineKeyboardButton("Open App", web_app=WebAppInfo(url="https://yourapp.com"))

# 4. Opens inline mode in another chat
InlineKeyboardButton("Share", switch_inline_query="search_query")

# 5. Opens inline mode in the current chat
InlineKeyboardButton("Search here", switch_inline_query_current_chat="query")
```

## Handling callback_data

`callback_data` is a string (max 64 bytes). When pressed, Telegram sends a
`CallbackQuery` update. The handler must call `answer()` to dismiss the spinner.

```python
from telegram.ext import CallbackQueryHandler

async def button_callback(update, context):
    query = update.callback_query
    await query.answer()                    # dismiss the spinner — required
    data = query.data                       # the callback_data string

    if data == "yes":
        await query.edit_message_text("You said yes!")
    elif data == "no":
        await query.edit_message_text("You said no!")
    elif data == "cancel":
        await query.delete_message()

app.add_handler(CallbackQueryHandler(button_callback))
```

Use `pattern=` to route to specific callbacks by regex:

```python
# Route by prefix
app.add_handler(CallbackQueryHandler(yes_cb,    pattern=r"^yes$"))
app.add_handler(CallbackQueryHandler(no_cb,     pattern=r"^no$"))
app.add_handler(CallbackQueryHandler(action_cb, pattern=r"^action:\d+$"))

# Extract groups
async def action_cb(update, context):
    query = update.callback_query
    await query.answer()
    action_id = context.matches[0].group(1)  # from pattern=r"^action:(\d+)$"
    await query.edit_message_text(f"Action {action_id}")
```

## Answering a callback query — all options

```python
query = update.callback_query

# Silent dismiss (just removes the spinner)
await query.answer()

# Show a brief toast notification (up to 200 chars)
await query.answer(text="Done!")

# Show a modal alert (user must tap OK to dismiss)
await query.answer(text="Critical error!", show_alert=True)

# Link to a game (for GameBot callbacks)
await query.answer(url="https://game.example.com")
```

After answering, edit or update the message:

```python
# Replace message text
await query.edit_message_text("New text")

# Replace text and keyboard
await query.edit_message_text("New text", reply_markup=new_keyboard)

# Replace just the keyboard
await query.edit_message_reply_markup(reply_markup=new_keyboard)

# Replace media caption
await query.edit_message_caption(caption="New caption")

# Replace media (photo, video, etc.)
from telegram import InputMediaPhoto
await query.edit_message_media(media=InputMediaPhoto(open("new.jpg", "rb")))

# Delete the message
await query.delete_message()
```

Omitting `reply_markup` from `edit_message_text` removes the keyboard entirely.
Pass the keyboard again to keep it.

## Full interactive menu example

```python
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, ContextTypes

TOKEN = "YOUR_BOT_TOKEN"

def build_menu(user_choice=None):
    """Build the keyboard — highlight current selection."""
    options = ["Python", "JavaScript", "Rust", "Go"]
    keyboard = []
    for opt in options:
        text = f"[{opt}]" if opt == user_choice else opt
        keyboard.append([InlineKeyboardButton(text, callback_data=f"lang:{opt}")])
    keyboard.append([InlineKeyboardButton("Confirm", callback_data="confirm")])
    return InlineKeyboardMarkup(keyboard)


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "Choose your favourite language:",
        reply_markup=build_menu(),
    )


async def button(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    await query.answer()

    data = query.data
    if data.startswith("lang:"):
        lang = data.split(":")[1]
        context.user_data["lang"] = lang
        await query.edit_message_text(
            f"Current selection: {lang}\nPress Confirm or choose another.",
            reply_markup=build_menu(user_choice=lang),
        )
    elif data == "confirm":
        lang = context.user_data.get("lang", "nothing")
        await query.edit_message_text(f"You confirmed: {lang}")


def main():
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(button))
    app.run_polling()

if __name__ == "__main__":
    main()
```

(Source: `examples.inlinekeyboard2.rst`)

## Encoding structured data in callback_data

The 64-byte limit means you must encode data compactly. Common patterns:

```python
# Colon-separated prefix scheme
InlineKeyboardButton("Like",   callback_data=f"like:{post_id}")
InlineKeyboardButton("Delete", callback_data=f"del:{post_id}")

# Parse in handler:
async def action_handler(update, context):
    query = update.callback_query
    await query.answer()
    prefix, value = query.data.split(":", 1)
    if prefix == "like":
        await handle_like(int(value), context)
    elif prefix == "del":
        await handle_delete(int(value), context)
```

For pagination:

```python
# Page navigation
InlineKeyboardButton("Next", callback_data=f"page:{current_page + 1}")
InlineKeyboardButton("Prev", callback_data=f"page:{current_page - 1}")
```

## Arbitrary callback data (pass Python objects, not strings)

When 64 bytes is not enough, enable `arbitrary_callback_data`. PTB stores the
object server-side in `CallbackDataCache` and sends only a UUID to Telegram.

Requires `pip install "python-telegram-bot[callback-data]"`.

(Source: `telegram.ext.callbackdatacache.rst`, `examples.arbitrarycallbackdatabot.rst`)

```python
from telegram.ext import ApplicationBuilder

app = (
    ApplicationBuilder()
    .token(TOKEN)
    .arbitrary_callback_data(True)
    .build()
)
```

Now `callback_data` can be any picklable Python object:

```python
from dataclasses import dataclass

@dataclass
class ProductAction:
    action: str
    product_id: int
    quantity: int

button = InlineKeyboardButton(
    "Buy 3",
    callback_data=ProductAction(action="buy", product_id=42, quantity=3)
)

async def purchase_handler(update, context):
    query = update.callback_query
    await query.answer()
    action: ProductAction = query.data   # already deserialized
    await query.edit_message_text(
        f"Buying {action.quantity}x product #{action.product_id}"
    )
```

Cache has a configurable size (`maxsize`). Old entries are evicted LRU.
When an entry is evicted and the user later presses that button, PTB raises
`InvalidCallbackData`. Handle it:

```python
from telegram.ext import InvalidCallbackData

async def handle_stale_button(update, context):
    query = update.callback_query
    if isinstance(query.data, InvalidCallbackData):
        await query.answer("This button has expired. Please restart.")
        return
    await query.answer()
    # normal handling...
```

## Inline query mode

Lets users trigger the bot from any chat via `@botusername <query>`.
Enable inline mode with BotFather (`/setinline`).
(Source: `examples.rst`, `examples.inlinebot.rst`)

```python
import uuid
from telegram import InlineQueryResultArticle, InputTextMessageContent
from telegram.ext import InlineQueryHandler

async def inline_query(update, context):
    query = update.inline_query.query

    if not query:
        return  # empty query — show nothing or default results

    results = [
        InlineQueryResultArticle(
            id=str(uuid.uuid4()),
            title=f"Echo: {query}",
            input_message_content=InputTextMessageContent(query),
            description="Sends your query as a message",
        ),
        InlineQueryResultArticle(
            id=str(uuid.uuid4()),
            title=f"Shout: {query.upper()}",
            input_message_content=InputTextMessageContent(query.upper()),
        ),
    ]

    await update.inline_query.answer(
        results,
        cache_time=0,          # 0 = don't cache (useful during development)
        is_personal=True,      # cache per-user rather than globally
    )

app.add_handler(InlineQueryHandler(inline_query))
```

`answer()` accepts up to 50 `InlineQueryResult*` objects.

### Inline query result types

```python
from telegram import (
    InlineQueryResultArticle,    # text message
    InlineQueryResultPhoto,      # photo from URL
    InlineQueryResultGif,        # GIF from URL
    InlineQueryResultMpeg4Gif,   # MP4 GIF from URL
    InlineQueryResultVideo,      # video from URL
    InlineQueryResultAudio,      # audio from URL
    InlineQueryResultVoice,      # voice from URL
    InlineQueryResultDocument,   # document from URL
    InlineQueryResultLocation,   # location
    InlineQueryResultVenue,      # venue
    InlineQueryResultContact,    # contact
    InlineQueryResultCachedSticker,  # sticker by file_id
    InlineQueryResultCachedPhoto,    # photo by file_id
)
```

### Handling chosen inline results

```python
from telegram.ext import ChosenInlineResultHandler

async def chosen_result(update, context):
    result = update.chosen_inline_result
    logger.info("User chose result %s for query '%s'", result.result_id, result.query)

app.add_handler(ChosenInlineResultHandler(chosen_result))
```

Enable `chosen_inline_result` updates via BotFather: `/setinlinefeedback`.

## ReplyKeyboardMarkup (chat keyboard, not inline)

Different from `InlineKeyboardMarkup` — replaces the text input area with
buttons that send a regular text message when pressed. No `CallbackQuery` is
produced.

```python
from telegram import ReplyKeyboardMarkup, ReplyKeyboardRemove, KeyboardButton

# Simple text buttons
keyboard = [["Option A", "Option B"], ["Cancel"]]
await update.message.reply_text(
    "Pick one:",
    reply_markup=ReplyKeyboardMarkup(
        keyboard,
        one_time_keyboard=True,      # hides keyboard after one press
        resize_keyboard=True,        # makes buttons smaller to fit screen
        input_field_placeholder="Choose an option",
    ),
)

# Remove the keyboard
await update.message.reply_text(
    "Done.",
    reply_markup=ReplyKeyboardRemove(),
)

# Request user contact
contact_button = KeyboardButton("Share Phone", request_contact=True)
await update.message.reply_text(
    "Share your phone number:",
    reply_markup=ReplyKeyboardMarkup([[contact_button]]),
)

# Request user location
location_button = KeyboardButton("Share Location", request_location=True)
await update.message.reply_text(
    "Share your location:",
    reply_markup=ReplyKeyboardMarkup([[location_button]]),
)
```

Receiving contact or location:

```python
async def got_contact(update, context):
    contact = update.message.contact
    await update.message.reply_text(
        f"Got contact: {contact.phone_number} ({contact.first_name})"
    )

async def got_location(update, context):
    loc = update.message.location
    await update.message.reply_text(f"Got location: {loc.latitude}, {loc.longitude}")

app.add_handler(MessageHandler(filters.CONTACT, got_contact))
app.add_handler(MessageHandler(filters.LOCATION, got_location))
```

## ForceReply

Forces the user's Telegram client to show a reply UI pointing to the bot's
message. Useful when you cannot use `ConversationHandler`.

```python
from telegram import ForceReply

await update.message.reply_text(
    "What is your name?",
    reply_markup=ForceReply(selective=True),  # selective=True only asks the mentioned user
)
```

## InlineKeyboardMarkup vs ReplyKeyboardMarkup — when to use each

| Feature | InlineKeyboardMarkup | ReplyKeyboardMarkup |
|---|---|---|
| Attached to | A specific message | The chat input area |
| User action | Press button → CallbackQuery | Press button → text message sent |
| Visible | Always (until message deleted/edited) | Until dismissed or one_time_keyboard |
| Use case | Action menus, confirm dialogs, pagination | Main menu, navigation, data collection |
| Works in channels | Yes | No |

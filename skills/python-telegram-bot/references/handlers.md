# Handlers

Sources: `telegram.ext.handlers-tree.rst`, `telegram.ext.commandhandler.rst`,
`telegram.ext.messagehandler.rst`, `telegram.ext.callbackqueryhandler.rst`,
`telegram.ext.chatmemberhandler.rst`, `telegram.ext.filters.rst`,
`telegram.ext.basehandler.rst`, `telegram.ext.applicationhandlerstop.rst`,
`examples.echobot.rst`, `examples.errorhandlerbot.rst`, `examples.chatmemberbot.rst`.

## Handler registration

```python
from telegram.ext import CommandHandler, MessageHandler, CallbackQueryHandler, filters

app.add_handler(CommandHandler("start", start_callback))
app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, echo_callback))
app.add_handler(CallbackQueryHandler(button_callback))
```

Every callback is `async def` and receives `(update, context)`:

```python
from telegram import Update
from telegram.ext import ContextTypes

async def start_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text("Hello!")
```

## CommandHandler

Matches messages starting with `/command` (and optional `@botusername` suffix).

```python
from telegram.ext import CommandHandler

# Single command
app.add_handler(CommandHandler("start", start_callback))

# Multiple trigger words for one handler
app.add_handler(CommandHandler(["start", "begin", "hello"], start_callback))

# /help with optional argument
app.add_handler(CommandHandler("help", help_callback))
```

Arguments after the command are available as `context.args` (list of strings):

```python
# User sends: /set 42 my-label
async def set_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not context.args or len(context.args) < 2:
        await update.message.reply_text("Usage: /set <number> <label>")
        return
    number = int(context.args[0])
    label = context.args[1]
    context.chat_data["setting"] = {"number": number, "label": label}
    await update.message.reply_text(f"Set {label} = {number}")
```

## MessageHandler

Always provide a filter. A bare `MessageHandler(filters.ALL, ...)` fires on
every update including commands, edited messages, and channel posts.

```python
from telegram.ext import MessageHandler, filters

# Text messages that are not commands
app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_callback))

# Photos
app.add_handler(MessageHandler(filters.PHOTO, photo_callback))

# Documents with specific extension
app.add_handler(MessageHandler(filters.Document.FileExtension("pdf"), pdf_callback))

# Audio or voice
app.add_handler(MessageHandler(filters.AUDIO | filters.VOICE, audio_callback))

# Forwarded messages
app.add_handler(MessageHandler(filters.FORWARDED, forwarded_callback))

# Private chats only
app.add_handler(MessageHandler(filters.ChatType.PRIVATE & filters.TEXT, private_text_cb))

# Group chats only
app.add_handler(MessageHandler(filters.ChatType.GROUPS & filters.TEXT, group_text_cb))
```

## Complete filter reference

`filters` is a module (`telegram.ext.filters`), not a class.
(Source: `telegram.ext.filters.rst`)

| Operator | Meaning | Example |
|---|---|---|
| `A & B` | AND — both must match | `filters.TEXT & ~filters.COMMAND` |
| `A \| B` | OR — either must match | `filters.PHOTO \| filters.VIDEO` |
| `~A` | NOT — inverts the filter | `~filters.FORWARDED` |

### Message content filters

```python
filters.TEXT              # any text message (including commands)
filters.COMMAND           # messages starting with /
filters.PHOTO             # photo messages
filters.VIDEO             # video messages
filters.AUDIO             # audio messages (music)
filters.VOICE             # voice messages
filters.DOCUMENT          # document messages
filters.ANIMATION         # GIF / animation
filters.STICKER           # sticker messages
filters.LOCATION          # location messages
filters.CONTACT           # contact messages
filters.VENUE             # venue messages
filters.POLL              # poll messages
filters.DICE              # dice messages
filters.GAME              # game messages
filters.INVOICE           # invoice messages
filters.SUCCESSFUL_PAYMENT  # successful payment messages
filters.PASSPORT_DATA     # Telegram Passport data
filters.FORWARDED         # forwarded from any source
```

### Chat type filters

```python
filters.ChatType.PRIVATE          # private chats (user ↔ bot)
filters.ChatType.GROUP            # basic groups
filters.ChatType.SUPERGROUP       # supergroups
filters.ChatType.CHANNEL          # channels
filters.ChatType.GROUPS           # GROUP | SUPERGROUP (shortcut)
```

### Status update filters

```python
filters.StatusUpdate.NEW_CHAT_MEMBERS    # user(s) added to chat
filters.StatusUpdate.LEFT_CHAT_MEMBER   # user left chat
filters.StatusUpdate.NEW_CHAT_TITLE     # chat title changed
filters.StatusUpdate.NEW_CHAT_PHOTO     # chat photo changed
filters.StatusUpdate.WEB_APP_DATA       # web app data received
```

### Regex filter

```python
# Matches message text against pattern; context.matches holds the match objects
app.add_handler(MessageHandler(
    filters.Regex(r"^/?\d{1,3}$"),  # messages that are 1-3 digit numbers
    number_callback,
))

async def number_callback(update, context):
    match = context.matches[0]  # first Match object
    number = int(match.group(0))
    await update.message.reply_text(f"You said number {number}")
```

### Document extension filter

```python
filters.Document.FileExtension("pdf")    # PDF documents
filters.Document.FileExtension("xlsx")   # Excel files
filters.Document.MimeType("image/jpeg")  # JPEG images as documents
```

### Custom filter

```python
from telegram.ext.filters import MessageFilter

class AdminOnlyFilter(MessageFilter):
    ADMIN_IDS = {123456789, 987654321}

    def filter(self, message) -> bool:
        return (
            message.from_user is not None
            and message.from_user.id in self.ADMIN_IDS
        )

admin_filter = AdminOnlyFilter()
app.add_handler(MessageHandler(admin_filter, admin_callback))
```

For stateful custom filters, use `UpdateFilter` for filters that need the full
`Update` object, or `MessageFilter` for those that only need the `Message`.

## CallbackQueryHandler

Fires when a user presses an `InlineKeyboardButton`. The `pattern` parameter
is a regex applied to `callback_query.data`.

```python
from telegram.ext import CallbackQueryHandler

# Specific patterns
app.add_handler(CallbackQueryHandler(yes_callback, pattern=r"^yes$"))
app.add_handler(CallbackQueryHandler(no_callback,  pattern=r"^no$"))
app.add_handler(CallbackQueryHandler(item_callback, pattern=r"^item:(\d+)$"))

# Catch-all (no pattern)
app.add_handler(CallbackQueryHandler(any_button_callback))
```

Always answer the callback query to dismiss the loading spinner:

```python
async def button_callback(update, context):
    query = update.callback_query

    # Option 1: just dismiss the spinner
    await query.answer()

    # Option 2: show a brief toast message
    await query.answer(text="Processing...")

    # Option 3: show a modal alert
    await query.answer(text="Error: something went wrong", show_alert=True)

    # Edit the message text
    await query.edit_message_text("You clicked a button!")

    # Edit text and keep keyboard
    from telegram import InlineKeyboardMarkup, InlineKeyboardButton
    new_keyboard = InlineKeyboardMarkup([[
        InlineKeyboardButton("Back", callback_data="back")
    ]])
    await query.edit_message_text("Updated", reply_markup=new_keyboard)

    # Edit just the keyboard
    await query.edit_message_reply_markup(reply_markup=new_keyboard)

    # Delete the message entirely
    await query.delete_message()
```

Extract regex groups from callback_data:

```python
async def item_callback(update, context):
    query = update.callback_query
    await query.answer()
    item_id = context.matches[0].group(1)   # from pattern=r"^item:(\d+)$"
    await query.edit_message_text(f"You chose item {item_id}")
```

## Handler priority (groups)

`add_handler` accepts an optional `group` integer (default `0`). Lower group
numbers are checked first. Within a group, handlers are checked in registration
order.

```python
# group=0 runs first (default)
app.add_handler(CommandHandler("start", start), group=0)

# group=1 runs only if group=0 didn't handle the update
app.add_handler(MessageHandler(filters.ALL, logging_handler), group=1)

# Negative groups run before group=0
app.add_handler(TypeHandler(Update, pre_processor), group=-1)
```

Raise `ApplicationHandlerStop` inside a handler to prevent subsequent handlers
in the same group from processing the update:

```python
from telegram.ext import ApplicationHandlerStop

async def auth_check(update, context):
    if not is_authorized(update.effective_user):
        await update.message.reply_text("Unauthorized")
        raise ApplicationHandlerStop
    # If we reach here, subsequent handlers in the same group run

app.add_handler(TypeHandler(Update, auth_check), group=0)
app.add_handler(CommandHandler("secret", secret_handler), group=0)
```

(Source: `telegram.ext.applicationhandlerstop.rst`)

## Error handler

PTB catches all exceptions raised in handlers and jobs and routes them to
registered error handlers. Without one, PTB logs the traceback but does not
crash the bot.

```python
import traceback
import html
import json
from telegram import Update
from telegram.constants import ParseMode

DEVELOPER_CHAT_ID = 123456789  # your personal chat ID

async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Log the error and send a message to the developer."""
    logger.error("Exception while handling update:", exc_info=context.error)

    # Format the traceback
    tb_list = traceback.format_exception(None, context.error, context.error.__traceback__)
    tb_string = "".join(tb_list)

    update_str = update.to_dict() if isinstance(update, Update) else str(update)
    message = (
        "An exception was raised while handling an update:\n"
        f"<pre>update = {html.escape(json.dumps(update_str, indent=2, ensure_ascii=False))}</pre>\n\n"
        f"<pre>{html.escape(tb_string)}</pre>"
    )

    await context.bot.send_message(
        chat_id=DEVELOPER_CHAT_ID,
        text=message[:4096],   # Telegram message limit
        parse_mode=ParseMode.HTML,
    )

app.add_error_handler(error_handler)
```

(Source: `examples.errorhandlerbot.rst`)

## ChatMemberHandler — tracking bot membership

`ChatMemberHandler` fires when the bot's own membership changes (`my_chat_member`)
or when any member's status changes (`chat_member`).

```python
from telegram import Update
from telegram.ext import ChatMemberHandler

async def track_chats(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Track when the bot is added to or removed from chats."""
    result = update.my_chat_member
    cause_name = result.from_user.full_name

    member = result.new_chat_member
    chat = result.chat

    if member.status == member.MEMBER:
        # Bot was added to a group or accepted a private chat
        if chat.type in [chat.GROUP, chat.SUPERGROUP]:
            context.bot_data.setdefault("group_ids", set()).add(chat.id)
            logger.info("Bot added to group %s by %s", chat.title, cause_name)
    elif member.status == member.LEFT:
        # Bot was removed from a group
        context.bot_data.get("group_ids", set()).discard(chat.id)
        logger.info("Bot removed from group %s by %s", chat.title, cause_name)

async def greet_new_members(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Greet new members who join the group."""
    result = update.chat_member
    if result.new_chat_member.status == result.new_chat_member.MEMBER:
        await update.effective_chat.send_message(
            f"Welcome to {update.effective_chat.title}, "
            f"{result.new_chat_member.user.mention_html()}!",
            parse_mode="HTML",
        )

# MY_CHAT_MEMBER fires when the bot's own status changes
app.add_handler(ChatMemberHandler(track_chats, ChatMemberHandler.MY_CHAT_MEMBER))

# CHAT_MEMBER fires when any member's status changes (requires chat admin rights)
app.add_handler(ChatMemberHandler(greet_new_members, ChatMemberHandler.CHAT_MEMBER))
```

(Source: `examples.chatmemberbot.rst`)

## Handling media (photos, documents, voice)

```python
import os

async def photo_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Download the largest version of a received photo."""
    # update.message.photo is a list of PhotoSize (different resolutions)
    photo = update.message.photo[-1]  # last is largest
    file = await context.bot.get_file(photo.file_id)
    await file.download_to_drive("received_photo.jpg")
    await update.message.reply_text(f"Got photo ({photo.width}x{photo.height})")

async def document_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Download a received document."""
    doc = update.message.document
    file = await context.bot.get_file(doc.file_id)
    path = await file.download_to_drive(doc.file_name)
    await update.message.reply_text(f"Saved: {doc.file_name} ({doc.file_size} bytes)")

async def voice_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Download a voice message."""
    voice = update.message.voice
    file = await context.bot.get_file(voice.file_id)
    await file.download_to_drive(f"voice_{voice.file_unique_id}.ogg")
    await update.message.reply_text(f"Got voice message ({voice.duration}s)")

app.add_handler(MessageHandler(filters.PHOTO, photo_handler))
app.add_handler(MessageHandler(filters.DOCUMENT, document_handler))
app.add_handler(MessageHandler(filters.VOICE, voice_handler))
```

Sending media back:

```python
async def send_media(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat_id = update.effective_chat.id

    # Send photo from file
    with open("image.png", "rb") as f:
        await context.bot.send_photo(chat_id=chat_id, photo=f, caption="A photo")

    # Send photo from URL
    await context.bot.send_photo(
        chat_id=chat_id,
        photo="https://example.com/image.png",
    )

    # Re-send by file_id (faster, no re-upload)
    await context.bot.send_photo(
        chat_id=chat_id,
        photo=some_file_id,  # save file_id from incoming messages
    )

    # Send document
    with open("report.pdf", "rb") as f:
        await context.bot.send_document(
            chat_id=chat_id,
            document=f,
            filename="report.pdf",
            caption="Monthly report",
        )

    # Send audio
    with open("song.mp3", "rb") as f:
        await context.bot.send_audio(
            chat_id=chat_id,
            audio=f,
            title="My Song",
            performer="Artist",
        )
```

## TypeHandler — catch-all by update type

`TypeHandler` matches any update whose type is (or inherits from) the given class.
Useful for pre/post processing or logging all updates:

```python
from telegram import Update
from telegram.ext import TypeHandler

async def log_all_updates(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    logger.debug("Update %s from user %s", update.update_id, update.effective_user)

# Run before all other handlers
app.add_handler(TypeHandler(Update, log_all_updates), group=-1)
```

## InlineQueryHandler

For bots enabled in inline mode via BotFather (`/setinline`). See
`references/inline-and-callbacks.md` for the full inline query reference.

```python
from telegram.ext import InlineQueryHandler

async def inline_handler(update, context):
    ...

app.add_handler(InlineQueryHandler(inline_handler))
```

## Complete handler type list

From `telegram.ext.handlers-tree.rst`:

| Handler | Use case |
|---|---|
| `CommandHandler` | `/command` messages |
| `MessageHandler` | Any message matching a filter |
| `CallbackQueryHandler` | Inline button presses |
| `InlineQueryHandler` | `@bot <query>` inline mode |
| `ConversationHandler` | Multi-step state machine |
| `ChatMemberHandler` | Bot/member status changes |
| `ChatJoinRequestHandler` | Group join requests |
| `PollHandler` | Non-anonymous poll vote updates |
| `PollAnswerHandler` | Individual poll answers |
| `PreCheckoutQueryHandler` | Payment pre-checkout step |
| `ShippingQueryHandler` | Shipping address queries |
| `PaidMediaPurchasedHandler` | Paid media purchase events |
| `MessageReactionHandler` | Message reactions |
| `ChatBoostHandler` | Chat boost events |
| `BusinessConnectionHandler` | Business account connections |
| `BusinessMessagesDeletedHandler` | Business message deletion |
| `ChosenInlineResultHandler` | When user picks an inline result |
| `TypeHandler` | Catch-all by update class |
| `PrefixHandler` | Commands with custom prefix (not `/`) |
| `StringCommandHandler` | String-dispatched (testing) |
| `StringRegexHandler` | Regex-dispatched (testing) |

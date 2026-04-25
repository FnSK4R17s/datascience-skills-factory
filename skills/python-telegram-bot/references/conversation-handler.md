# ConversationHandler

Sources: `telegram.ext.conversationhandler.rst`, `examples.conversationbot.rst`,
`examples.conversationbot2.rst`, `examples.nestedconversationbot.rst`,
`examples.persistentconversationbot.rst`, `examples.rst`.

## Purpose

`ConversationHandler` tracks per-user (or per-chat) state across multiple
messages. It routes each incoming update to a different callback depending on
which state the user is currently in. Classic use cases: multi-step forms,
login wizards, quizzes, onboarding flows.

(Source: `examples.rst` — "A common task for a bot is to ask information from
the user. In v5.0 of this library, we introduced the ConversationHandler for
that exact purpose.")

## Anatomy

```python
from telegram.ext import ConversationHandler, CommandHandler, MessageHandler, filters

# State constants — any hashable value works (int, str, enum)
NAME, AGE, LOCATION, CONFIRM = range(4)

conv_handler = ConversationHandler(
    entry_points=[CommandHandler("start", start)],
    states={
        NAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, got_name)],
        AGE:  [MessageHandler(filters.TEXT & ~filters.COMMAND, got_age)],
        LOCATION: [
            MessageHandler(filters.LOCATION, got_location),
            CommandHandler("skip", skip_location),
        ],
        CONFIRM: [
            MessageHandler(filters.Regex(r"^yes$"), confirmed),
            MessageHandler(filters.Regex(r"^no$"),  declined),
        ],
    },
    fallbacks=[CommandHandler("cancel", cancel)],
)
app.add_handler(conv_handler)
```

### Entry points

A list of handlers that start a new conversation. When one fires, the
conversation begins and transitions to the state returned by its callback.

### State callbacks

Return the next state constant to advance, or `ConversationHandler.END` to
close the conversation:

```python
async def start(update, context) -> int:
    await update.message.reply_text("Hi! What's your name?")
    return NAME                                    # move to NAME state

async def got_name(update, context) -> int:
    context.user_data["name"] = update.message.text
    await update.message.reply_text(
        f"Nice to meet you, {update.message.text}! How old are you?"
    )
    return AGE                                     # move to AGE state

async def got_age(update, context) -> int:
    try:
        age = int(update.message.text)
    except ValueError:
        await update.message.reply_text("Please send a number.")
        return AGE                                 # stay in AGE state

    context.user_data["age"] = age
    await update.message.reply_text(
        "Send your location (or /skip):"
    )
    return LOCATION                                # move to LOCATION state

async def got_location(update, context) -> int:
    loc = update.message.location
    context.user_data["location"] = (loc.latitude, loc.longitude)
    name = context.user_data["name"]
    age = context.user_data["age"]
    await update.message.reply_text(
        f"Summary:\nName: {name}\nAge: {age}\nLocation: {loc.latitude}, {loc.longitude}\n"
        "Correct? (yes/no)"
    )
    return CONFIRM

async def skip_location(update, context) -> int:
    context.user_data["location"] = None
    await update.message.reply_text("Skipped location. All correct? (yes/no)")
    return CONFIRM

async def confirmed(update, context) -> int:
    await update.message.reply_text("Great! Data saved.")
    # Do something with context.user_data["name"], etc.
    return ConversationHandler.END

async def declined(update, context) -> int:
    await update.message.reply_text("Let's start over. What's your name?")
    context.user_data.clear()
    return NAME

async def cancel(update, context) -> int:
    await update.message.reply_text("Cancelled.")
    return ConversationHandler.END
```

### Fallbacks

Checked in every state when no state handler matches. A fallback returning
`ConversationHandler.END` ends the conversation. A fallback returning a state
constant transitions to that state.

## Complete working example — registration form

```python
import logging
from telegram import Update, ReplyKeyboardMarkup, ReplyKeyboardRemove
from telegram.ext import (
    Application, CommandHandler, MessageHandler, ConversationHandler, filters,
    ContextTypes,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TOKEN = "YOUR_BOT_TOKEN"

# Conversation states
NAME, GENDER, PHOTO, LOCATION, BIO = range(5)


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    await update.message.reply_text(
        "Hi! I am going to ask you a few questions.\n"
        "Send /cancel to stop.\n\n"
        "What's your name?",
        reply_markup=ReplyKeyboardRemove(),
    )
    return NAME


async def name(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data["name"] = update.message.text
    reply_keyboard = [["Male", "Female", "Other"]]
    await update.message.reply_text(
        "What is your gender?",
        reply_markup=ReplyKeyboardMarkup(
            reply_keyboard, one_time_keyboard=True,
            input_field_placeholder="Male, Female, or Other?"
        ),
    )
    return GENDER


async def gender(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data["gender"] = update.message.text
    await update.message.reply_text(
        "Send me a photo of yourself, or send /skip.",
        reply_markup=ReplyKeyboardRemove(),
    )
    return PHOTO


async def photo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    photo_file = await update.message.photo[-1].get_file()
    context.user_data["photo"] = photo_file.file_id
    await update.message.reply_text(
        "Got your photo! Now, send your location, or send /skip."
    )
    return LOCATION


async def skip_photo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data["photo"] = None
    await update.message.reply_text(
        "No photo. Now, send your location, or send /skip."
    )
    return LOCATION


async def location(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    loc = update.message.location
    context.user_data["location"] = f"{loc.latitude}, {loc.longitude}"
    await update.message.reply_text("Got your location! Finally, write a short bio.")
    return BIO


async def skip_location(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data["location"] = None
    await update.message.reply_text("No location. Write a short bio.")
    return BIO


async def bio(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data["bio"] = update.message.text
    data = context.user_data
    await update.message.reply_text(
        f"Profile complete!\n"
        f"Name: {data.get('name')}\n"
        f"Gender: {data.get('gender')}\n"
        f"Location: {data.get('location', 'N/A')}\n"
        f"Bio: {data.get('bio')}"
    )
    return ConversationHandler.END


async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    await update.message.reply_text(
        "Bye! Your data was not saved.", reply_markup=ReplyKeyboardRemove()
    )
    return ConversationHandler.END


def main() -> None:
    app = Application.builder().token(TOKEN).build()

    conv_handler = ConversationHandler(
        entry_points=[CommandHandler("start", start)],
        states={
            NAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, name)],
            GENDER: [MessageHandler(filters.Regex("^(Male|Female|Other)$"), gender)],
            PHOTO: [
                MessageHandler(filters.PHOTO, photo),
                CommandHandler("skip", skip_photo),
            ],
            LOCATION: [
                MessageHandler(filters.LOCATION, location),
                CommandHandler("skip", skip_location),
            ],
            BIO: [MessageHandler(filters.TEXT & ~filters.COMMAND, bio)],
        },
        fallbacks=[CommandHandler("cancel", cancel)],
    )

    app.add_handler(conv_handler)
    app.run_polling()


if __name__ == "__main__":
    main()
```

## Conversation scope: per-user vs per-chat

The conversation key determines how state is tracked. Default is per-user per-chat.

| `per_user` | `per_chat` | Key used | Use case |
|---|---|---|---|
| `True` (default) | `True` (default) | `(chat_id, user_id)` | Private bot, each user has own conversation |
| `False` | `True` | `chat_id` | Group game where one conversation covers the whole group |
| `True` | `False` | `user_id` | Cross-chat conversation (same user in multiple chats shares state) |
| `False` | `False` | — | Invalid — raises `ValueError` |

```python
# Group-scoped conversation (one conversation per group, not per user)
ConversationHandler(
    entry_points=[CommandHandler("game", start_game)],
    states={...},
    fallbacks=[CommandHandler("stop", stop_game)],
    per_user=False,    # all users in the group share the conversation state
    per_chat=True,
)
```

## ConversationHandler with inline keyboards

When a state advances via an `InlineKeyboardButton` press, the incoming update
is a `callback_query`, not a `message`. Use `CallbackQueryHandler` in that state:

```python
from telegram import InlineKeyboardButton, InlineKeyboardMarkup

MENU, OPTION_A, OPTION_B = range(3)

async def start(update, context) -> int:
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("Option A", callback_data="a")],
        [InlineKeyboardButton("Option B", callback_data="b")],
    ])
    await update.message.reply_text("Choose:", reply_markup=keyboard)
    return MENU

async def menu_choice(update, context) -> int:
    query = update.callback_query
    await query.answer()
    choice = query.data
    if choice == "a":
        await query.edit_message_text("You chose A! Now tell me more:")
        return OPTION_A
    else:
        await query.edit_message_text("You chose B! Now tell me more:")
        return OPTION_B

async def option_a_detail(update, context) -> int:
    context.user_data["detail"] = update.message.text
    await update.message.reply_text("Got it. Done!")
    return ConversationHandler.END

conv = ConversationHandler(
    entry_points=[CommandHandler("start", start)],
    states={
        MENU: [CallbackQueryHandler(menu_choice)],        # button press, not text
        OPTION_A: [MessageHandler(filters.TEXT & ~filters.COMMAND, option_a_detail)],
    },
    fallbacks=[CommandHandler("cancel", cancel)],
)
```

## Timeout

Set `conversation_timeout` to auto-end stale conversations. Requires `JobQueue`
to be present (install `python-telegram-bot[job-queue]`).

```python
ConversationHandler(
    entry_points=[...],
    states={
        ...,
        ConversationHandler.TIMEOUT: [
            # Optional: handle the timeout event with a callback
            MessageHandler(filters.ALL, timeout_callback),
        ],
    },
    fallbacks=[...],
    conversation_timeout=300,  # 5-minute idle timeout
)

async def timeout_callback(update, context) -> int:
    # update is None, update.effective_user might be None
    # Send a message if we have a stored chat_id
    chat_id = context.user_data.get("chat_id")
    if chat_id:
        await context.bot.send_message(
            chat_id=chat_id,
            text="Conversation timed out. Send /start to begin again.",
        )
    return ConversationHandler.END
```

## Persisting conversations across restarts

Without persistence, all conversation states are lost when the bot restarts.

```python
from telegram.ext import PicklePersistence

persistence = PicklePersistence(filepath="conversations.pickle")

app = (
    Application.builder()
    .token(TOKEN)
    .persistence(persistence)
    .build()
)

conv_handler = ConversationHandler(
    entry_points=[CommandHandler("start", start)],
    states={NAME: [...], AGE: [...]},
    fallbacks=[CommandHandler("cancel", cancel)],
    persistent=True,          # required for persistence
    name="my_conversation",   # required — stable string; keyed in pickle file
)
```

Without `persistent=True` AND `name=...`, PTB keys the conversation by the
object's memory address, which changes every restart. Both are required.
(Source: `examples.persistentconversationbot.rst`)

## Nested ConversationHandlers

Supported but complex. Parent and child handlers share the state namespace —
collisions cause silent routing bugs.

Rules for nested handlers:
1. States must be unique across parent and child — use `range(3)` offsets or
   string prefixes to avoid clashes.
2. The child `ConversationHandler` is added as a state handler inside the parent.
3. When the child ends (returns `ConversationHandler.END`), control returns to
   the parent at the state where the child was entered.
4. Keep nesting to one level. Deeper nesting is nearly impossible to debug.

```python
PARENT_START, CHILD, PARENT_END = range(3)
CHILD_STEP_1, CHILD_STEP_2 = range(3, 5)  # offset to avoid collision

child_handler = ConversationHandler(
    entry_points=[CommandHandler("sub", child_start)],
    states={
        CHILD_STEP_1: [MessageHandler(filters.TEXT, child_step1)],
        CHILD_STEP_2: [MessageHandler(filters.TEXT, child_step2)],
    },
    fallbacks=[CommandHandler("back", child_back)],
    map_to_parent={
        ConversationHandler.END: PARENT_END,  # when child ends, go here in parent
    },
)

parent_handler = ConversationHandler(
    entry_points=[CommandHandler("start", parent_start)],
    states={
        PARENT_START: [
            child_handler,                        # child as a state handler
            CommandHandler("skip", skip_to_end),
        ],
        PARENT_END: [MessageHandler(filters.TEXT, parent_end)],
    },
    fallbacks=[CommandHandler("cancel", cancel)],
)
```

(Source: `examples.nestedconversationbot.rst`)

## Known footguns

**Returning nothing from a callback ends the conversation silently.**
Always return a state constant or `ConversationHandler.END`. A missing `return`
statement leaves the user in a dead state with no error message.

```python
# WRONG — conversation dies silently
async def got_name(update, context):
    context.user_data["name"] = update.message.text
    await update.message.reply_text("Got it!")
    # missing: return AGE

# CORRECT
async def got_name(update, context) -> int:
    context.user_data["name"] = update.message.text
    await update.message.reply_text("Got it!")
    return AGE
```

**Entry points re-fire inside an active conversation by default.**
`allow_reentry=False` (default) — if the user sends `/start` mid-conversation,
it is ignored. `allow_reentry=True` — `/start` restarts the conversation from
scratch, discarding current state.

```python
ConversationHandler(..., allow_reentry=True)  # /start always restarts
```

**State handlers must be the right type for the incoming update.**
If a state is reached by pressing an inline button, the next update is a
`CallbackQuery`, not a `Message`. `MessageHandler` will not fire — use
`CallbackQueryHandler`.

**`ConversationHandler.END` vs returning `None`.**
`END` is the constant `-1`. Returning `None` has the same effect in current PTB
but is undocumented. Always use `ConversationHandler.END`.

**`per_message=True` for inline conversations.**
When the conversation is driven entirely by inline keyboard buttons (no text
input), set `per_message=True` to track state per message rather than per chat.
This avoids one button press in one message affecting a different message's
conversation. (Requires PTB v20.3+.)

## allow_reentry, per_message, block

```python
ConversationHandler(
    entry_points=[...],
    states={...},
    fallbacks=[...],
    allow_reentry=True,     # /start restarts even if conversation is active
    per_message=False,      # True for button-only conversations to track per-message
    block=True,             # False = non-blocking callbacks (use with concurrent_updates)
    conversation_timeout=60,  # seconds idle before auto-END
    persistent=True,
    name="my_conv",
)
```

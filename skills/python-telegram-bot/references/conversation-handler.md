# ConversationHandler

Sources: `telegram.ext.conversationhandler.rst`, `examples.conversationbot.rst`,
`examples.conversationbot2.rst`, `examples.nestedconversationbot.rst`,
`examples.persistentconversationbot.rst`, `examples.rst`.

## Purpose

`ConversationHandler` tracks per-user (or per-chat) state across multiple
messages. It routes each incoming update to a different callback depending on
which state the user is currently in. Classic use cases: multi-step forms,
login wizards, quizzes.

(Source: `examples.rst` — "A common task for a bot is to ask information from
the user. In v5.0 of this library, we introduced the ConversationHandler for
that exact purpose.")

## Anatomy

```python
from telegram.ext import ConversationHandler, CommandHandler, MessageHandler, filters

NAME, AGE, CONFIRM = range(3)   # state constants; any hashable value works

conv_handler = ConversationHandler(
    entry_points=[CommandHandler("start", start)],
    states={
        NAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, name_received)],
        AGE:  [MessageHandler(filters.TEXT & ~filters.COMMAND, age_received)],
        CONFIRM: [
            MessageHandler(filters.Regex(r"^yes$"), confirmed),
            MessageHandler(filters.Regex(r"^no$"),  cancelled),
        ],
    },
    fallbacks=[CommandHandler("cancel", cancel)],
)
app.add_handler(conv_handler)
```

### Entry points

A list of handlers that start a new conversation. When one fires, the
conversation begins in the state returned by its callback.

### State callbacks

Return the next state constant to advance, or `ConversationHandler.END` to
close the conversation.

```python
async def start(update, context) -> int:
    await update.message.reply_text("What is your name?")
    return NAME

async def name_received(update, context) -> int:
    context.user_data["name"] = update.message.text
    await update.message.reply_text("How old are you?")
    return AGE

async def cancel(update, context) -> int:
    await update.message.reply_text("Cancelled.")
    return ConversationHandler.END
```

### Fallbacks

Checked when no state handler matches. A fallback returning
`ConversationHandler.END` ends the conversation. A fallback returning a state
constant transitions to that state.

## Conversation scope: per-user vs per-chat

Default key is `(chat_id, user_id)`.

| `per_user` | `per_chat` | Key |
|-----------|-----------|-----|
| True (default) | True (default) | `(chat_id, user_id)` |
| False | True | `chat_id` |
| True | False | `user_id` |
| False | False | invalid — raises |

## Known footguns

**Returning nothing from a callback ends the conversation silently.**
Always return a state constant or `ConversationHandler.END`. A missing `return`
leaves the user in a dead state with no error.

**Entry points fire even in an active conversation by default.**
`allow_reentry=False` (default) ignores re-entry. `allow_reentry=True` lets
`/start` restart mid-conversation. Document the behavior to users.

**Nested ConversationHandlers are supported but complex.**
States must be unique across parent and child; collisions cause silent routing
bugs. Keep nesting to one level. (Source: `examples.nestedconversationbot.rst`)

**Inline keyboards in conversations need `CallbackQueryHandler` in the state.**
When a state is reached by pressing a button, the next update is a
`callback_query`, not a message. `MessageHandler` will not fire.

**Persistence requires `persistent=True` and `name`.**
Without both, conversation state is keyed by object identity and lost on restart.

```python
ConversationHandler(
    ...,
    persistent=True,
    name="my_conversation",   # stable string, unique per application
)
```

(Source: `examples.persistentconversationbot.rst`)

**`ConversationHandler.END` vs returning `None`.**
`END` is `-1`. Returning `None` has the same effect in current PTB but is
undocumented — use the constant.

## Timeouts

Set `conversation_timeout` (seconds) to auto-end stale conversations. Requires
`JobQueue` to be present (install `python-telegram-bot[job-queue]`).

```python
ConversationHandler(..., conversation_timeout=300)  # 5-minute idle timeout
```

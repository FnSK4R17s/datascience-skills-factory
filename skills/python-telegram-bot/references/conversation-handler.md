# ConversationHandler

## Purpose

`ConversationHandler` tracks per-user (or per-chat) state across multiple
messages. It routes each incoming update to a different callback depending on
which state the user is currently in. Classic use cases: multi-step forms,
login wizards, quizzes.

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

A list of handlers that can start a new conversation. Each must be a handler
object (not a callback). When an entry point fires, the conversation begins in
the state returned by its callback.

### State callbacks

Each state maps to a list of handlers. The callback for the matched handler
returns the next state constant, or `ConversationHandler.END` to close the
conversation.

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

Handlers checked when no state handler matches. Useful for `/cancel` and
unrecognised input. A fallback that returns `ConversationHandler.END` ends the
conversation. A fallback that returns a state transitions to that state.

## Conversation scope: per-user vs per-chat

By default conversations are per-user in a chat (key = `(chat_id, user_id)`).

Change with `per_user` and `per_chat` parameters:

| `per_user` | `per_chat` | Key |
|-----------|-----------|-----|
| True (default) | True (default) | `(chat_id, user_id)` |
| False | True | `chat_id` |
| True | False | `user_id` |
| False | False | Not valid — raises |

## Known footguns

**Returning nothing from a callback ends the conversation silently.**
Always return either a state constant or `ConversationHandler.END`. Forgetting
a `return` statement leaves the user stuck in a dead state.

**Entry points fire even in an active conversation by default.**
Set `allow_reentry=True` to let `/start` restart mid-conversation, or
`allow_reentry=False` (default) to ignore it. If you leave the default,
document to users that they must `/cancel` before restarting.

**Nested ConversationHandlers are supported but complex.**
A sub-conversation inside a parent state is possible; states must be unique
across parent and child or you get silent routing bugs. Keep nesting shallow
(max one level) unless the complexity is justified.

**Inline keyboards in conversations need `CallbackQueryHandler` in the state.**
If a state is reached by pressing a button, the next update is a
`callback_query`, not a message. Add `CallbackQueryHandler` to that state's
handler list; `MessageHandler` will not fire.

**Persistence and ConversationHandler.**
When using `PicklePersistence`, conversation state survives restarts only if
`ConversationHandler` is constructed with `persistent=True` and a `name`
parameter. Without a name, state is keyed by object identity — lost on restart.

```python
ConversationHandler(
    ...,
    persistent=True,
    name="my_conversation",   # stable across restarts
)
```

**`ConversationHandler.END` vs returning `None`.**
`END` is `-1`. Returning `None` does the same thing in current PTB versions but
is undocumented behavior — use the constant.

## Timeouts (conversation_timeout)

Optional: set `conversation_timeout` (seconds) to automatically end stale
conversations. Requires the `JobQueue` to be enabled (it is by default when
PTB-extra requirements are installed).

```python
ConversationHandler(..., conversation_timeout=300)  # 5-minute timeout
```

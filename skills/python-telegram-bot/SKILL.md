---
name: python-telegram-bot
description: >
  Build, debug, and maintain Telegram bots using python-telegram-bot v21+.
  Use when code imports `telegram` or `telegram.ext`, when wiring
  Application/Handler patterns, when implementing ConversationHandler states,
  when scheduling jobs via JobQueue, or when integrating with ASGI/FastAPI
  via webhooks. Triggers on: "telegram bot", "python-telegram-bot",
  "ConversationHandler", "ApplicationBuilder", "PTB", "telegram.ext",
  "InlineKeyboardMarkup", "CallbackQueryHandler", "JobQueue", "PicklePersistence".
  Skip: raw Telegram Bot API over HTTP without the library, Telethon/Pyrogram
  (userbot frameworks), non-Python SDKs, direct httpx/requests API calls.
---

# python-telegram-bot v21+

Sources: scraped rst docs from python-telegram-bot v21.11.1 — 336 files
systematically classified. Narrative prose from `inclusions__*.rst`,
`stability_policy.rst`, `examples.rst` (index + 20 named examples),
tree files for class inventory.

v20 rewrote the library from synchronous to fully async. v21 extended that
foundation. Code written against v13 or earlier will not run under v20+ — the
entire `Updater`-centric pattern is gone, replaced by `Application`.

## The core shift (v13 -> v20+)

- Every handler callback is now `async def`.
- `Bot` methods are all coroutines — call them with `await`.
- Entry point is `Application`, built via `ApplicationBuilder` — not `Updater`.
- `application.run_polling()` / `application.run_webhook()` block the process
  and own the event loop. Do not wrap them in `asyncio.run()`.
  (Source: `inclusions__application_run_tip.rst`)
- For integrating with external asyncio frameworks (FastAPI, etc.), use manual
  lifecycle methods instead of `run_*`. (Source: `inclusions__application_run_tip.rst`)
- `python-telegram-bot` is LGPL-licensed. Dynamic import (standard `pip install`)
  is safe for permissive-licensed projects. See `gpl-license-checker` skill.

## Install

```bash
pip install "python-telegram-bot"                       # core only
pip install "python-telegram-bot[job-queue]"            # + APScheduler JobQueue
pip install "python-telegram-bot[rate-limiter]"         # + AIORateLimiter (aiolimiter)
pip install "python-telegram-bot[callback-data]"        # + arbitrary callback objects
pip install "python-telegram-bot[passport]"             # + Telegram Passport (cryptography)
pip install "python-telegram-bot[all]"                  # everything
```

## When to invoke this skill

- Code has `from telegram.ext import ...` or `import telegram`.
- User asks how to wire handlers, add commands, or respond to messages.
- User is building a multi-step conversation (login wizard, form, quiz).
- User needs scheduled jobs inside the bot process.
- User is deploying via webhook or integrating with FastAPI/ASGI.
- User is migrating from v13 or an older async pattern.
- User is setting up payments, polls, inline keyboards, or deep links.

## When NOT to invoke

- Using Telegram Bot API directly with `requests`/`httpx` (no PTB import).
- Building a Telegram userbot — use Telethon or Pyrogram.
- Non-Python bot (Node.js `telegraf`, Go `telebot`, etc.).

## Extras (opt-in installs)

| Extra | Enables | Install |
|-------|---------|---------|
| `job-queue` | `JobQueue` (APScheduler) | `pip install "python-telegram-bot[job-queue]"` |
| `rate-limiter` | `AIORateLimiter` (aiolimiter) | `pip install "python-telegram-bot[rate-limiter]"` |
| `callback-data` | Arbitrary callback objects, `CallbackDataCache` | `pip install "python-telegram-bot[callback-data]"` |
| `passport` | Telegram Passport decryption (cryptography) | `pip install "python-telegram-bot[passport]"` |
| `all` | All extras | `pip install "python-telegram-bot[all]"` |

## Minimal working bot (echo bot)

This is the starting point for any PTB bot. Copy-paste and run it — just add your token.

```python
import logging
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

TOKEN = "YOUR_BOT_TOKEN"  # from @BotFather


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send a welcome message on /start."""
    user = update.effective_user
    await update.message.reply_html(
        f"Hi {user.mention_html()}! Send me any message and I'll echo it back.",
    )


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text("Send any text message and I'll echo it back.")


async def echo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Echo the user message."""
    await update.message.reply_text(update.message.text)


def main() -> None:
    """Build the Application, register handlers, and start polling."""
    app = Application.builder().token(TOKEN).build()

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, echo))

    # Block until Ctrl-C. PTB owns the event loop.
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
```

Source: `examples.echobot.rst`

## Core architecture

```
ApplicationBuilder.token(...).build()
    |
    Application
    ├── bot           (ExtBot — all Bot API methods)
    ├── updater       (Updater — fetches updates via polling or webhook)
    ├── job_queue     (JobQueue — APScheduler, None if [job-queue] not installed)
    ├── persistence   (BasePersistence implementation, None by default)
    └── handlers      (dict[group_id, list[BaseHandler]])
```

Every incoming update travels through handler groups (ordered by group number,
lower first). Within a group, handlers are checked in registration order. The
first matching handler in a group handles the update. Raise
`ApplicationHandlerStop` to prevent later groups from running.

## Update routing at a glance

```
Update arrives
    └── for each group (sorted by int key, ascending):
            └── for each handler in group:
                    if handler.check_update(update):
                        await handler.handle_update(update, ...)
                        break  # unless block=False
                    # if no handler matched → try next group
```

## Handler quick reference

| Handler class | Matches |
|---|---|
| `CommandHandler("cmd", cb)` | `/cmd` messages |
| `MessageHandler(filters.TEXT, cb)` | Any message matching filter |
| `CallbackQueryHandler(cb, pattern=r"^yes$")` | Inline button presses |
| `InlineQueryHandler(cb)` | `@bot <query>` inline mode |
| `ConversationHandler(...)` | Multi-step conversations with state |
| `ChatMemberHandler(cb)` | Bot added/removed from chats |
| `ChatJoinRequestHandler(cb)` | Join requests in groups |
| `PollHandler(cb)` / `PollAnswerHandler(cb)` | Poll updates / answers |
| `PreCheckoutQueryHandler(cb)` | Payment pre-checkout |
| `ShippingQueryHandler(cb)` | Shipping address queries |
| `TypeHandler(Update, cb)` | Catch-all by update type |

## Filter composition

```python
from telegram.ext import filters

# AND, OR, NOT
MessageHandler(filters.TEXT & ~filters.COMMAND, cb)   # text but not commands
MessageHandler(filters.PHOTO | filters.VIDEO, cb)     # photo or video
MessageHandler(filters.ChatType.PRIVATE, cb)          # private chat only

# Built-in filter examples
filters.TEXT              # any text message
filters.PHOTO             # photo messages
filters.COMMAND           # messages starting with /
filters.FORWARDED         # forwarded messages
filters.Regex(r"^\d+$")   # text matching regex
filters.Document.FileExtension("pdf")  # PDF documents
filters.SUCCESSFUL_PAYMENT # successful payment messages
filters.StatusUpdate.WEB_APP_DATA  # web app data

# Custom filter
from telegram.ext.filters import MessageFilter

class IsAdmin(MessageFilter):
    ADMIN_IDS = {123456789}
    def filter(self, message):
        return message.from_user and message.from_user.id in self.ADMIN_IDS

app.add_handler(MessageHandler(IsAdmin(), admin_only_callback))
```

## context.user_data / chat_data / bot_data

Always store state in the data dicts, not in closures or module globals.
These travel through persistence and are correctly scoped.

```python
async def count(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    context.user_data.setdefault("count", 0)
    context.user_data["count"] += 1
    await update.message.reply_text(f"You've sent {context.user_data['count']} messages.")
```

| Dict | Scope | Persisted |
|------|-------|-----------|
| `context.user_data` | Per user (across all chats) | yes |
| `context.chat_data` | Per chat (across all users in that chat) | yes |
| `context.bot_data` | Global (all users, all chats) | yes |

## Sending messages — most-used methods

```python
# Text
await update.message.reply_text("Hello!")
await update.message.reply_html("<b>Bold</b> text")
await update.message.reply_markdown_v2("*Bold* text")

# Direct send (useful in jobs where there's no update)
await context.bot.send_message(chat_id=12345, text="Hello from job!")

# Photo
await update.message.reply_photo(photo=open("image.png", "rb"))
await update.message.reply_photo(photo="https://example.com/image.png")

# Document
await update.message.reply_document(document=open("file.pdf", "rb"))

# Location
await update.message.reply_location(latitude=51.5, longitude=-0.12)

# Chat action (typing indicator)
await context.bot.send_chat_action(
    chat_id=update.effective_chat.id,
    action="typing"
)

# Media group (album)
from telegram import InputMediaPhoto
await context.bot.send_media_group(
    chat_id=update.effective_chat.id,
    media=[
        InputMediaPhoto(open("a.jpg", "rb")),
        InputMediaPhoto(open("b.jpg", "rb")),
    ],
)
```

Full Bot method inventory: `inclusions__bot_methods.rst`

## Reference map

| File | What it covers |
|------|----------------|
| [references/application-lifecycle.md](references/application-lifecycle.md) | ApplicationBuilder options, polling vs webhook, startup/shutdown hooks, `stop_running()`, asyncio integration, connection pool tuning |
| [references/handlers.md](references/handlers.md) | All handler types, filter composition, handler groups, error handler, ChatMemberHandler, media handling |
| [references/conversation-handler.md](references/conversation-handler.md) | ConversationHandler states, entry points, fallbacks, scope, timeout, nested handlers, complete examples |
| [references/context-and-jobs.md](references/context-and-jobs.md) | CallbackContext, data dicts, JobQueue scheduling patterns, custom context types |
| [references/inline-and-callbacks.md](references/inline-and-callbacks.md) | InlineKeyboardMarkup, callback_data, answer_callback_query, arbitrary callback data, inline query mode, ReplyKeyboard |
| [references/webhooks.md](references/webhooks.md) | Built-in webhook server, ASGI/FastAPI/Starlette/Flask integration, secret tokens, registration |
| [references/persistence.md](references/persistence.md) | PicklePersistence, custom BasePersistence, DictPersistence, pickle warnings, GDPR pruning |
| [references/error-handling.md](references/error-handling.md) | Error handler registration, telegram.error hierarchy, RetryAfter, Forbidden, ChatMigrated |
| [references/rate-limiting.md](references/rate-limiting.md) | AIORateLimiter, BaseRateLimiter, pool_timeout, broadcast patterns |
| [references/payments.md](references/payments.md) | send_invoice, LabeledPrice, PreCheckoutQuery flow, Telegram Stars (XTR), shipping |
| [references/polls.md](references/polls.md) | send_poll, quiz mode, PollHandler, PollAnswerHandler, stop_poll |
| [references/deep-linking.md](references/deep-linking.md) | ?start=PAYLOAD, create_deep_linked_url, group deep links |
| [references/webapp.md](references/webapp.md) | Mini Apps / Web Apps, WebAppInfo, WEB_APP_DATA filter, initData security validation |
| [references/passport.md](references/passport.md) | Telegram Passport (niche), RSA decryption, EncryptedPassportElement |
| [references/examples-catalogue.md](references/examples-catalogue.md) | All 20 official examples with patterns and cross-references |
| [references/class-reference-map.md](references/class-reference-map.md) | Complete module-by-module class inventory |

Start with the file closest to the user's immediate problem.

## Anti-recommendations

- **Do not** call `asyncio.run(application.run_polling(...))` — PTB creates its
  own event loop; nesting causes `RuntimeError: This event loop is already running`.
  (Source: `inclusions__application_run_tip.rst`)
- **Do not** spin up a bare `Bot` and call `await bot.get_updates()` in a loop —
  use `Application` for handler dispatch.
- **Do not** share a single `Application` instance across threads — one instance
  per process.
- **Do not** store state in handler closures or module-level globals — use
  `context.user_data` / `context.chat_data` / `context.bot_data`.
- **Do not** miss `await query.answer()` in `CallbackQueryHandler` — Telegram
  shows a spinner until answered; after ~30 seconds the query expires entirely.
- **Do not** forget `persistent=True` and `name=` on `ConversationHandler` when
  using `PicklePersistence` — without both, state is keyed by memory address
  and lost on restart.
- **Do not** use `PicklePersistence` across PTB major version upgrades without
  migrating the pickle file. (Source: `stability_policy.rst`)
- **Do not** set `connection_pool_size` smaller than `concurrent_updates` — pool
  exhaustion causes apparent hangs under load. (Source: `inclusions__pool_size_tip.rst`)
- **Do not** forget to call `delete_webhook()` before switching from webhook to
  polling — Telegram returns `409 Conflict` on `getUpdates` otherwise.
- **Do not** return `None` from a ConversationHandler state callback — it has
  the same effect as `END` in current PTB but is undocumented. Always return
  an explicit state constant or `ConversationHandler.END`.

---
name: python-telegram-bot
description: >
  Build, debug, and maintain Telegram bots using python-telegram-bot v21+.
  Use when code imports `telegram` or `telegram.ext`, when wiring
  Application/Handler patterns, when implementing ConversationHandler
  states, or when migrating from the synchronous v13 API to async v20+.
  Triggers on: "telegram bot", "python-telegram-bot", "ConversationHandler",
  "ApplicationBuilder", "PTB".
  Skip: raw Telegram Bot API over HTTP without the library, non-Python SDKs,
  Telethon/Pyrogram (userbot frameworks).
---

# python-telegram-bot v21+

python-telegram-bot v20 rewrote the library from synchronous to fully async.
v21 extended that foundation. Code written against v13 or earlier will not run
under v20+ without a migration — the entire `Updater`-centric pattern is gone,
replaced by `Application`.

This skill is a problem statement plus reference data. It defines what the hard
parts are and where to look for authoritative answers. Implementation decisions
belong to the invoking agent, which can adapt to library changes invisible to
this file.

## The core shift (v13 -> v20+)

- Every handler callback is now `async def`.
- `Bot` methods are all coroutines; call them with `await`.
- The entry point is `Application`, built via `ApplicationBuilder`, not `Updater`.
- `application.run_polling()` / `application.run_webhook()` block the process and
  own the event loop — do not call `asyncio.run()` around them.
- `python-telegram-bot` itself is LGPL-licensed. Dynamic import (standard `pip
  install`) is safe for permissive-licensed projects; vendoring/forking requires
  care. See `gpl-license-checker` skill for verdict details.

## When to invoke this skill

- Code has `from telegram.ext import ...` or `import telegram`.
- User asks how to wire handlers, add commands, or respond to messages.
- User is building a multi-step conversation (login wizard, form, quiz).
- User needs scheduled jobs inside the bot process.
- User is deploying via webhook (not polling) or integrating with FastAPI/ASGI.
- User is migrating from v13 or an older async pattern.

## When NOT to invoke

- Using Telegram Bot API directly with `requests`/`httpx` (no PTB import).
- Building a Telegram userbot (not a bot account) — use Telethon or Pyrogram.
- Non-Python bot (Node.js `telegraf`, Go `telebot`, etc.).

## Reference map

| File | What it covers |
|------|---------------|
| [references/application-lifecycle.md](references/application-lifecycle.md) | ApplicationBuilder, polling vs webhook, startup/shutdown hooks, graceful shutdown |
| [references/handlers.md](references/handlers.md) | CommandHandler, MessageHandler, CallbackQueryHandler, filter composition, handler priority |
| [references/conversation-handler.md](references/conversation-handler.md) | ConversationHandler states, entry points, fallbacks, per-user vs per-chat, known footguns |
| [references/context-and-jobs.md](references/context-and-jobs.md) | CallbackContext, bot_data/chat_data/user_data, JobQueue scheduling |
| [references/inline-and-callbacks.md](references/inline-and-callbacks.md) | InlineKeyboardMarkup, callback_data, answer_callback_query, inline query mode |
| [references/webhooks.md](references/webhooks.md) | Custom webhook servers, ASGI/FastAPI integration, secret tokens, local dev tunnels |
| [references/persistence.md](references/persistence.md) | PicklePersistence, custom BasePersistence, state survival across restarts |

Start with the file closest to the user's immediate problem. Cross-reference
only when the primary file says "see also".

## Anti-recommendations

- Do not call `asyncio.run(application.run_polling(...))` — PTB owns its own
  event loop; wrapping it breaks shutdown signal handling.
- Do not spin up a bare `Bot` object and call `await bot.get_updates()` in a
  loop — that is manual long-polling with no handler dispatch; use `Application`.
- Do not share a single `Application` instance across threads — it is not
  thread-safe; run one instance per process.
- Do not store state in handler closure variables — use `context.user_data` /
  `context.chat_data` / `context.bot_data` so persistence can serialize it.

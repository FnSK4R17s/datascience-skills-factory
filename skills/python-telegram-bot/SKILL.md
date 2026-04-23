---
name: python-telegram-bot
description: >
  Build, debug, and maintain Telegram bots using python-telegram-bot v21+.
  Use when code imports `telegram` or `telegram.ext`, when wiring
  Application/Handler patterns, when implementing ConversationHandler states,
  when scheduling jobs via JobQueue, or when integrating with ASGI/FastAPI
  via webhooks. Triggers on: "telegram bot", "python-telegram-bot",
  "ConversationHandler", "ApplicationBuilder", "PTB".
  Skip: raw Telegram Bot API over HTTP without the library, Telethon/Pyrogram
  (userbot frameworks), non-Python SDKs, direct httpx/requests API calls.
---

# python-telegram-bot v21+

v20 rewrote the library from synchronous to fully async. v21 extended that
foundation. Code written against v13 or earlier will not run under v20+ — the
entire `Updater`-centric pattern is gone, replaced by `Application`.

Sources used: scraped rst docs from python-telegram-bot v21.11.1
(`telegram.ext.application.rst`, `telegram.ext.conversationhandler.rst`,
`telegram.ext.filters.rst`, `inclusions__application_run_tip.rst`,
`inclusions__pool_size_tip.rst`, `examples.rst`, `stability_policy.rst`,
`telegram.ext.extbot.rst`, `inclusions__bot_methods.rst`).

## The core shift (v13 -> v20+)

- Every handler callback is now `async def`.
- `Bot` methods are all coroutines; call them with `await`.
- Entry point is `Application`, built via `ApplicationBuilder` — not `Updater`.
- `application.run_polling()` / `application.run_webhook()` block the process
  and own the event loop. Do not call `asyncio.run()` around them.
  (Source: `inclusions__application_run_tip.rst`)
- For integrating with external asyncio frameworks (FastAPI, etc.), use manual
  lifecycle methods instead of `run_*`. (Source: `inclusions__application_run_tip.rst`)
- `python-telegram-bot` is LGPL-licensed. Dynamic import (standard `pip install`)
  is safe for permissive-licensed projects. See `gpl-license-checker` skill.

## When to invoke this skill

- Code has `from telegram.ext import ...` or `import telegram`.
- User asks how to wire handlers, add commands, or respond to messages.
- User is building a multi-step conversation (login wizard, form, quiz).
- User needs scheduled jobs inside the bot process.
- User is deploying via webhook or integrating with FastAPI/ASGI.
- User is migrating from v13 or an older async pattern.

## When NOT to invoke

- Using Telegram Bot API directly with `requests`/`httpx` (no PTB import).
- Building a Telegram userbot — use Telethon or Pyrogram.
- Non-Python bot (Node.js `telegraf`, Go `telebot`, etc.).

## Reference map

| File | What it covers |
|------|----------------|
| [references/application-lifecycle.md](references/application-lifecycle.md) | ApplicationBuilder, polling vs webhook, startup/shutdown hooks, graceful shutdown, asyncio integration |
| [references/handlers.md](references/handlers.md) | CommandHandler, MessageHandler, CallbackQueryHandler, filter composition, error handler, handler groups |
| [references/conversation-handler.md](references/conversation-handler.md) | ConversationHandler states, entry points, fallbacks, per-user vs per-chat, known footguns |
| [references/context-and-jobs.md](references/context-and-jobs.md) | CallbackContext, bot_data/chat_data/user_data, JobQueue scheduling, custom context types |
| [references/inline-and-callbacks.md](references/inline-and-callbacks.md) | InlineKeyboardMarkup, callback_data, answer_callback_query, arbitrary callback data, inline query mode |
| [references/webhooks.md](references/webhooks.md) | Built-in webhook server, ASGI/FastAPI integration, secret tokens, webhook registration |
| [references/persistence.md](references/persistence.md) | PicklePersistence, custom BasePersistence, conversation state survival across restarts |

Start with the file closest to the user's immediate problem.

## Anti-recommendations

- Do not call `asyncio.run(application.run_polling(...))` — PTB creates its own
  event loop; double-nesting causes `RuntimeError` or silent hang.
  (Source: `inclusions__application_run_tip.rst`)
- Do not spin up a bare `Bot` and call `await bot.get_updates()` in a loop —
  use `Application` for handler dispatch.
- Do not share a single `Application` instance across threads — run one instance
  per process.
- Do not store state in handler closures — use `context.user_data` /
  `context.chat_data` / `context.bot_data` so persistence can serialize it.
- When making many concurrent requests (via `block=False`, `create_task`, or
  `JobQueue`), set `concurrent_updates`, `connection_pool_size`, and
  `pool_timeout` in sync on `ApplicationBuilder`.
  (Source: `inclusions__pool_size_tip.rst`)

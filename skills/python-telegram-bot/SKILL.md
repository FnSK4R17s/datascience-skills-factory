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

Sources: scraped rst docs from python-telegram-bot v21.11.1 — 336 files
systematically classified. Narrative prose from `inclusions__*.rst`,
`stability_policy.rst`, `examples.rst` (index + 20 named examples),
tree files for class inventory, autoclass stubs for class names only.

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

## Reference map

| File | What it covers |
|------|----------------|
| [references/application-lifecycle.md](references/application-lifecycle.md) | ApplicationBuilder, polling vs webhook, startup/shutdown hooks, `stop_running()`, asyncio integration, connection pool |
| [references/handlers.md](references/handlers.md) | CommandHandler, MessageHandler, CallbackQueryHandler, filter composition, handler groups, error handler |
| [references/conversation-handler.md](references/conversation-handler.md) | ConversationHandler states, entry points, fallbacks, per-user vs per-chat, timeout, known footguns |
| [references/context-and-jobs.md](references/context-and-jobs.md) | CallbackContext, bot_data/chat_data/user_data, JobQueue scheduling, custom context types |
| [references/inline-and-callbacks.md](references/inline-and-callbacks.md) | InlineKeyboardMarkup, callback_data, answer_callback_query, arbitrary callback data, inline query mode, ReplyKeyboard |
| [references/webhooks.md](references/webhooks.md) | Built-in webhook server, ASGI/FastAPI integration, secret tokens, webhook registration |
| [references/persistence.md](references/persistence.md) | PicklePersistence, custom BasePersistence, pickle-across-versions warning, DictPersistence |
| [references/error-handling.md](references/error-handling.md) | Error handler registration, telegram.error hierarchy, RetryAfter, Forbidden, BadRequest |
| [references/rate-limiting.md](references/rate-limiting.md) | AIORateLimiter, BaseRateLimiter, pool_timeout interaction, broadcast patterns |
| [references/payments.md](references/payments.md) | send_invoice, LabeledPrice, PreCheckoutQuery flow, Telegram Stars (XTR), shipping |
| [references/polls.md](references/polls.md) | send_poll, quiz mode, PollHandler, PollAnswerHandler, stop_poll |
| [references/deep-linking.md](references/deep-linking.md) | ?start=PAYLOAD, create_deep_linked_url, group deep links |
| [references/webapp.md](references/webapp.md) | Mini Apps / Web Apps, WebAppInfo, WEB_APP_DATA filter, security validation |
| [references/passport.md](references/passport.md) | Telegram Passport (niche), RSA decryption, EncryptedPassportElement |
| [references/examples-catalogue.md](references/examples-catalogue.md) | One-line summary of all 20 official examples with cross-reference to reference files |
| [references/class-reference-map.md](references/class-reference-map.md) | Module-by-module class inventory; pointer to installed docstrings for detail |

Start with the file closest to the user's immediate problem. For class-level
detail (attributes, method signatures), consult installed package docstrings or
the official rendered docs — the scrape contains only stubs for most classes.

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
- Do not use `PicklePersistence` across PTB major version upgrades without
  migrating the file — pickled objects from one PTB version may not load in
  another. (Source: `stability_policy.rst`)
- Do not skip `await query.answer()` in `CallbackQueryHandler` — Telegram
  shows a spinner until answered; after ~30 seconds the query expires.

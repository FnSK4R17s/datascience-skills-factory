<p align="center">
  <img src="logo.png" alt="python-telegram-bot" height="88">
</p>

<h1 align="center">python-telegram-bot</h1>

<p align="center">
  <strong>Build Telegram bots with python-telegram-bot v21+.</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

v20 rewrote the library from synchronous to fully async; v21 extended that
foundation. Code written against v13 or earlier will not run under v20+ — the
entire `Updater`-centric pattern is gone, replaced by `Application`.

This skill covers the full v21 surface: the Application lifecycle,
handlers + filters, ConversationHandler states, CallbackContext + JobQueue,
inline queries + callback data, webhooks (polling vs webhook deployment),
persistence, rate limiting, payments, polls, deep linking, Telegram Mini
Apps (WebApp), Passport, and error handling. A catalogue of the 20 official
examples plus a class-reference map round it out.

## Install

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill python-telegram-bot
```

## File structure

```
python-telegram-bot/
├── SKILL.md                        # Entry point, triggers, decision tree
├── README.md                       # This file
├── logo.png                        # Brand mark
└── references/
    ├── application-lifecycle.md    # ApplicationBuilder, run_polling/run_webhook
    ├── handlers.md                 # CommandHandler, MessageHandler, filters
    ├── conversation-handler.md     # states, fallbacks, nested conversations
    ├── context-and-jobs.md         # CallbackContext, user/chat_data, JobQueue
    ├── inline-and-callbacks.md     # inline queries, callback data, keyboards
    ├── webhooks.md                 # polling vs webhook, ASGI integration
    ├── persistence.md              # PicklePersistence, DictPersistence
    ├── rate-limiting.md            # AIORateLimiter, flood control
    ├── error-handling.md           # add_error_handler, retry patterns
    ├── payments.md                 # Telegram Payments flow
    ├── polls.md                    # quiz vs regular, answer handling
    ├── deep-linking.md             # t.me/<bot>?start=<payload>
    ├── webapp.md                   # Telegram Mini Apps
    ├── passport.md                 # Telegram Passport data decoding
    ├── examples-catalogue.md       # 20 official examples, what each teaches
    └── class-reference-map.md      # class → concept → reference
```

## When the skill fires

- Code imports `telegram` or `telegram.ext`.
- User is wiring `Application` / `Handler` patterns, implementing
  `ConversationHandler` states, or switching between polling and webhook.
- User is migrating a v13 bot to v20+.

## When it should NOT fire

- Raw Telegram Bot API over HTTP without the library (`httpx`, `requests`).
- Telethon or Pyrogram (userbot frameworks, different auth model).
- Non-Python Telegram SDKs.

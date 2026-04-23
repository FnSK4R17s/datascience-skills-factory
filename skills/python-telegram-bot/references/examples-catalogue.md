# Examples Catalogue

Sources: `examples.rst` (narrative index), all `examples.*.rst` files (21 example stubs).

All examples are CC0-licensed. All except `rawapibot` use the `telegram.ext`
high-level framework. Source files live in the `examples/` directory of the
python-telegram-bot repository.

## Example index

| Example file | Pattern demonstrated | Reference to read |
|---|---|---|
| `echobot.py` | Minimal bot: `CommandHandler` + `MessageHandler`, replies to text with same text | `handlers.md` |
| `timerbot.py` | `JobQueue` usage: `/set N` schedules a one-shot delayed message, `/unset` cancels | `context-and-jobs.md` |
| `conversationbot.py` | Basic `ConversationHandler`: multi-step form collecting name + location, state diagram included | `conversation-handler.md` |
| `conversationbot2.py` | More complex `ConversationHandler` with branching states and inline keyboard input, state diagram included | `conversation-handler.md` |
| `nestedconversationbot.py` | Nested `ConversationHandler`s: parent + child handlers, state diagram included | `conversation-handler.md` |
| `persistentconversationbot.py` | Conversation state + `user_data` survives restarts via `PicklePersistence`, requires `persistent=True` + `name` on handler | `persistence.md`, `conversation-handler.md` |
| `inlinekeyboard.py` | `InlineKeyboardMarkup`, `CallbackQueryHandler`, `query.answer()`, `query.edit_message_text()` | `inline-and-callbacks.md` |
| `inlinekeyboard2.py` | Interactive menu built with inline keyboard, showing how to update keyboard state | `inline-and-callbacks.md` |
| `deeplinking.py` | Deep-link payload via `?start=PAYLOAD`, `context.args`, `create_deep_linked_url` | `deep-linking.md` |
| `inlinebot.py` | Inline mode: `InlineQueryHandler`, `InlineQueryResultArticle`, `answer()` — requires BotFather `/setinline` | `inline-and-callbacks.md` |
| `pollbot.py` | `send_poll`, `stop_poll`, `PollHandler`, `PollAnswerHandler`, quiz mode | `polls.md` |
| `passportbot.py` | Telegram Passport: HTML login widget, `EncryptedPassportElement`, private-key decryption — requires `[passport]` extra | `passport.md` |
| `paymentbot.py` | Payments: `send_invoice`, `LabeledPrice`, `PreCheckoutQueryHandler`, `SuccessfulPayment` | `payments.md` |
| `errorhandlerbot.py` | Custom error handler: traceback formatting, sending error report to developer chat | `error-handling.md` |
| `chatmemberbot.py` | `ChatMemberHandler`: detecting when bot is added/removed from a chat, `my_chat_member` vs `chat_member` updates | `handlers.md` |
| `webappbot.py` | Telegram Web App (Mini App): `WebAppInfo`, `InlineKeyboardButton(web_app=...)`, `WEB_APP_DATA` filter, plus companion HTML page | `webapp.md` |
| `contexttypesbot.py` | `ContextTypes` + `TypedDict` for typed `user_data` / `chat_data` / `bot_data` in handler signatures | `context-and-jobs.md` |
| `customwebhookbot.py` | Custom webhook with Starlette, Flask, Quart, and Django — PTB manual lifecycle + `process_update()` | `webhooks.md`, `application-lifecycle.md` |
| `arbitrarycallbackdatabot.py` | `arbitrary_callback_data=True`: pass Python objects (not just strings) as `callback_data` — requires `[callback-data]` extra | `inline-and-callbacks.md` |
| `rawapibot.py` | Pure API wrapper only, no `telegram.ext` — direct `bot.get_updates()` loop | `class-reference-map.md` |

## Example patterns cross-reference

| Pattern | Example(s) |
|---------|-----------|
| Minimal first bot | `echobot` |
| Scheduled / timer jobs | `timerbot` |
| Multi-step forms | `conversationbot`, `conversationbot2`, `nestedconversationbot` |
| State that survives restart | `persistentconversationbot` |
| Button menus | `inlinekeyboard`, `inlinekeyboard2` |
| Inline mode (@bot query) | `inlinebot` |
| Deep links | `deeplinking` |
| Polls and quizzes | `pollbot` |
| Payment checkout | `paymentbot` |
| Error reporting | `errorhandlerbot` |
| Chat membership tracking | `chatmemberbot` |
| Web app / Mini App | `webappbot` |
| Typed context data | `contexttypesbot` |
| Webhook + external framework | `customwebhookbot` |
| Complex callback objects | `arbitrarycallbackdatabot` |
| Identity verification | `passportbot` |
| Bare API (no ext) | `rawapibot` |

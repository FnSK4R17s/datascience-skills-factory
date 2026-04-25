# Examples Catalogue

Sources: `examples.rst` (narrative index), all `examples.*.rst` files (20 named examples).

All examples are CC0-licensed. All except `rawapibot` use the `telegram.ext`
high-level framework. Source files live in the `examples/` directory of the
python-telegram-bot repository on GitHub.

GitHub: https://github.com/python-telegram-bot/python-telegram-bot/tree/v21.x/examples

## Example index

| Example | Core pattern | Key classes |
|---|---|---|
| `echobot.py` | Minimal bot skeleton | `CommandHandler`, `MessageHandler`, `filters.TEXT` |
| `timerbot.py` | JobQueue scheduling | `JobQueue.run_once`, `run_repeating`, `get_jobs_by_name` |
| `conversationbot.py` | Basic multi-step form | `ConversationHandler` (3 states), `ReplyKeyboardMarkup` |
| `conversationbot2.py` | Branching conversation + inline keyboard | `ConversationHandler`, `CallbackQueryHandler` in states |
| `nestedconversationbot.py` | Parent + child `ConversationHandler` | `map_to_parent`, nested state spaces |
| `persistentconversationbot.py` | Conversation state survives restarts | `PicklePersistence`, `persistent=True`, `name=` |
| `inlinekeyboard.py` | Inline keyboard basics | `InlineKeyboardMarkup`, `CallbackQueryHandler`, `query.answer()`, `query.edit_message_text()` |
| `inlinekeyboard2.py` | Interactive menu with state | `InlineKeyboardMarkup`, dynamic keyboard rebuild |
| `deeplinking.py` | Deep link payload handling | `context.args`, `create_deep_linked_url` |
| `inlinebot.py` | Inline mode (@bot query) | `InlineQueryHandler`, `InlineQueryResultArticle`, `answer()` |
| `pollbot.py` | Polls and quizzes | `send_poll`, `PollHandler`, `PollAnswerHandler`, `stop_poll` |
| `passportbot.py` | Telegram Passport identity | `EncryptedPassportElement`, private key decryption |
| `paymentbot.py` | Payment checkout | `send_invoice`, `LabeledPrice`, `PreCheckoutQueryHandler` |
| `errorhandlerbot.py` | Custom error handler | `add_error_handler`, traceback formatting, `ParseMode.HTML` |
| `chatmemberbot.py` | Bot membership tracking | `ChatMemberHandler.MY_CHAT_MEMBER`, `CHAT_MEMBER` |
| `webappbot.py` | Telegram Mini App | `WebAppInfo`, `filters.StatusUpdate.WEB_APP_DATA` |
| `contexttypesbot.py` | Typed context data | `ContextTypes`, `TypedDict` for user/chat/bot data |
| `customwebhookbot.py` | Webhook + external framework | PTB manual lifecycle, `process_update()`, Starlette/Flask/Quart/Django |
| `arbitrarycallbackdatabot.py` | Python objects as callback_data | `arbitrary_callback_data=True`, `CallbackDataCache`, `InvalidCallbackData` |
| `rawapibot.py` | Bare API (no `telegram.ext`) | Direct `bot.get_updates()` loop, no handler dispatch |

## Detailed example notes

### echobot.py — the starting point

Every other bot builds on this pattern. Key structure:

```python
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user = update.effective_user
    await update.message.reply_html(f"Hi {user.mention_html()}!")

async def echo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(update.message.text)

app.add_handler(CommandHandler("start", start))
app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, echo))
app.run_polling(allowed_updates=Update.ALL_TYPES)
```

Reference: `handlers.md`

---

### timerbot.py — JobQueue scheduling

Canonical pattern for named, cancellable jobs:

```python
async def set_timer(update, context):
    due = int(context.args[0])
    # Cancel existing job for this chat
    for job in context.job_queue.get_jobs_by_name(str(update.effective_chat.id)):
        job.schedule_removal()
    # Schedule new
    context.job_queue.run_once(alarm, due, chat_id=update.effective_chat.id,
                                name=str(update.effective_chat.id))
    await update.message.reply_text(f"Timer set for {due} seconds!")

async def alarm(context: ContextTypes.DEFAULT_TYPE) -> None:
    await context.bot.send_message(chat_id=context.job.chat_id, text="Beep!")
```

Reference: `context-and-jobs.md`

---

### conversationbot.py — 3-state form

Collects name, location, and biography. Includes a state diagram.
Shows `ReplyKeyboardMarkup` in `GENDER` state, `filters.LOCATION` in `LOCATION` state.

Reference: `conversation-handler.md`

---

### conversationbot2.py — branching + inline keyboard

More complex: user can navigate between states using inline keyboard buttons.
Demonstrates `CallbackQueryHandler` inside a `ConversationHandler` state.
Includes a state diagram showing the branching paths.

Reference: `conversation-handler.md`

---

### nestedconversationbot.py — parent + child handlers

Shows `map_to_parent` to return from child back to a specific parent state.
Critical: state integers in parent and child must not overlap.

Reference: `conversation-handler.md`

---

### persistentconversationbot.py — state across restarts

Shows the two required parameters:

```python
PicklePersistence(filepath="conversationbot.pickle")
ConversationHandler(..., persistent=True, name="my_conversation")
```

Reference: `persistence.md`, `conversation-handler.md`

---

### inlinekeyboard.py — inline keyboard basics

Shows the three required steps:
1. Send message with `InlineKeyboardMarkup`.
2. Register `CallbackQueryHandler`.
3. Always call `await query.answer()` to dismiss spinner.

Reference: `inline-and-callbacks.md`

---

### inlinekeyboard2.py — interactive menu

Shows how to update the keyboard on each press (selected state highlighted).
Pattern: rebuild and pass new `reply_markup` to `edit_message_text`.

Reference: `inline-and-callbacks.md`

---

### deeplinking.py — payload in /start

Three deep-link handling patterns in one bot:
1. Plain `/start` with no payload.
2. `/start <payload>` — basic parameter.
3. Link via `InlineKeyboardButton(url=...)` to open in current chat.

Reference: `deep-linking.md`

---

### inlinebot.py — inline mode

Requires BotFather `/setinline`. Handles `InlineQueryHandler` with
`InlineQueryResultArticle`. Query text → result list → user selects one →
message sent in whatever chat the user is in.

Reference: `inline-and-callbacks.md`

---

### pollbot.py — polls and quizzes

Complete example: send quiz poll, track answers with `PollAnswerHandler`,
show final results, stop poll. Demonstrates non-anonymous poll tracking.

Reference: `polls.md`

---

### passportbot.py — identity verification

Most complex example. Requires:
- RSA key pair (2048+ bits).
- HTML page with Telegram Login Widget.
- `pip install "python-telegram-bot[passport]"`.

Reference: `passport.md`

---

### paymentbot.py — payment checkout

4-step flow: send invoice → `PreCheckoutQueryHandler` (must answer in 10s)
→ approve → `MessageHandler(filters.SUCCESSFUL_PAYMENT, ...)`.

Reference: `payments.md`

---

### errorhandlerbot.py — structured error reporting

Shows the developer-chat notification pattern: format traceback as HTML,
send to a known chat ID. The standard template for all production bots.

```python
async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
    logger.error("Exception while handling update:", exc_info=context.error)
    tb_string = "".join(traceback.format_exception(None, context.error, ...))
    message = f"<pre>{html.escape(tb_string)}</pre>"
    await context.bot.send_message(DEVELOPER_CHAT_ID, message[:4096], ParseMode.HTML)

app.add_error_handler(error_handler)
```

Reference: `error-handling.md`

---

### chatmemberbot.py — membership events

Two handler types:
- `MY_CHAT_MEMBER`: bot added to / removed from a chat.
- `CHAT_MEMBER`: any user joins or leaves (requires admin rights).

Pattern for tracking which groups the bot is in:

```python
app.add_handler(ChatMemberHandler(track_chats, ChatMemberHandler.MY_CHAT_MEMBER))
```

Reference: `handlers.md`

---

### webappbot.py — Telegram Mini App

Bot side: `InlineKeyboardButton(web_app=WebAppInfo(url=...))` + handler for
`filters.StatusUpdate.WEB_APP_DATA`. HTML page: uses iro.js color picker;
calls `window.Telegram.WebApp.sendData(data)` on submit.

Reference: `webapp.md`

---

### contexttypesbot.py — typed context

Shows `TypedDict` + `ContextTypes` for fully typed `user_data`, `chat_data`,
`bot_data`. IDE and mypy recognize the fields.

Reference: `context-and-jobs.md`

---

### customwebhookbot.py — external framework integration

Four tabs: Starlette, Flask (Quart), Quart, Django. All use:
1. PTB manual lifecycle: `initialize()` + `start()` in startup, `stop()` + `shutdown()` in teardown.
2. `process_update(update)` to dispatch updates.
3. Secret token validation.
4. No `run_polling()` or `run_webhook()`.

Reference: `webhooks.md`, `application-lifecycle.md`

---

### arbitrarycallbackdatabot.py — Python objects as callback_data

```python
app = ApplicationBuilder().token(TOKEN).arbitrary_callback_data(True).build()
# Now callback_data can be any picklable object:
InlineKeyboardButton("Go", callback_data={"action": "buy", "id": 42})
```

Handles `InvalidCallbackData` when the cache evicts old entries.

Reference: `inline-and-callbacks.md`

---

### rawapibot.py — bare API without ext

The only example without `telegram.ext`. Directly calls `bot.get_updates()` in
a loop. Not recommended for new bots — shows what the library saves you from.

Reference: `class-reference-map.md`

## Pattern cross-reference

| Pattern | Best example(s) |
|---|---|
| First bot / minimal skeleton | `echobot` |
| Timed/delayed messages | `timerbot` |
| Multi-step forms | `conversationbot`, `conversationbot2` |
| Complex branching flows | `nestedconversationbot` |
| State survives restarts | `persistentconversationbot` |
| Button menus | `inlinekeyboard`, `inlinekeyboard2` |
| Inline mode (@bot query) | `inlinebot` |
| Deep links with payload | `deeplinking` |
| Polls and quizzes | `pollbot` |
| Payment checkout | `paymentbot` |
| Error reporting to developer | `errorhandlerbot` |
| Chat membership tracking | `chatmemberbot` |
| Web app / Mini App | `webappbot` |
| Typed context data | `contexttypesbot` |
| Webhook + FastAPI/Starlette/Flask | `customwebhookbot` |
| Complex callback objects | `arbitrarycallbackdatabot` |
| Identity verification (KYC) | `passportbot` |
| Bare API (no ext) | `rawapibot` |

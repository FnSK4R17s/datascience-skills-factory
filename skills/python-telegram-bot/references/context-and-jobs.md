# Context and Jobs

Sources: `telegram.ext.callbackcontext.rst`, `telegram.ext.contexttypes.rst`,
`telegram.ext.jobqueue.rst`, `telegram.ext.job.rst`,
`examples.timerbot.rst`, `examples.contexttypesbot.rst`.

## CallbackContext

Every handler callback receives `context: ContextTypes.DEFAULT_TYPE`.
The type alias resolves to `CallbackContext[ExtBot, dict, dict, dict]`.

Key attributes:

| Attribute | Type | Scope | Persisted |
|-----------|------|-------|-----------|
| `context.bot` | `Bot` / `ExtBot` | global | N/A |
| `context.bot_data` | `dict` | all users/chats | yes (if persistence set) |
| `context.chat_data` | `dict` | current chat | yes |
| `context.user_data` | `dict` | current user | yes |
| `context.args` | `list[str]` | CommandHandler only | no |
| `context.matches` | `list[re.Match]` | Regex filter / CallbackQueryHandler | no |
| `context.error` | `Exception` | error handler only | no |
| `context.job` | `Job` | job callbacks only | no |

`chat_data` and `user_data` are `None` in handlers that fire without a
specific chat or user. Guard with `if context.chat_data is not None:`.

## Storing state

Always store mutable state in the data dicts, not in handler closures or
module-level globals. The dicts travel through persistence.

```python
async def increment(update, context):
    context.user_data.setdefault("count", 0)
    context.user_data["count"] += 1
    await update.message.reply_text(f"Count: {context.user_data['count']}")
```

## Custom context types

For typed `user_data` / `chat_data` / `bot_data`, use `ContextTypes`.
(Source: `telegram.ext.contexttypes.rst`, `examples.contexttypesbot.rst`)

```python
from telegram.ext import ContextTypes, CallbackContext
from typing import TypedDict

class MyUserData(TypedDict):
    count: int

MyContext = CallbackContext[ExtBot, MyUserData, dict, dict]

app = (
    ApplicationBuilder()
    .token(TOKEN)
    .context_types(ContextTypes(user_data=MyUserData))
    .build()
)
```

## JobQueue

Schedules coroutines inside the bot's event loop.
Requires `pip install "python-telegram-bot[job-queue]"` (APScheduler).
Without it, `app.job_queue` is `None`.
(Source: `examples.rst` — "Note: To use JobQueue, you must install PTB via
`pip install "python-telegram-bot[job-queue]"`")

### Scheduling jobs

```python
async def my_handler(update, context):
    # run once, N seconds from now
    context.job_queue.run_once(callback=notify, when=60,
        chat_id=update.effective_chat.id, data={"msg": "Reminder!"})

    # run every N seconds
    context.job_queue.run_repeating(notify, interval=30, first=10)

    # run at a specific datetime
    context.job_queue.run_at(notify, when=datetime.datetime(2026, 6, 1, 9, 0))

    # run on a cron schedule (monthly example)
    context.job_queue.run_monthly(notify, when=datetime.time(8, 0), day=1)
```

### Job callback signature

Job callbacks receive only `context` — not `update`:

```python
async def notify(context: ContextTypes.DEFAULT_TYPE) -> None:
    job = context.job
    await context.bot.send_message(chat_id=job.chat_id, text=job.data["msg"])
```

### Cancelling jobs

Jobs are named; cancel by name:

```python
context.job_queue.run_once(notify, when=60, name="my_job")

# later:
for job in context.job_queue.get_jobs_by_name("my_job"):
    job.schedule_removal()
```

## Application-level data access outside handlers

Access `bot_data` in startup hooks via the application object:

```python
async def on_startup(app):
    app.bot_data["started_at"] = datetime.datetime.now(tz=datetime.timezone.utc)
```

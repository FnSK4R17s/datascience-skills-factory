# Context and Jobs

## CallbackContext

Every handler callback receives `context: ContextTypes.DEFAULT_TYPE`. The
type alias resolves to `CallbackContext[ExtBot, dict, dict, dict]` but you
rarely need the generic form unless building custom context types.

Key attributes:

| Attribute | Type | Scope | Persisted |
|-----------|------|-------|-----------|
| `context.bot` | `Bot` / `ExtBot` | global | N/A |
| `context.bot_data` | `dict` | all users/chats | yes (if persistence configured) |
| `context.chat_data` | `dict` | current chat | yes |
| `context.user_data` | `dict` | current user | yes |
| `context.args` | `list[str]` | CommandHandler only | no |
| `context.matches` | `list[re.Match]` | Regex filter / CallbackQueryHandler | no |
| `context.error` | `Exception` | error handler only | no |
| `context.job` | `Job` | job callbacks only | no |

`chat_data` and `user_data` are `None` in handlers that fire without a
specific chat or user (e.g. a raw `Update` with only `callback_query` and
no `message`). Guard with `if context.chat_data is not None:`.

## Storing state

Always store mutable state in the data dicts, not in handler closures or
module-level globals. The dicts travel through persistence and are safe to
access across handler invocations.

```python
async def increment(update, context):
    context.user_data.setdefault("count", 0)
    context.user_data["count"] += 1
    await update.message.reply_text(f"Count: {context.user_data['count']}")
```

## Custom context types

If you need typed `user_data` / `chat_data` / `bot_data`, use `ContextTypes`:

```python
from telegram.ext import ContextTypes, CallbackContext

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

`JobQueue` lets you schedule coroutines inside the bot's event loop. It is
included when you install `python-telegram-bot[job-queue]` (requires
APScheduler). It is enabled by default in `ApplicationBuilder` when the
dependency is present.

### Scheduling jobs

```python
async def my_handler(update, context):
    # run once, 60 seconds from now
    context.job_queue.run_once(
        callback=notify,
        when=60,
        chat_id=update.effective_chat.id,
        data={"msg": "Reminder!"},
    )

    # run every 30 seconds
    context.job_queue.run_repeating(notify, interval=30, first=10)

    # run at a specific datetime
    import datetime
    context.job_queue.run_at(notify, when=datetime.datetime(2026, 6, 1, 9, 0))

    # run on a cron schedule
    context.job_queue.run_monthly(notify, when=datetime.time(8, 0), day=1)
```

### Job callback

```python
async def notify(context: ContextTypes.DEFAULT_TYPE) -> None:
    job = context.job          # the Job object
    chat_id = job.chat_id
    data = job.data            # whatever you passed as `data=`
    await context.bot.send_message(chat_id=chat_id, text=data["msg"])
```

### Cancelling jobs

Jobs are named; cancel by name:

```python
context.job_queue.run_once(notify, when=60, name="my_job")

# later:
current_jobs = context.job_queue.get_jobs_by_name("my_job")
for job in current_jobs:
    job.schedule_removal()
```

### JobQueue requires the extra

`pip install "python-telegram-bot[job-queue]"` installs APScheduler. Without
it, `app.job_queue` is `None` and any access raises `AttributeError`.

## Application-level data access outside handlers

If you need `bot_data` outside a handler (e.g. in startup hooks), access it
via the application object:

```python
async def on_startup(app):
    app.bot_data["started_at"] = datetime.datetime.now(tz=datetime.timezone.utc)
```

# Context and Jobs

Sources: `telegram.ext.callbackcontext.rst`, `telegram.ext.contexttypes.rst`,
`telegram.ext.jobqueue.rst`, `telegram.ext.job.rst`,
`examples.timerbot.rst`, `examples.contexttypesbot.rst`.

## CallbackContext

Every handler callback receives `context: ContextTypes.DEFAULT_TYPE`.
The type alias resolves to `CallbackContext[ExtBot, dict, dict, dict]`.

Full attribute reference:

| Attribute | Type | Available in | Persisted |
|---|---|---|---|
| `context.bot` | `ExtBot` | all callbacks | N/A |
| `context.application` | `Application` | all callbacks | N/A |
| `context.bot_data` | `dict` | all callbacks | yes (if persistence set) |
| `context.chat_data` | `dict \| None` | callbacks with a chat | yes |
| `context.user_data` | `dict \| None` | callbacks with a user | yes |
| `context.args` | `list[str] \| None` | `CommandHandler` only | no |
| `context.matches` | `list[re.Match]` | `Regex` filter / `CallbackQueryHandler` | no |
| `context.error` | `Exception \| None` | error handler only | no |
| `context.job` | `Job \| None` | job callbacks only | no |

`chat_data` and `user_data` are `None` in handlers that fire without a
specific chat or user (e.g., inline handlers, `TypeHandler` with no user).
Guard with `if context.chat_data is not None:`.

## Storing and accessing state

Always store mutable state in the data dicts, not in closures or module-level
globals. The dicts travel through persistence and are scoped correctly.

```python
# user_data: one dict per user across all chats
async def count_messages(update, context):
    context.user_data.setdefault("count", 0)
    context.user_data["count"] += 1
    await update.message.reply_text(f"You've sent {context.user_data['count']} messages total.")

# chat_data: one dict per chat (shared by all users in that chat)
async def chat_counter(update, context):
    context.chat_data.setdefault("messages", 0)
    context.chat_data["messages"] += 1
    await update.message.reply_text(
        f"This chat has {context.chat_data['messages']} messages since I started."
    )

# bot_data: global (all users, all chats)
async def global_counter(update, context):
    context.bot_data.setdefault("total", 0)
    context.bot_data["total"] += 1
    await update.message.reply_text(
        f"I've handled {context.bot_data['total']} messages globally."
    )
```

## Accessing data outside handlers

From startup hooks and jobs:

```python
async def on_startup(app: Application) -> None:
    # Initialize bot_data before any update arrives
    app.bot_data["started_at"] = datetime.datetime.now(tz=datetime.timezone.utc)
    app.bot_data["user_set"] = set()

# From a job callback:
async def daily_report(context: ContextTypes.DEFAULT_TYPE) -> None:
    total_users = len(context.bot_data.get("user_set", set()))
    await context.bot.send_message(
        chat_id=ADMIN_CHAT_ID,
        text=f"Daily report: {total_users} unique users",
    )
```

## Custom context types

For typed `user_data` / `chat_data` / `bot_data`, use `ContextTypes`.
This enables IDE autocompletion and type checking.
(Source: `telegram.ext.contexttypes.rst`, `examples.contexttypesbot.rst`)

```python
from typing import TypedDict
from telegram.ext import ContextTypes, CallbackContext, ApplicationBuilder
from telegram import Update

class UserData(TypedDict, total=False):
    name: str
    age: int
    score: int

class ChatData(TypedDict, total=False):
    topic: str
    message_count: int

class BotData(TypedDict, total=False):
    started_at: str
    total_users: int

# The context type with all four type parameters
# CallbackContext[BotType, UserData, ChatData, BotData]
MyContext = CallbackContext[Any, UserData, ChatData, BotData]

async def start(update: Update, context: MyContext) -> None:
    # IDE knows context.user_data has "name", "age", "score"
    context.user_data["name"] = update.effective_user.first_name
    context.user_data["score"] = 0
    await update.message.reply_text(f"Hi {context.user_data['name']}!")

app = (
    ApplicationBuilder()
    .token(TOKEN)
    .context_types(ContextTypes(
        context=MyContext,
        user_data=UserData,
        chat_data=ChatData,
        bot_data=BotData,
    ))
    .build()
)
```

## JobQueue

Schedules coroutines inside the bot's event loop.
Requires `pip install "python-telegram-bot[job-queue]"` (adds APScheduler).
Without it, `app.job_queue` is `None`.

(Source: `examples.rst` — "Note: To use JobQueue, you must install PTB via
`pip install "python-telegram-bot[job-queue]"`")

Check it is available before using:

```python
if app.job_queue is None:
    raise RuntimeError("Install python-telegram-bot[job-queue]")
```

### Job callback signature

Job callbacks receive only `context` — NOT `update`:

```python
async def my_job(context: ContextTypes.DEFAULT_TYPE) -> None:
    job = context.job
    # job.chat_id, job.user_id, job.data, job.name
    await context.bot.send_message(
        chat_id=job.chat_id,
        text=f"Reminder: {job.data['message']}",
    )
```

### run_once — fire once after a delay

```python
async def set_timer(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not context.args:
        await update.message.reply_text("Usage: /set <seconds>")
        return

    seconds = int(context.args[0])
    chat_id = update.effective_chat.id

    context.job_queue.run_once(
        callback=alarm,
        when=seconds,                       # seconds from now (or datetime)
        chat_id=chat_id,
        user_id=update.effective_user.id,
        data={"msg": f"Alarm after {seconds}s"},
        name=str(chat_id),                  # name to find/cancel later
    )
    await update.message.reply_text(f"Timer set for {seconds} seconds.")

async def alarm(context: ContextTypes.DEFAULT_TYPE) -> None:
    await context.bot.send_message(
        chat_id=context.job.chat_id,
        text=context.job.data["msg"],
    )
```

### run_repeating — fire on an interval

```python
async def set_recurring(update, context):
    chat_id = update.effective_chat.id

    # Remove old job if exists
    jobs = context.job_queue.get_jobs_by_name(str(chat_id))
    for job in jobs:
        job.schedule_removal()

    context.job_queue.run_repeating(
        callback=send_update,
        interval=30,             # every 30 seconds
        first=5,                 # first fire 5 seconds from now
        chat_id=chat_id,
        name=str(chat_id),
        data={"topic": "news"},
    )
    await update.message.reply_text("Will send updates every 30 seconds.")

async def send_update(context: ContextTypes.DEFAULT_TYPE) -> None:
    await context.bot.send_message(
        chat_id=context.job.chat_id,
        text=f"Update: topic={context.job.data['topic']}",
    )
```

### run_daily — fire at a specific time each day

```python
import datetime

async def on_startup(app: Application) -> None:
    # Schedule daily 9 AM report (UTC)
    app.job_queue.run_daily(
        callback=daily_report,
        time=datetime.time(hour=9, minute=0, tzinfo=datetime.timezone.utc),
        days=(0, 1, 2, 3, 4),   # Monday–Friday (0=Mon, 6=Sun)
        chat_id=ADMIN_CHAT_ID,
        name="daily_report",
    )

async def daily_report(context: ContextTypes.DEFAULT_TYPE) -> None:
    await context.bot.send_message(
        chat_id=context.job.chat_id,
        text="Good morning! Here's today's report.",
    )
```

### run_monthly — fire on a specific day each month

```python
app.job_queue.run_monthly(
    callback=monthly_billing,
    when=datetime.time(hour=10, minute=0, tzinfo=datetime.timezone.utc),
    day=1,              # 1st of each month
    chat_id=ADMIN_CHAT_ID,
)
```

### run_at — fire once at a specific datetime

```python
import datetime

app.job_queue.run_at(
    callback=send_event_reminder,
    when=datetime.datetime(2026, 6, 1, 9, 0, tzinfo=datetime.timezone.utc),
    chat_id=USER_CHAT_ID,
    data={"event": "Launch party"},
)
```

### Cancelling jobs by name

```python
# Cancel a specific named job
async def unset_timer(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat_id = update.effective_chat.id
    jobs = context.job_queue.get_jobs_by_name(str(chat_id))
    if not jobs:
        await update.message.reply_text("No active timer.")
        return
    for job in jobs:
        job.schedule_removal()
    await update.message.reply_text("Timer cancelled.")
```

### One job per user / per chat pattern

```python
async def set_user_timer(update, context):
    user_id = update.effective_user.id
    chat_id = update.effective_chat.id
    job_name = f"user_{user_id}_timer"

    # Cancel existing timer for this user
    for job in context.job_queue.get_jobs_by_name(job_name):
        job.schedule_removal()

    # Schedule new one
    context.job_queue.run_once(
        callback=user_alarm,
        when=60,
        chat_id=chat_id,
        user_id=user_id,
        name=job_name,
    )
    await update.message.reply_text("Your personal timer is set.")
```

### Startup jobs (run on bot start)

Schedule jobs from the `post_init` hook so they're tied to the application's
lifecycle:

```python
async def on_startup(app: Application) -> None:
    # Health check every 5 minutes
    app.job_queue.run_repeating(
        callback=health_check,
        interval=300,
        first=10,
        name="health_check",
    )

    # Daily cleanup at midnight UTC
    app.job_queue.run_daily(
        callback=cleanup,
        time=datetime.time(0, 0, tzinfo=datetime.timezone.utc),
        name="daily_cleanup",
    )

app = (
    ApplicationBuilder()
    .token(TOKEN)
    .post_init(on_startup)
    .build()
)
```

## Complete timer bot example

```python
import logging
import datetime
from telegram import Update
from telegram.ext import (
    Application, CommandHandler, ContextTypes,
)

logging.basicConfig(level=logging.INFO)
TOKEN = "YOUR_BOT_TOKEN"


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "Hi! Use /set <seconds> to set a timer.\n"
        "Use /unset to cancel the current timer."
    )


async def alarm(context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send the alarm message."""
    job = context.job
    await context.bot.send_message(chat_id=job.chat_id, text=f"Beep! {job.data}")


async def remove_job_if_exists(name: str, context: ContextTypes.DEFAULT_TYPE) -> bool:
    """Remove existing jobs with the given name. Returns True if jobs were removed."""
    current_jobs = context.job_queue.get_jobs_by_name(name)
    if not current_jobs:
        return False
    for job in current_jobs:
        job.schedule_removal()
    return True


async def set_timer(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Add a job to the queue."""
    chat_id = update.effective_message.chat_id
    try:
        due = float(context.args[0])
        if due < 0:
            await update.effective_message.reply_text("Sorry, we can not go back to future!")
            return
        job_removed = await remove_job_if_exists(str(chat_id), context)
        context.job_queue.run_once(alarm, due, chat_id=chat_id,
                                   name=str(chat_id), data=f"Alarm after {due}s")
        text = "Timer successfully set!"
        if job_removed:
            text += " Old one was removed."
        await update.effective_message.reply_text(text)
    except (IndexError, ValueError):
        await update.effective_message.reply_text("Usage: /set <seconds>")


async def unset(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Remove the job if the user changed their mind."""
    chat_id = update.message.chat_id
    job_removed = await remove_job_if_exists(str(chat_id), context)
    text = "Timer successfully cancelled!" if job_removed else "You have no active timer."
    await update.message.reply_text(text)


def main() -> None:
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", start))
    app.add_handler(CommandHandler("set", set_timer))
    app.add_handler(CommandHandler("unset", unset))
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
```

(Source: `examples.timerbot.rst`)

## JobQueue — timezone configuration

APScheduler uses timezone-aware datetimes. Set `tzinfo` in `Defaults`:

```python
import pytz
from telegram.ext import Defaults

app = (
    ApplicationBuilder()
    .token(TOKEN)
    .defaults(Defaults(tzinfo=pytz.timezone("America/New_York")))
    .build()
)
```

Without `tzinfo` set in defaults, datetimes passed to `run_at` etc. are treated
as UTC.

## context.args in CommandHandler

`context.args` is populated only in `CommandHandler` callbacks. It's a list
of space-separated tokens after the command word:

```python
# User sends: /remind 60 Take a break

async def remind(update, context):
    try:
        seconds = int(context.args[0])
        message = " ".join(context.args[1:])   # "Take a break"
    except (IndexError, ValueError):
        await update.message.reply_text("Usage: /remind <seconds> <message>")
        return

    context.job_queue.run_once(
        callback=lambda ctx: ctx.bot.send_message(chat_id=ctx.job.chat_id, text=ctx.job.data),
        when=seconds,
        chat_id=update.effective_chat.id,
        data=message,
    )
    await update.message.reply_text(f"Will remind you in {seconds}s: '{message}'")
```

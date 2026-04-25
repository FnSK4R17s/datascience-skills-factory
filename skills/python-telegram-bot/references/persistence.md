# Persistence

Sources: `telegram.ext.persistence-tree.rst`, `telegram.ext.picklepersistence.rst`,
`telegram.ext.basepersistence.rst`, `telegram.ext.dictpersistence.rst`,
`telegram.ext.persistenceinput.rst`, `stability_policy.rst`,
`examples.persistentconversationbot.rst`.

## The problem

By default, `user_data`, `chat_data`, `bot_data`, and `ConversationHandler`
state live in memory. A bot restart wipes them all. Persistence serializes these
to storage and reloads on startup.

## PicklePersistence — built-in file storage

Serializes everything to a single file via Python `pickle`. Good for small bots
with a single process.

```python
from telegram.ext import ApplicationBuilder, PicklePersistence

persistence = PicklePersistence(
    filepath="bot_data.pickle",    # path to the pickle file
    update_interval=60,            # write to disk every N seconds (default: 60)
    single_file=True,              # True = one file; False = separate files per dict
    on_flush=False,                # True = only write on shutdown, not periodically
)

app = (
    ApplicationBuilder()
    .token(TOKEN)
    .persistence(persistence)
    .build()
)
```

PTB reads the file on `app.initialize()` and writes:
- Periodically (every `update_interval` seconds via a background job).
- On `app.shutdown()`.

### What PicklePersistence saves

| Data | Persisted by default |
|---|---|
| `bot_data` | yes |
| `chat_data` | yes |
| `user_data` | yes |
| Arbitrary callback data cache | yes, if enabled |
| `ConversationHandler` state | yes, if handler has `persistent=True` and `name` |

### Selective persistence

Use `PersistenceInput` to control which data types are saved:

```python
from telegram.ext import PersistenceInput

persistence = PicklePersistence(
    filepath="bot.pickle",
    store_data=PersistenceInput(
        bot_data=True,
        chat_data=True,
        user_data=True,
        callback_data=False,   # don't save arbitrary callback data
    ),
)
```

## Persisting ConversationHandler state

Both `persistent=True` and `name=` are required. Without both, state is keyed
by object memory address (changes on restart) and is effectively not persisted.

```python
from telegram.ext import ConversationHandler, CommandHandler, MessageHandler, filters

NAME, AGE = range(2)

conv_handler = ConversationHandler(
    entry_points=[CommandHandler("start", start)],
    states={
        NAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, got_name)],
        AGE:  [MessageHandler(filters.TEXT & ~filters.COMMAND, got_age)],
    },
    fallbacks=[CommandHandler("cancel", cancel)],
    persistent=True,            # required
    name="registration_conv",   # required — must be unique per Application
)
```

(Source: `examples.persistentconversationbot.rst`)

## Complete persistent bot example

```python
import logging
from telegram import Update
from telegram.ext import (
    Application, CommandHandler, MessageHandler, ConversationHandler,
    PicklePersistence, ContextTypes, filters,
)

logging.basicConfig(level=logging.INFO)
TOKEN = "YOUR_BOT_TOKEN"
NAME, AGE = range(2)


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    # Show existing data if user has started before
    name = context.user_data.get("name")
    if name:
        await update.message.reply_text(
            f"Welcome back, {name}! Your age: {context.user_data.get('age', '?')}\n"
            "Use /update to change your info."
        )
        return ConversationHandler.END
    await update.message.reply_text("Hello! What's your name?")
    return NAME


async def got_name(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data["name"] = update.message.text
    await update.message.reply_text(f"Hi {update.message.text}! How old are you?")
    return AGE


async def got_age(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    try:
        age = int(update.message.text)
    except ValueError:
        await update.message.reply_text("Please send a number.")
        return AGE
    context.user_data["age"] = age
    await update.message.reply_text(
        f"Saved! Name: {context.user_data['name']}, Age: {age}"
    )
    return ConversationHandler.END


async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    await update.message.reply_text("Cancelled.")
    return ConversationHandler.END


def main() -> None:
    persistence = PicklePersistence(filepath="userbot.pickle")

    app = (
        Application.builder()
        .token(TOKEN)
        .persistence(persistence)
        .build()
    )

    conv = ConversationHandler(
        entry_points=[CommandHandler("start", start)],
        states={
            NAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, got_name)],
            AGE:  [MessageHandler(filters.TEXT & ~filters.COMMAND, got_age)],
        },
        fallbacks=[CommandHandler("cancel", cancel)],
        persistent=True,
        name="user_registration",
    )

    app.add_handler(conv)
    app.run_polling()


if __name__ == "__main__":
    main()
```

## Custom persistence — BasePersistence

For production, implement `BasePersistence` to write to a database (Redis,
PostgreSQL, MongoDB, etc.). All methods are `async`.

### Method signatures

```python
from telegram.ext import BasePersistence, PersistenceInput
from telegram.ext._utils.types import BD, CD, UD, CDCData, ConversationDict

class MyPersistence(BasePersistence):
    def __init__(self):
        super().__init__(
            store_data=PersistenceInput(
                bot_data=True,
                chat_data=True,
                user_data=True,
                callback_data=False,
            )
        )

    # --- Read methods (called on startup) ---
    async def get_bot_data(self) -> BD:
        """Return the stored bot_data dict."""
        ...

    async def get_chat_data(self) -> dict[int, CD]:
        """Return all chat_data as {chat_id: data_dict}."""
        ...

    async def get_user_data(self) -> dict[int, UD]:
        """Return all user_data as {user_id: data_dict}."""
        ...

    async def get_callback_data(self) -> CDCData | None:
        """Return callback data cache, or None if not stored."""
        ...

    async def get_conversations(self, name: str) -> ConversationDict:
        """Return conversation states for the named ConversationHandler."""
        ...

    # --- Write methods (called on update and shutdown) ---
    async def update_bot_data(self, data: BD) -> None: ...
    async def update_chat_data(self, chat_id: int, data: CD) -> None: ...
    async def update_user_data(self, user_id: int, data: UD) -> None: ...
    async def update_callback_data(self, data: CDCData) -> None: ...
    async def update_conversation(
        self, name: str, key: tuple[int, ...], new_state: object | None
    ) -> None: ...

    # --- Drop methods (for GDPR / cleanup) ---
    async def drop_chat_data(self, chat_id: int) -> None: ...
    async def drop_user_data(self, user_id: int) -> None: ...

    # --- Lifecycle ---
    async def flush(self) -> None:
        """Called on shutdown. Flush any buffered writes."""
        ...
```

### Redis-backed persistence example

```python
import json
import redis.asyncio as redis
from telegram.ext import BasePersistence, PersistenceInput

class RedisPersistence(BasePersistence):
    def __init__(self, redis_url: str = "redis://localhost:6379"):
        super().__init__(store_data=PersistenceInput())
        self._url = redis_url
        self._redis: redis.Redis | None = None

    async def _get_redis(self) -> redis.Redis:
        if self._redis is None:
            self._redis = redis.from_url(self._url, decode_responses=True)
        return self._redis

    async def get_bot_data(self) -> dict:
        r = await self._get_redis()
        raw = await r.get("bot_data")
        return json.loads(raw) if raw else {}

    async def get_user_data(self) -> dict:
        r = await self._get_redis()
        keys = await r.keys("user_data:*")
        result = {}
        for key in keys:
            user_id = int(key.split(":")[1])
            raw = await r.get(key)
            result[user_id] = json.loads(raw) if raw else {}
        return result

    async def get_chat_data(self) -> dict:
        r = await self._get_redis()
        keys = await r.keys("chat_data:*")
        result = {}
        for key in keys:
            chat_id = int(key.split(":")[1])
            raw = await r.get(key)
            result[chat_id] = json.loads(raw) if raw else {}
        return result

    async def get_callback_data(self):
        return None  # not persisted in this implementation

    async def get_conversations(self, name: str) -> dict:
        r = await self._get_redis()
        raw = await r.get(f"conv:{name}")
        if not raw:
            return {}
        # Keys are tuples — serialize as JSON lists
        data = json.loads(raw)
        return {tuple(k): v for k, v in data.items()}

    async def update_bot_data(self, data: dict) -> None:
        r = await self._get_redis()
        await r.set("bot_data", json.dumps(data))

    async def update_user_data(self, user_id: int, data: dict) -> None:
        r = await self._get_redis()
        await r.set(f"user_data:{user_id}", json.dumps(data))

    async def update_chat_data(self, chat_id: int, data: dict) -> None:
        r = await self._get_redis()
        await r.set(f"chat_data:{chat_id}", json.dumps(data))

    async def update_callback_data(self, data) -> None:
        pass  # not persisted

    async def update_conversation(self, name, key, new_state) -> None:
        r = await self._get_redis()
        raw = await r.get(f"conv:{name}")
        conversations = {}
        if raw:
            data = json.loads(raw)
            conversations = {tuple(k): v for k, v in data.items()}
        if new_state is None:
            conversations.pop(key, None)
        else:
            conversations[key] = new_state
        await r.set(f"conv:{name}", json.dumps({str(list(k)): v for k, v in conversations.items()}))

    async def drop_user_data(self, user_id: int) -> None:
        r = await self._get_redis()
        await r.delete(f"user_data:{user_id}")

    async def drop_chat_data(self, chat_id: int) -> None:
        r = await self._get_redis()
        await r.delete(f"chat_data:{chat_id}")

    async def flush(self) -> None:
        if self._redis:
            await self._redis.aclose()
```

Use it:

```python
app = (
    ApplicationBuilder()
    .token(TOKEN)
    .persistence(RedisPersistence(redis_url="redis://localhost:6379"))
    .build()
)
```

## DictPersistence — in-memory (testing only)

An in-memory persistence implementation. Useful for testing — data does not
survive restarts.

```python
from telegram.ext import DictPersistence

persistence = DictPersistence()
app = ApplicationBuilder().token(TOKEN).persistence(persistence).build()
```

`DictPersistence` also lets you pre-seed data:

```python
persistence = DictPersistence(
    user_data_json='{"12345": {"name": "Alice"}}',
    bot_data_json='{"total": 0}',
)
```

(Source: `telegram.ext.dictpersistence.rst`)

## PicklePersistence limitations

- **Not portable across Python versions without care.** Pickle format can change.
  (Source: `stability_policy.rst` — "pickled objects from one version of PTB
  may not be loadable in future versions")
- **Objects must be picklable.** No lambdas, open file handles, or DB connections.
  Store only plain data in `user_data` etc.
- **Single-process only.** Concurrent writes from multiple processes corrupt the file.
  If you run multiple bot replicas, use a proper database.
- **Grows indefinitely** as new users interact. Schedule a cleanup job.

## Pruning stale data (GDPR / memory)

`user_data` and `chat_data` dicts grow as users interact. Prune them:

```python
async def cleanup_stale_users(context: ContextTypes.DEFAULT_TYPE) -> None:
    """Remove user_data for users who haven't interacted in 90 days."""
    cutoff = datetime.datetime.now() - datetime.timedelta(days=90)
    to_drop = []
    for user_id, data in context.application.user_data.items():
        last_seen = data.get("last_seen")
        if last_seen and last_seen < cutoff:
            to_drop.append(user_id)
    for user_id in to_drop:
        await context.application.drop_user_data(user_id)
        logger.info("Dropped user_data for user %s", user_id)

# Schedule weekly cleanup
async def on_startup(app):
    app.job_queue.run_repeating(cleanup_stale_users, interval=604800)  # 7 days
```

Manual drop:

```python
# Remove data for a specific user (e.g., on /delete_my_data command)
async def delete_my_data(update, context):
    await context.application.drop_user_data(update.effective_user.id)
    await update.message.reply_text("Your data has been deleted.")
```

## Migrating pickled data between PTB versions

When upgrading PTB (especially across major versions), the pickle file may
not load due to class changes. Options:

1. **Delete the pickle file** — users lose state (simplest, acceptable if state
   is non-critical).
2. **Export to JSON before upgrading**, re-import after (`DictPersistence` to JSON,
   rebuild `PicklePersistence`).
3. **Switch to a custom database persistence** (Redis/PostgreSQL) — migrations are
   explicit SQL/schema changes, not implicit pickle format changes.

(Source: `stability_policy.rst`)

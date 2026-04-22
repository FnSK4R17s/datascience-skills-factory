# Persistence

## The problem

By default, `user_data`, `chat_data`, `bot_data`, and `ConversationHandler`
state live in memory. A bot restart wipes them. Persistence serializes these
dicts to a storage backend and reloads them on startup.

## PicklePersistence

The built-in persistence implementation. Serializes to a file using Python's
`pickle` module.

```python
from telegram.ext import ApplicationBuilder, PicklePersistence

persistence = PicklePersistence(filepath="bot_data.pickle")

app = (
    ApplicationBuilder()
    .token(TOKEN)
    .persistence(persistence)
    .build()
)
```

PTB reads the file on `app.initialize()` and writes it periodically (every
`update_interval` seconds, default 60) and on `app.shutdown()`.

### What PicklePersistence saves

| Data | Persisted by default |
|------|---------------------|
| `bot_data` | yes |
| `chat_data` | yes |
| `user_data` | yes |
| `callback_data` (arbitrary callback data cache) | yes, if enabled |
| `ConversationHandler` state | yes, if handler has `persistent=True` and a `name` |

### Persistence scope

To persist only some data stores, use `store_data`:

```python
from telegram.ext import PersistenceInput

PicklePersistence(
    filepath="bot_data.pickle",
    store_data=PersistenceInput(
        bot_data=False,
        chat_data=True,
        user_data=True,
        callback_data=False,
    ),
)
```

## Persisting ConversationHandler state

Two extra parameters are required on `ConversationHandler`:

```python
ConversationHandler(
    entry_points=...,
    states=...,
    fallbacks=...,
    persistent=True,          # enable persistence for this handler
    name="my_conv",           # stable key; must be unique per application
)
```

Without `name`, PTB keys by object identity (memory address), which changes
every restart. Without `persistent=True`, the handler state is never written.

## Custom persistence (BasePersistence)

For production use, implement `BasePersistence` to write to a database:

```python
from telegram.ext import BasePersistence, PersistenceInput
from telegram.ext._utils.types import BD, CD, UD, CDCData, ConversationDict

class RedisPersistence(BasePersistence):
    def __init__(self, redis_client):
        super().__init__(store_data=PersistenceInput())
        self.redis = redis_client

    async def get_bot_data(self) -> BD: ...
    async def get_chat_data(self) -> dict[int, CD]: ...
    async def get_user_data(self) -> dict[int, UD]: ...
    async def get_callback_data(self) -> CDCData | None: ...
    async def get_conversations(self, name: str) -> ConversationDict: ...
    async def update_bot_data(self, data: BD) -> None: ...
    async def update_chat_data(self, chat_id: int, data: CD) -> None: ...
    async def update_user_data(self, user_id: int, data: UD) -> None: ...
    async def update_callback_data(self, data: CDCData) -> None: ...
    async def update_conversation(self, name, key, new_state) -> None: ...
    async def drop_chat_data(self, chat_id: int) -> None: ...
    async def drop_user_data(self, user_id: int) -> None: ...
    async def flush(self) -> None: ...
```

All methods are async. PTB calls them on update and on shutdown.

## Pickle limitations

- Pickle is not human-readable or portable across Python versions without care.
- Stored objects must be picklable — lambda functions, open file handles, and
  database connections are not. Store only plain data in `user_data` etc.
- Concurrent writes from multiple processes will corrupt the file.
  `PicklePersistence` is single-process only.
- The file is overwritten atomically (temp file + rename) on platforms that
  support it. Still, back up in production.

## Data type contracts

PTB expects the data dicts to be plain `dict` instances. Subclasses may work
but are not guaranteed. If you use `defaultdict` or other mapping types,
ensure they serialize correctly with your chosen persistence backend.

## Clearing old data

If a user is deleted or a conversation is abandoned, the data dicts grow
indefinitely. Implement a periodic job or `drop_user_data` / `drop_chat_data`
calls to prune entries older than a threshold.

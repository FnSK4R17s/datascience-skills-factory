# Persistence

Sources: `telegram.ext.persistence-tree.rst`, `telegram.ext.picklepersistence.rst`,
`telegram.ext.basepersistence.rst`, `telegram.ext.dictpersistence.rst`,
`telegram.ext.persistenceinput.rst`, `stability_policy.rst`,
`examples.persistentconversationbot.rst`.

## The problem

By default, `user_data`, `chat_data`, `bot_data`, and `ConversationHandler`
state live in memory. A bot restart wipes them. Persistence serializes these
to storage and reloads on startup.

## PicklePersistence

The built-in implementation. Serializes to a file via Python `pickle`.

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

PTB reads the file on `app.initialize()` and writes periodically (default
every 60 seconds via `update_interval`) and on `app.shutdown()`.

### What PicklePersistence saves

| Data | Persisted by default |
|------|---------------------|
| `bot_data` | yes |
| `chat_data` | yes |
| `user_data` | yes |
| Arbitrary callback data cache | yes, if enabled |
| `ConversationHandler` state | yes, if handler has `persistent=True` and `name` |

### Selective persistence

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

Requires both `persistent=True` and a stable `name` on `ConversationHandler`:

```python
ConversationHandler(
    entry_points=...,
    states=...,
    fallbacks=...,
    persistent=True,
    name="my_conv",    # unique per application; lost on restart without this
)
```

Without `name`, PTB keys by object identity (memory address), which changes
every restart. (Source: `examples.persistentconversationbot.rst`)

## Custom persistence (BasePersistence)

For production, implement `BasePersistence` to write to a database.
All methods are async.

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

## Pickle limitations

- Not portable across Python versions without care.
  (Source: `stability_policy.rst` — "pickled objects from one version of PTB
  may not be loadable in future versions")
- Objects must be picklable — no lambdas, open file handles, or DB connections.
  Store only plain data in `user_data` etc.
- Single-process only. Concurrent writes from multiple processes corrupt the file.
- File is overwritten atomically (temp file + rename) on supporting platforms.

## Clearing old data

`user_data` and `chat_data` dicts grow indefinitely as new users interact.
Schedule a periodic job or call `drop_user_data(user_id)` /
`drop_chat_data(chat_id)` on `BasePersistence` to prune stale entries.

## DictPersistence

An in-memory persistence implementation (no file). Useful for testing.
Data does not survive restarts. (Source: `telegram.ext.dictpersistence.rst`)

```python
from telegram.ext import DictPersistence
persistence = DictPersistence()
```

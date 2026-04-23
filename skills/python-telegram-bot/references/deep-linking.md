# Deep Linking

Sources: `examples.deeplinking.rst`, `examples.rst`,
`telegram.inlinekeyboardbutton.rst`.

## What deep linking does

A deep link is a `t.me/botusername?start=PAYLOAD` URL that opens a private chat
with the bot and automatically sends `/start PAYLOAD`. The bot receives this as a
`CommandHandler("start")` event with `context.args[0]` equal to `PAYLOAD`.

Use cases: referral codes, invite links, one-click feature activation, linking
from web pages into the bot.

## Format

```
https://t.me/yourbotusername?start=PAYLOAD
```

- `PAYLOAD` must match `[A-Za-z0-9_-]{1,64}`.
- For group deep links (opens a group join prompt): use `?startgroup=PAYLOAD`
  instead of `?start=PAYLOAD`.

## Handling deep links

```python
from telegram.ext import CommandHandler

async def start(update, context):
    if context.args:
        payload = context.args[0]
        # e.g. payload = "ref_12345" or "invite_abc"
        await update.message.reply_text(f"You came via link with payload: {payload}")
    else:
        await update.message.reply_text("Hello! No deep link payload.")

app.add_handler(CommandHandler("start", start))
```

## Generating deep links programmatically

```python
from telegram.helpers import create_deep_linked_url

# Requires bot.username to be populated (call bot.get_me() once on startup)
url = create_deep_linked_url(bot_username, "ref_12345")
# Produces: https://t.me/yourbotusername?start=ref_12345
```

## Combining with inline keyboards

```python
from telegram import InlineKeyboardButton, InlineKeyboardMarkup

async def send_invite(update, context):
    url = create_deep_linked_url(context.bot.username, f"inv_{update.effective_user.id}")
    keyboard = [[InlineKeyboardButton("Share invite link", url=url)]]
    await update.message.reply_text(
        "Share this link to invite friends:",
        reply_markup=InlineKeyboardMarkup(keyboard),
    )
```

`InlineKeyboardButton` with a `url` field opens a browser (or the Telegram app
for `t.me` links) rather than sending a `CallbackQuery`.

## Group deep links

```python
group_url = create_deep_linked_url(bot_username, "campaign_launch", group=True)
# Produces: https://t.me/yourbotusername?startgroup=campaign_launch
```

When a user clicks a group link, Telegram prompts them to add the bot to a group.
The bot receives the payload in the `/start` or group join event in the group
context.

## Limitations

- Payload is limited to 64 characters and the character set `[A-Za-z0-9_-]`.
- Deep links only work in private chats (`?start=`) or for adding to groups
  (`?startgroup=`). They do not work in channels.
- `context.args` is a list; the payload is always `context.args[0]` when present.
  Guard: `if context.args and len(context.args) > 0`.

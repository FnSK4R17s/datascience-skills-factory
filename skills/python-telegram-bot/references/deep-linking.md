# Deep Linking

Sources: `examples.deeplinking.rst`, `examples.rst`,
`telegram.inlinekeyboardbutton.rst`.

## What deep linking does

A deep link is a URL of the form `t.me/botusername?start=PAYLOAD` that:
1. Opens a private chat with the bot in Telegram.
2. Automatically sends `/start PAYLOAD`.

The bot receives this as a `CommandHandler("start")` event with
`context.args[0]` equal to `PAYLOAD`.

Use cases:
- Referral / affiliate codes
- Invite links
- One-click feature activation
- Linking from a web page or email into the bot
- Campaign tracking (different payloads for different ad sources)

## URL format

```
# Private chat start
https://t.me/yourbotusername?start=PAYLOAD

# Adds bot to a group (shows a "choose group" dialog)
https://t.me/yourbotusername?startgroup=PAYLOAD

# Short form (same as above)
https://t.me/yourbotusername?start=PAYLOAD
```

Payload constraints:
- Characters: `[A-Za-z0-9_-]` only.
- Max length: 64 characters.
- Deep links do not work in channels.

## Basic deep link handler

```python
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

TOKEN = "YOUR_BOT_TOKEN"


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle /start with optional deep link payload."""
    if context.args:
        payload = context.args[0]
        # Decode and act on the payload
        if payload.startswith("ref_"):
            referrer_id = int(payload[4:])
            await handle_referral(update, context, referrer_id)
        elif payload.startswith("inv_"):
            invite_code = payload[4:]
            await handle_invite(update, context, invite_code)
        else:
            await update.message.reply_text(f"You arrived via: {payload}")
    else:
        await update.message.reply_text(
            "Welcome! No referral link used.\n"
            "Send /invite to get your referral link."
        )


async def handle_referral(update, context, referrer_id):
    user_id = update.effective_user.id
    if user_id == referrer_id:
        await update.message.reply_text("You can't refer yourself!")
        return
    # Credit the referrer
    await update.message.reply_text(
        f"Welcome! You were referred by user #{referrer_id}."
    )
    await context.bot.send_message(
        chat_id=referrer_id,
        text=f"{update.effective_user.full_name} joined via your link!",
    )


async def handle_invite(update, context, invite_code):
    await update.message.reply_text(f"Joining with invite code: {invite_code}")


app = Application.builder().token(TOKEN).build()
app.add_handler(CommandHandler("start", start))
```

## Generating deep links programmatically

```python
from telegram.helpers import create_deep_linked_url

# Requires bot.username to be set (populated by bot.get_me() or after initialize())
async def invite_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    bot_username = context.bot.username   # available after app.initialize()
    user_id = update.effective_user.id

    # Create a referral link for this user
    payload = f"ref_{user_id}"   # fits in 64 chars, A-Za-z0-9_-
    url = create_deep_linked_url(bot_username, payload)

    await update.message.reply_text(
        f"Your referral link:\n{url}\n\n"
        "Share it with friends. When they join via this link, you'll be credited."
    )
```

`create_deep_linked_url` takes:
- `bot_username` (str, without `@`)
- `payload` (str, must match `[A-Za-z0-9_-]{1,64}`)
- `group` (bool, default `False`) — set `True` for group deep links

## Combining with inline keyboards

Present the deep link as a clickable button rather than raw text:

```python
from telegram import InlineKeyboardButton, InlineKeyboardMarkup
from telegram.helpers import create_deep_linked_url

async def share_invite(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    bot_username = context.bot.username
    user_id = update.effective_user.id
    payload = f"ref_{user_id}"
    url = create_deep_linked_url(bot_username, payload)

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("Share invite link", url=url)],
    ])
    await update.message.reply_text(
        "Invite your friends and earn rewards!",
        reply_markup=keyboard,
    )
```

`InlineKeyboardButton(text, url=url)` opens the URL in a browser (or in the
Telegram app for `t.me` links) — no `CallbackQuery` is produced.

## Group deep links

When a user clicks a group deep link, Telegram shows a "Choose a group" dialog.
After the user selects a group, the bot is added and receives the payload in
the group's context:

```python
from telegram.helpers import create_deep_linked_url

async def group_invite(update, context):
    url = create_deep_linked_url(
        context.bot.username,
        "campaign_launch",
        group=True,  # generates ?startgroup= URL
    )
    # Produces: https://t.me/yourbotusername?startgroup=campaign_launch
    await update.message.reply_text(f"Add bot to your group: {url}")
```

The bot receives the `/start campaign_launch` in the group once it's added.
The handler fires with `update.effective_chat.type` being `group` or `supergroup`.

## Full referral system example

```python
import logging
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, ContextTypes
from telegram.helpers import create_deep_linked_url

logging.basicConfig(level=logging.INFO)
TOKEN = "YOUR_BOT_TOKEN"


async def on_startup(app: Application) -> None:
    """Initialize referral data store on startup."""
    app.bot_data.setdefault("referrals", {})   # {referrer_id: [referred_user_ids]}
    app.bot_data.setdefault("joined_users", set())


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user = update.effective_user
    joined = context.bot_data["joined_users"]

    if user.id in joined:
        await update.message.reply_text("Welcome back!")
        return

    joined.add(user.id)

    if context.args and context.args[0].startswith("ref_"):
        try:
            referrer_id = int(context.args[0][4:])
        except ValueError:
            referrer_id = None

        if referrer_id and referrer_id != user.id:
            context.bot_data["referrals"].setdefault(referrer_id, []).append(user.id)
            ref_count = len(context.bot_data["referrals"][referrer_id])
            await context.bot.send_message(
                chat_id=referrer_id,
                text=f"{user.full_name} joined via your link! "
                     f"You now have {ref_count} referral(s).",
            )
            await update.message.reply_text(
                f"Welcome! You were invited by someone."
            )
            return

    await update.message.reply_text(
        "Welcome! Use /invite to get your referral link.\n"
        "Use /mystats to see your referral count."
    )


async def invite(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    payload = f"ref_{user_id}"
    url = create_deep_linked_url(context.bot.username, payload)

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("Share your invite link", url=url)],
    ])
    await update.message.reply_text(
        "Share this link to invite friends:",
        reply_markup=keyboard,
    )


async def mystats(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    referrals = context.bot_data["referrals"].get(user_id, [])
    await update.message.reply_text(
        f"Your referral count: {len(referrals)}"
    )


def main() -> None:
    app = (
        Application.builder()
        .token(TOKEN)
        .post_init(on_startup)
        .build()
    )
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("invite", invite))
    app.add_handler(CommandHandler("mystats", mystats))
    app.run_polling()


if __name__ == "__main__":
    main()
```

(Source: `examples.deeplinking.rst`)

## Payload encoding for longer data

When you need to encode more than a simple ID, use base64 or a short hash:

```python
import base64
import json

def encode_payload(data: dict) -> str:
    """Encode a dict into a deep-link-safe payload (max 64 chars)."""
    json_str = json.dumps(data, separators=(",", ":"))
    encoded = base64.urlsafe_b64encode(json_str.encode()).decode().rstrip("=")
    if len(encoded) > 64:
        raise ValueError(f"Payload too long: {len(encoded)} chars (max 64)")
    return encoded

def decode_payload(encoded: str) -> dict:
    """Decode a payload back into a dict."""
    padding = 4 - len(encoded) % 4
    padded = encoded + "=" * (padding % 4)
    json_str = base64.urlsafe_b64decode(padded).decode()
    return json.loads(json_str)

# Usage:
payload = encode_payload({"action": "redeem", "code": "ABCD"})
# → e.g. "eyJhY3Rpb24iOiJyZWRlZW0iLCJjb2RlIjoiQUJDRCJ9"

url = create_deep_linked_url(bot_username, payload)
```

## Limitations

- Payload: `[A-Za-z0-9_-]` characters only, max 64 characters.
- Deep links only work in private chats (`?start=`) or for adding to groups
  (`?startgroup=`). They do not work in channels.
- `context.args` is a list; payload is always `context.args[0]` when present.
  Guard: `if context.args:` before accessing `context.args[0]`.
- The bot must have been `/started` by the user at least once before, or the
  deep link opens a "Start" button — it doesn't auto-send `/start` in all clients.

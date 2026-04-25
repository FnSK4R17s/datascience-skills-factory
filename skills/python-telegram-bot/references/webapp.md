# Bot Web Apps (Mini Apps)

Sources: `examples.webappbot.rst`, `examples.rst`,
`telegram.webappdata.rst`, `telegram.webappinfo.rst`,
`telegram.menubuttonwebapp.rst`, `telegram.sentwebappmessage.rst`.

## What Web Apps are

Telegram Web Apps (Mini Apps) let a bot open a full-page web page inside the
Telegram client. The page can interact with the bot via the Telegram Web App JS
SDK (`window.Telegram.WebApp`). Common uses: forms, games, dashboards,
storefronts, color pickers, file managers.

The web app runs as a web page but inside Telegram — the SDK provides access
to user info, theme colors, and a `sendData` function to communicate back.

(Source: `examples.rst` — "Uses the iro.js JavaScript library to showcase a
user interface that is hard to achieve with native Telegram functionality.")

## Requirements

- The web app URL must be served over HTTPS.
- The URL must be whitelisted in BotFather (configure under bot settings).
- Use the Telegram Web App JS SDK: `https://telegram.org/js/telegram-web-app.js`
- `WebAppData.data` is received only when the web app calls `sendData()`.

## Launching a web app from the bot

### Via inline keyboard button

```python
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo

WEB_APP_URL = "https://yourdomain.com/webapp"   # must be HTTPS


async def open_webapp_command(update, context):
    keyboard = [[
        InlineKeyboardButton(
            "Open App",
            web_app=WebAppInfo(url=WEB_APP_URL),
        )
    ]]
    await update.message.reply_text(
        "Click the button to open the web app:",
        reply_markup=InlineKeyboardMarkup(keyboard),
    )
```

### Via reply keyboard button

```python
from telegram import KeyboardButton, ReplyKeyboardMarkup, WebAppInfo

async def open_webapp_reply_keyboard(update, context):
    button = KeyboardButton(
        text="Open App",
        web_app=WebAppInfo(url=WEB_APP_URL),
    )
    await update.message.reply_text(
        "Tap the button:",
        reply_markup=ReplyKeyboardMarkup([[button]], resize_keyboard=True),
    )
```

### Via the chat menu button

Set the bot's menu button (the button next to the message input field) to
open the web app:

```python
from telegram import MenuButtonWebApp, WebAppInfo

async def set_menu_button(update, context):
    await context.bot.set_chat_menu_button(
        chat_id=update.effective_chat.id,
        menu_button=MenuButtonWebApp(
            text="Open App",
            web_app=WebAppInfo(url=WEB_APP_URL),
        ),
    )
    await update.message.reply_text("Menu button set!")

# Reset to default commands menu
from telegram import MenuButtonCommands

async def reset_menu_button(update, context):
    await context.bot.set_chat_menu_button(
        chat_id=update.effective_chat.id,
        menu_button=MenuButtonCommands(),
    )
```

## Receiving data from the web app

When the web app's JavaScript calls `window.Telegram.WebApp.sendData(data)`,
Telegram sends the bot a `Message` with `web_app_data.data` set.

```python
import json
from telegram.ext import MessageHandler, filters

async def web_app_data_handler(update, context):
    data_str = update.effective_message.web_app_data.data
    button_text = update.effective_message.web_app_data.button_text

    try:
        data = json.loads(data_str)
    except json.JSONDecodeError:
        data = data_str   # treat as plain string if not JSON

    await update.message.reply_text(
        f"Received from web app (button: '{button_text}'):\n{data}"
    )

app.add_handler(MessageHandler(
    filters.StatusUpdate.WEB_APP_DATA,
    web_app_data_handler,
))
```

`web_app_data.data` is the string passed to `sendData()` in the JavaScript.
`web_app_data.button_text` is the text of the button that launched the web app.

## Web App JavaScript side

Minimal HTML page that sends data back to the bot:

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>My Web App</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
</head>
<body>
    <h1>Choose a color</h1>
    <input type="color" id="colorPicker" value="#ff0000">
    <button onclick="sendColor()">Send to Bot</button>

    <script>
        const tg = window.Telegram.WebApp;
        tg.ready();   // tell Telegram the app is ready

        // Apply Telegram theme colors
        document.body.style.backgroundColor = tg.themeParams.bg_color;
        document.body.style.color = tg.themeParams.text_color;

        function sendColor() {
            const color = document.getElementById("colorPicker").value;
            tg.sendData(JSON.stringify({ color: color }));
            // sendData() closes the web app and sends a message to the bot
        }

        // Show the main button (optional)
        tg.MainButton.text = "Confirm";
        tg.MainButton.show();
        tg.MainButton.onClick(sendColor);
    </script>
</body>
</html>
```

## initData security validation

The JS SDK provides `window.Telegram.WebApp.initData` — a URL-encoded string
containing user info and a hash for server-side validation. Always validate
this hash before trusting the data.

The validation algorithm:
1. Parse the `initData` URL-encoded string.
2. Remove the `hash` field.
3. Sort remaining fields alphabetically.
4. Join as `key=value\n` pairs.
5. HMAC-SHA256 of the joined string using the key = HMAC-SHA256 of the bot token
   using the string `"WebAppData"` as the key.
6. Compare with the `hash` field from step 2.

```python
import hmac
import hashlib
from urllib.parse import parse_qsl

def validate_init_data(init_data: str, bot_token: str) -> bool:
    """Validate Telegram Mini App initData signature."""
    # Parse the URL-encoded string
    parsed = dict(parse_qsl(init_data))
    received_hash = parsed.pop("hash", "")

    # Build the data-check string
    data_check_pairs = sorted(f"{k}={v}" for k, v in parsed.items())
    data_check_string = "\n".join(data_check_pairs)

    # Compute expected hash
    secret_key = hmac.new(
        b"WebAppData",
        bot_token.encode(),
        hashlib.sha256,
    ).digest()

    expected_hash = hmac.new(
        secret_key,
        data_check_string.encode(),
        hashlib.sha256,
    ).hexdigest()

    return hmac.compare_digest(received_hash, expected_hash)
```

Use this in your web server endpoint:

```python
from fastapi import FastAPI, Request, HTTPException

app_server = FastAPI()

@app_server.post("/api/submit")
async def handle_submission(request: Request):
    body = await request.json()
    init_data = body.get("initData", "")

    if not validate_init_data(init_data, BOT_TOKEN):
        raise HTTPException(status_code=403, detail="Invalid initData")

    # Parse user info from initData
    from urllib.parse import parse_qsl
    import json
    parsed = dict(parse_qsl(init_data))
    user = json.loads(parsed.get("user", "{}"))
    user_id = user.get("id")

    # Process the request for this user
    return {"status": "ok", "user_id": user_id}
```

## Complete Web App bot example

```python
import json
import logging
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, WebAppInfo
from telegram.ext import Application, CommandHandler, MessageHandler, ContextTypes, filters

logging.basicConfig(level=logging.INFO)
TOKEN = "YOUR_BOT_TOKEN"
WEB_APP_URL = "https://yourdomain.com/colorpicker"


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    keyboard = [[
        InlineKeyboardButton(
            "Pick a color",
            web_app=WebAppInfo(url=WEB_APP_URL),
        )
    ]]
    await update.message.reply_text(
        "Open the color picker:",
        reply_markup=InlineKeyboardMarkup(keyboard),
    )


async def web_app_data(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle data sent from the web app via sendData()."""
    raw = update.effective_message.web_app_data.data
    try:
        data = json.loads(raw)
        color = data.get("color", "unknown")
        await update.message.reply_text(
            f"You chose color: {color}",
            reply_markup=None,
        )
        # Store the choice
        context.user_data["chosen_color"] = color
    except json.JSONDecodeError:
        await update.message.reply_text(f"Received: {raw}")


def main() -> None:
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.StatusUpdate.WEB_APP_DATA, web_app_data))
    app.run_polling()


if __name__ == "__main__":
    main()
```

(Source: `examples.webappbot.rst`)

## SDK features overview

The Telegram Web App JS SDK (`window.Telegram.WebApp`) provides:

| API | Purpose |
|---|---|
| `tg.ready()` | Signal Telegram the app is loaded |
| `tg.sendData(data)` | Send string data to bot and close the app |
| `tg.initData` | URL-encoded string with user info + hash |
| `tg.initDataUnsafe` | Parsed version of initData (not validated — use initData for validation) |
| `tg.themeParams` | Current Telegram theme colors |
| `tg.MainButton` | The bottom main action button |
| `tg.BackButton` | Back button shown in the header |
| `tg.close()` | Close the web app |
| `tg.expand()` | Expand to full height |
| `tg.openLink(url)` | Open a URL in the browser |
| `tg.openTelegramLink(url)` | Open a Telegram link |
| `tg.showAlert(text, callback)` | Show a native alert |
| `tg.showConfirm(text, callback)` | Show a native confirm dialog |
| `tg.HapticFeedback` | Trigger haptic feedback on mobile |

## Sending messages from web app to inline context

For bots in inline mode, use `save_prepared_inline_message` to prepare a message
that the web app can trigger sending:

```python
from telegram import PreparedInlineMessage

async def prepare_message(update, context):
    """Pre-stage a message for the web app to send."""
    result = await context.bot.save_prepared_inline_message(
        user_id=update.effective_user.id,
        result=InlineQueryResultArticle(
            id="prepared",
            title="Prepared message",
            input_message_content=InputTextMessageContent("Hello from the web app!"),
        ),
        allow_user_chats=True,
    )
    # Return the prepared_message_id to the web app via some mechanism
    # (e.g., store in user_data and let web app fetch it via your API)
    context.user_data["prepared_msg_id"] = result.id
```

The web app then uses `window.Telegram.WebApp.sendPreparedMessage(id, ...)` to
trigger sending in the user's chosen chat. (v21+ feature)

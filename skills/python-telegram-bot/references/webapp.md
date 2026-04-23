# Bot Web Apps (Mini Apps)

Sources: `examples.webappbot.rst`, `examples.rst`,
`telegram.webappdata.rst`, `telegram.webappinfo.rst`,
`telegram.menubuttonwebapp.rst`, `telegram.sentwebappmessage.rst`.

## What Web Apps are

Telegram Web Apps (Mini Apps) let a bot open a full-page web page inside the
Telegram client. The page can interact with the bot via the Telegram Web App JS
SDK (`window.Telegram.WebApp`). Common uses: forms, games, dashboards, storefronts.
(Source: `examples.rst` — "Uses the iro.js JavaScript library to showcase a user
interface that is hard to achieve with native Telegram functionality.")

## Launching a web app

### Via inline keyboard button

```python
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo

url = "https://yourdomain.com/webapp"   # must be HTTPS

keyboard = [[InlineKeyboardButton("Open App", web_app=WebAppInfo(url=url))]]
await update.message.reply_text(
    "Click to open the web app:",
    reply_markup=InlineKeyboardMarkup(keyboard),
)
```

### Via reply keyboard button

```python
from telegram import KeyboardButton, ReplyKeyboardMarkup

button = KeyboardButton("Open App", web_app=WebAppInfo(url=url))
await update.message.reply_text(
    "Tap to open:",
    reply_markup=ReplyKeyboardMarkup([[button]], resize_keyboard=True),
)
```

### Via MenuButton

Set the bot's menu button to open a web app directly:

```python
from telegram import MenuButtonWebApp, WebAppInfo

await context.bot.set_chat_menu_button(
    chat_id=update.effective_chat.id,
    menu_button=MenuButtonWebApp(text="Open App", web_app=WebAppInfo(url=url)),
)
```

## Receiving data from the web app

When the web app calls `window.Telegram.WebApp.sendData(data)`, Telegram sends
the bot a `Message` with `web_app_data.data` set:

```python
from telegram.ext import MessageHandler, filters

async def web_app_data_handler(update, context):
    data = update.effective_message.web_app_data.data
    # data is the string passed to sendData() in the JS side
    parsed = json.loads(data)
    await update.message.reply_text(f"Received: {parsed}")

app.add_handler(MessageHandler(filters.StatusUpdate.WEB_APP_DATA, web_app_data_handler))
```

## Security

The JS SDK provides `window.Telegram.WebApp.initData` — a URL-encoded string
containing the user's data and a hash for server-side validation. Always validate
this hash on your server before trusting the data.

Validation follows the algorithm in Telegram's official docs (HMAC-SHA256 over
sorted key=value pairs with the bot token as the key). Do not skip validation in
production.

## Sending messages from a web app to an inline context

For inline bots, use `bot.save_prepared_inline_message()` (v21+) to store a
message on Telegram's side, then the web app triggers sending it via
`window.Telegram.WebApp.sendData`.

## Requirements

- The web app URL must be served over HTTPS.
- The URL must be whitelisted in BotFather (under "Web App" settings or via
  `set_my_description` / domain verification).
- `WebAppData.data` is available only when the web app uses `sendData()` — it is
  not the same as the user submitting a form.

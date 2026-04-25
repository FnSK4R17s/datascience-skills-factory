# Class Reference Map

Sources: `telegram.rst`, `telegram.ext.rst`, `telegram.at-tree.rst`,
`telegram.inline-tree.rst`, `telegram.payments-tree.rst`,
`telegram.passport-tree.rst`, `telegram.games-tree.rst`,
`telegram.stickers-tree.rst`, `telegram.ext.handlers-tree.rst`,
`telegram.ext.persistence-tree.rst`, `telegram.ext.acd-tree.rst`,
`telegram.ext.rate-limiting-tree.rst`, `telegram_auxil.rst`,
`inclusions__bot_methods.rst`.

## How to use this file

The scraped documentation consists of Sphinx `autoclass` stubs — they reference
the library's Python docstrings but do not copy them. For full class signatures,
attributes, and method details, use:

1. `help(telegram.ext.Application)` in a Python REPL with PTB installed.
2. The installed package's `__doc__` attributes.
3. The official rendered docs at https://python-telegram-bot.readthedocs.io/

This file maps module structure so you know where each class lives and what
Bot API methods exist.

## `telegram` package — core objects

### Update types

```python
from telegram import Update

# Update attributes (one is set per update, others are None)
update.message              # Message
update.edited_message       # Message (edited)
update.channel_post         # Message (in channel)
update.edited_channel_post  # Message (edited channel post)
update.business_connection  # BusinessConnection
update.business_message     # Message (from business account)
update.callback_query       # CallbackQuery (inline keyboard press)
update.inline_query         # InlineQuery
update.chosen_inline_result # ChosenInlineResult
update.shipping_query       # ShippingQuery
update.pre_checkout_query   # PreCheckoutQuery
update.poll                 # Poll (vote count changed)
update.poll_answer          # PollAnswer (user voted, non-anon)
update.my_chat_member       # ChatMemberUpdated (bot's own status)
update.chat_member          # ChatMemberUpdated (any member)
update.chat_join_request    # ChatJoinRequest
update.chat_boost           # ChatBoostUpdated
update.removed_chat_boost   # ChatBoostRemoved
update.message_reaction     # MessageReactionUpdated
update.message_reaction_count # MessageReactionCountUpdated
update.purchased_paid_media # PaidMediaPurchased

# Convenience properties (look at all update types)
update.effective_message    # first non-None of: message, edited_message, etc.
update.effective_user       # the User involved
update.effective_chat       # the Chat involved
```

### Message

```python
from telegram import Message

# Common attributes
message.message_id          # int
message.from_user           # User | None
message.chat                # Chat
message.date                # datetime
message.text                # str | None (text messages)
message.caption             # str | None (photo/video captions)
message.photo               # list[PhotoSize] | None (last = largest)
message.video               # Video | None
message.audio               # Audio | None
message.voice               # Voice | None
message.document            # Document | None
message.sticker             # Sticker | None
message.animation           # Animation | None
message.location            # Location | None
message.contact             # Contact | None
message.poll                # Poll | None
message.web_app_data        # WebAppData | None
message.passport_data       # PassportData | None
message.successful_payment  # SuccessfulPayment | None
message.invoice             # Invoice | None
message.entities            # list[MessageEntity] | None (text formatting)
message.reply_to_message    # Message | None

# Convenience reply methods (equivalent to bot.send_*):
await message.reply_text(text, **kwargs)
await message.reply_html(text, **kwargs)
await message.reply_markdown_v2(text, **kwargs)
await message.reply_photo(photo, **kwargs)
await message.reply_document(document, **kwargs)
await message.reply_location(latitude, longitude, **kwargs)
await message.reply_poll(question, options, **kwargs)
await message.delete()
await message.pin()
await message.forward(chat_id)
await message.copy(chat_id)
```

### User

```python
from telegram import User

user.id               # int — stable across all chats
user.first_name       # str
user.last_name        # str | None
user.username         # str | None (without @)
user.language_code    # str | None (IETF BCP 47 tag)
user.is_bot           # bool
user.is_premium       # bool

# Convenience methods
user.full_name                      # "First Last"
user.mention_html()                 # '<a href="tg://user?id=...">First</a>'
user.mention_markdown()             # '[First](tg://user?id=...)'
user.mention_markdown_v2()         # MarkdownV2 safe version
user.link                          # "tg://user?id=..."
await user.get_profile_photos()    # UserProfilePhotos
```

### Chat

```python
from telegram import Chat

chat.id               # int
chat.type             # "private", "group", "supergroup", "channel"
chat.title            # str | None (groups/channels)
chat.username         # str | None

# Type checks
chat.type == Chat.PRIVATE     # or chat.type == "private"
chat.type == Chat.GROUP
chat.type == Chat.SUPERGROUP
chat.type == Chat.CHANNEL
```

## Bot API methods — complete list

All are async methods on `context.bot` / `app.bot`. (Source: `inclusions__bot_methods.rst`)

### Sending messages

| Method | Purpose |
|---|---|
| `send_message(chat_id, text, ...)` | Send text |
| `send_photo(chat_id, photo, ...)` | Send photo |
| `send_video(chat_id, video, ...)` | Send video |
| `send_audio(chat_id, audio, ...)` | Send audio (music) |
| `send_voice(chat_id, voice, ...)` | Send voice message |
| `send_document(chat_id, document, ...)` | Send document |
| `send_animation(chat_id, animation, ...)` | Send GIF |
| `send_sticker(chat_id, sticker, ...)` | Send sticker |
| `send_video_note(chat_id, video_note, ...)` | Send video note (circle) |
| `send_location(chat_id, latitude, longitude, ...)` | Send location |
| `send_venue(chat_id, latitude, longitude, title, address, ...)` | Send venue |
| `send_contact(chat_id, phone_number, first_name, ...)` | Send contact |
| `send_poll(chat_id, question, options, ...)` | Send poll |
| `send_dice(chat_id, ...)` | Send animated dice |
| `send_chat_action(chat_id, action, ...)` | Typing indicator etc |
| `send_media_group(chat_id, media, ...)` | Send album |
| `send_invoice(chat_id, title, description, payload, ...)` | Send payment invoice |
| `send_game(chat_id, game_short_name, ...)` | Send game |
| `send_gift(chat_id, gift_id, ...)` | Send Telegram gift |
| `send_paid_media(chat_id, star_count, media, ...)` | Send paid media |
| `copy_message(chat_id, from_chat_id, message_id, ...)` | Copy message silently |
| `copy_messages(chat_id, from_chat_id, message_ids, ...)` | Copy multiple messages |
| `forward_message(chat_id, from_chat_id, message_id, ...)` | Forward with attribution |
| `forward_messages(chat_id, from_chat_id, message_ids, ...)` | Forward multiple |

### Editing messages

| Method | Purpose |
|---|---|
| `edit_message_text(text, chat_id, message_id, ...)` | Edit text |
| `edit_message_caption(caption, chat_id, message_id, ...)` | Edit caption |
| `edit_message_media(media, chat_id, message_id, ...)` | Replace media |
| `edit_message_reply_markup(reply_markup, chat_id, message_id, ...)` | Replace keyboard |
| `delete_message(chat_id, message_id)` | Delete message |
| `delete_messages(chat_id, message_ids)` | Delete multiple |
| `stop_poll(chat_id, message_id)` | Stop a poll (returns final Poll) |
| `set_message_reaction(chat_id, message_id, reaction, ...)` | Add reaction |
| `pin_chat_message(chat_id, message_id, ...)` | Pin message |
| `unpin_chat_message(chat_id, message_id)` | Unpin message |
| `unpin_all_chat_messages(chat_id)` | Unpin all |

### Answering queries

| Method | Purpose |
|---|---|
| `answer_callback_query(callback_query_id, text, ...)` | Answer inline button press |
| `answer_inline_query(inline_query_id, results, ...)` | Answer inline query |
| `answer_pre_checkout_query(pre_checkout_query_id, ok, ...)` | Answer payment query |
| `answer_shipping_query(shipping_query_id, ok, ...)` | Answer shipping query |
| `answer_web_app_query(web_app_query_id, result)` | Answer web app query |

### Chat administration

| Method | Purpose |
|---|---|
| `get_chat(chat_id)` | Get chat info |
| `get_chat_administrators(chat_id)` | List admins |
| `get_chat_member(chat_id, user_id)` | Get member info |
| `get_chat_member_count(chat_id)` | Count members |
| `ban_chat_member(chat_id, user_id, ...)` | Ban user |
| `unban_chat_member(chat_id, user_id, ...)` | Unban user |
| `restrict_chat_member(chat_id, user_id, permissions, ...)` | Restrict permissions |
| `promote_chat_member(chat_id, user_id, ...)` | Promote to admin |
| `kick_chat_member(chat_id, user_id, ...)` | Alias for ban |
| `leave_chat(chat_id)` | Bot leaves chat |
| `approve_chat_join_request(chat_id, user_id)` | Approve join request |
| `decline_chat_join_request(chat_id, user_id)` | Decline join request |
| `create_chat_invite_link(chat_id, ...)` | Create invite link |
| `export_chat_invite_link(chat_id)` | Get primary invite link |
| `revoke_chat_invite_link(chat_id, invite_link)` | Revoke invite link |
| `set_chat_title(chat_id, title)` | Set chat title |
| `set_chat_description(chat_id, description)` | Set description |
| `set_chat_photo(chat_id, photo)` | Set chat photo |
| `delete_chat_photo(chat_id)` | Delete chat photo |
| `set_chat_permissions(chat_id, permissions)` | Set default permissions |
| `set_chat_sticker_set(chat_id, sticker_set_name)` | Set chat sticker set |
| `get_user_profile_photos(user_id, ...)` | Get user's profile photos |
| `get_user_chat_boosts(chat_id, user_id)` | Get user's boosts in chat |

### Bot settings

| Method | Purpose |
|---|---|
| `get_me()` | Get bot info (User object) |
| `set_my_commands(commands, ...)` | Set command list |
| `get_my_commands(...)` | Get command list |
| `delete_my_commands(...)` | Delete command list |
| `set_my_name(name, ...)` | Set bot name |
| `set_my_description(description, ...)` | Set bot description |
| `set_my_short_description(...)` | Set short description |
| `set_chat_menu_button(chat_id, menu_button)` | Set menu button |
| `get_chat_menu_button(chat_id)` | Get menu button |
| `set_my_default_administrator_rights(...)` | Set default admin rights |

### Files

| Method | Purpose |
|---|---|
| `get_file(file_id)` | Get File object (call `.download_to_drive()` on it) |
| `upload_sticker_file(user_id, sticker, sticker_format)` | Upload sticker file |

### Payments and Stars

| Method | Purpose |
|---|---|
| `create_invoice_link(title, description, payload, ...)` | Create shareable invoice link |
| `get_star_transactions(offset, limit)` | List Star transactions |
| `refund_star_payment(user_id, telegram_payment_charge_id)` | Refund Stars |
| `edit_user_star_subscription(user_id, ...)` | Edit Star subscription |

### Miscellaneous

| Method | Purpose |
|---|---|
| `get_updates(offset, limit, timeout, ...)` | Long poll (use Application instead) |
| `set_webhook(url, ...)` | Register webhook |
| `delete_webhook(...)` | Delete webhook |
| `get_webhook_info()` | Get webhook status |
| `set_passport_data_errors(user_id, errors)` | Report Passport validation errors |
| `set_game_score(user_id, score, ...)` | Set game score |
| `get_game_high_scores(user_id, ...)` | Get game high scores |
| `save_prepared_inline_message(user_id, result, ...)` | Prepare inline message for web app |
| `close()` | Switch from cloud to local Bot API server |
| `log_out()` | Log out from cloud Bot API |
| `verify_user(user_id, ...)` | Verify user on behalf of org |
| `verify_chat(chat_id, ...)` | Verify chat on behalf of org |

## `telegram.ext` package

### Application layer

```python
from telegram.ext import (
    Application,          # the central object
    ApplicationBuilder,   # builds Application via builder pattern
    Updater,              # manages polling/webhook internally (rarely used directly)
    ExtBot,               # Bot subclass with ext-layer features
    Defaults,             # global send parameter defaults
    BaseUpdateProcessor,  # base for custom update processors
    SimpleUpdateProcessor, # default sequential update processor
)
```

### Context

```python
from telegram.ext import (
    CallbackContext,    # injected into every callback
    ContextTypes,       # configure custom context types
)
```

### JobQueue

```python
from telegram.ext import (
    JobQueue,   # schedule jobs (requires [job-queue])
    Job,        # individual scheduled job
)

# JobQueue methods:
# .run_once(callback, when, chat_id, user_id, data, name)
# .run_repeating(callback, interval, first, chat_id, user_id, data, name)
# .run_daily(callback, time, days, chat_id, user_id, data, name)
# .run_monthly(callback, when, day, chat_id, user_id, data, name)
# .run_at(callback, when, chat_id, user_id, data, name)
# .get_jobs_by_name(name) -> tuple[Job, ...]
# .jobs() -> tuple[Job, ...]

# Job attributes:
# .chat_id, .user_id, .data, .name
# .schedule_removal() — cancel this job
```

### Handlers — complete list

```python
from telegram.ext import (
    BaseHandler,
    CommandHandler,
    MessageHandler,
    CallbackQueryHandler,
    InlineQueryHandler,
    ConversationHandler,
    TypeHandler,
    PrefixHandler,
    ChatMemberHandler,
    ChatJoinRequestHandler,
    ChatBoostHandler,
    BusinessConnectionHandler,
    BusinessMessagesDeletedHandler,
    MessageReactionHandler,
    PollHandler,
    PollAnswerHandler,
    PreCheckoutQueryHandler,
    ShippingQueryHandler,
    PaidMediaPurchasedHandler,
    ChosenInlineResultHandler,
    StringCommandHandler,    # for testing
    StringRegexHandler,      # for testing
    ApplicationHandlerStop,  # raise to stop handler group propagation
)
```

### Filters module

```python
from telegram.ext import filters

# All filter classes and instances live in this module:
# filters.TEXT, filters.PHOTO, filters.VIDEO, filters.AUDIO, filters.VOICE
# filters.COMMAND, filters.FORWARDED, filters.DOCUMENT
# filters.CONTACT, filters.LOCATION, filters.POLL, filters.DICE
# filters.GAME, filters.INVOICE, filters.SUCCESSFUL_PAYMENT
# filters.PASSPORT_DATA, filters.ANIMATION, filters.STICKER
# filters.ALL, filters.ATTACHMENT
# filters.ChatType.PRIVATE, .GROUP, .SUPERGROUP, .CHANNEL, .GROUPS
# filters.Regex(pattern)
# filters.Document.FileExtension(ext), .MimeType(mime)
# filters.StatusUpdate.NEW_CHAT_MEMBERS, .LEFT_CHAT_MEMBER, .WEB_APP_DATA, ...
# filters.FORWARDED
# filters.UpdateType.MESSAGE, .CALLBACK_QUERY, .INLINE_QUERY, ...

# Base classes for custom filters:
from telegram.ext.filters import MessageFilter, UpdateFilter
```

### Persistence

```python
from telegram.ext import (
    BasePersistence,      # ABC — implement for custom storage
    PicklePersistence,    # file-based (single file by default)
    DictPersistence,      # in-memory (testing only)
    PersistenceInput,     # configure which data types are persisted
)
```

### Arbitrary callback data

```python
from telegram.ext import (
    CallbackDataCache,      # internal cache; configure via ApplicationBuilder
    InvalidCallbackData,    # raised when cached entry was evicted
)
```

### Rate limiting

```python
from telegram.ext import (
    BaseRateLimiter,   # ABC — implement for custom throttling
    AIORateLimiter,    # built-in rate limiter (requires [rate-limiter])
)
```

## `telegram.constants` module

Important constants for avoiding magic strings:

```python
from telegram.constants import (
    ParseMode,          # .HTML, .MARKDOWN_V2, .MARKDOWN
    ChatType,           # .PRIVATE, .GROUP, .SUPERGROUP, .CHANNEL
    MessageEntityType,  # .BOLD, .ITALIC, .CODE, .URL, .MENTION, ...
    ChatMemberStatus,   # .ADMINISTRATOR, .MEMBER, .LEFT, .BANNED, ...
    BotCommandScopeType,
    MenuButtonType,
    FileSizeLimit,      # .FILESIZE_DOWNLOAD, .FILESIZE_UPLOAD, ...
    FloodLimit,         # .MESSAGES_PER_SECOND, .MESSAGES_PER_MINUTE_PER_GROUP
    MessageLimit,       # .MAX_TEXT_LENGTH (4096), .MAX_CAPTION_LENGTH (1024)
    InlineQueryResultsButton,
    PollLimit,          # .MIN_OPEN_PERIOD, .MAX_OPEN_PERIOD, ...
)
```

## `telegram.helpers` module

```python
from telegram.helpers import (
    create_deep_linked_url,  # generate t.me/?start= links
    escape_markdown,          # escape MarkdownV2 special characters
    mention_html,             # generate HTML mention link
    mention_markdown,         # generate Markdown mention link
)
```

## `telegram.error` module

```python
from telegram.error import (
    TelegramError,    # base class
    Forbidden,        # bot blocked by user, or lacks permission
    InvalidToken,     # bot token invalid/revoked
    NetworkError,     # network-level failure
    BadRequest,       # malformed request
    TimedOut,         # API response timeout
    ChatMigrated,     # group → supergroup (.new_chat_id attribute)
    RetryAfter,       # flood control (.retry_after attribute — seconds to wait)
    Conflict,         # two bot instances polling simultaneously
)
```

## Inline mode (`telegram.inline-tree.rst`)

```python
from telegram import (
    InlineQuery,
    ChosenInlineResult,
    InlineQueryResultsButton,
    PreparedInlineMessage,
    # Result types (21 total):
    InlineQueryResultArticle,
    InlineQueryResultPhoto,
    InlineQueryResultGif,
    InlineQueryResultMpeg4Gif,
    InlineQueryResultVideo,
    InlineQueryResultAudio,
    InlineQueryResultVoice,
    InlineQueryResultDocument,
    InlineQueryResultLocation,
    InlineQueryResultVenue,
    InlineQueryResultContact,
    InlineQueryResultGame,
    InlineQueryResultCachedAudio,
    InlineQueryResultCachedDocument,
    InlineQueryResultCachedGif,
    InlineQueryResultCachedMpeg4Gif,
    InlineQueryResultCachedPhoto,
    InlineQueryResultCachedSticker,
    InlineQueryResultCachedVideo,
    InlineQueryResultCachedVoice,
    # Content types:
    InputTextMessageContent,
    InputLocationMessageContent,
    InputVenueMessageContent,
    InputContactMessageContent,
    InputInvoiceMessageContent,
)
```

## Media types

```python
from telegram import (
    Animation,    # GIF
    Audio,        # audio file (music)
    Document,     # generic document
    InputFile,    # file-like object for uploading
    InputMedia,   # base for media group items
    InputMediaPhoto,
    InputMediaVideo,
    InputMediaDocument,
    InputMediaAudio,
    InputMediaAnimation,
    InputPaidMedia,         # paid media (v21)
    InputPaidMediaPhoto,
    InputPaidMediaVideo,
    PhotoSize,    # one resolution of a photo
    Sticker,
    StickerSet,
    InputSticker,
    Video,
    VideoNote,    # round video (circle)
    Voice,        # voice message
)
```

## Chat keyboard types

```python
from telegram import (
    InlineKeyboardButton,    # button with callback_data / url / web_app
    InlineKeyboardMarkup,    # keyboard attached to a message
    ReplyKeyboardMarkup,     # keyboard replacing the text input area
    ReplyKeyboardRemove,     # removes a ReplyKeyboard
    KeyboardButton,          # one button in a ReplyKeyboard
    KeyboardButtonPollType,  # request poll creation from user
    KeyboardButtonRequestChat,   # request user to select a chat
    KeyboardButtonRequestUsers,  # request user to select users
    ForceReply,              # force user to reply to bot message
    ReplyParameters,         # reply to a specific message
    WebAppInfo,              # for web_app= in buttons
)
```

## Bot info / settings types

```python
from telegram import (
    BotCommand,
    BotCommandScopeDefault,
    BotCommandScopeAllPrivateChats,
    BotCommandScopeAllGroupChats,
    BotCommandScopeAllChatAdministrators,
    BotCommandScopeChat,
    BotCommandScopeChatAdministrators,
    BotCommandScopeChatMember,
    MenuButtonWebApp,
    MenuButtonCommands,
    MenuButtonDefault,
    WebhookInfo,
    BotDescription,
    BotName,
    BotShortDescription,
)
```

## v21 new additions

Added in v20/v21 (not in v13):

```python
# Paid media
from telegram import (
    PaidMedia,
    PaidMediaPreview,
    PaidMediaPhoto,
    PaidMediaVideo,
    PaidMediaInfo,
    PaidMediaPurchased,
    InputPaidMediaPhoto,
    InputPaidMediaVideo,
)

# Gifts / Stars
from telegram import Gift, Gifts, StarTransaction, StarTransactions
from telegram import RevenueWithdrawalState, TransactionPartner, AffiliateInfo

# Reactions
from telegram import (
    ReactionType,
    ReactionTypeEmoji,
    ReactionTypeCustomEmoji,
    ReactionTypePaid,
    MessageReactionUpdated,
    MessageReactionCountUpdated,
)

# Message origin
from telegram import (
    MessageOrigin,
    MessageOriginUser,
    MessageOriginChat,
    MessageOriginChannel,
    MessageOriginHiddenUser,
)

# Business
from telegram import (
    BusinessConnection,
    BusinessIntro,
    BusinessLocation,
    BusinessOpeningHours,
    BusinessOpeningHoursInterval,
    BusinessMessagesDeleted,
)

# Forum topics
from telegram import (
    ForumTopic,
    ForumTopicCreated,
    ForumTopicClosed,
    ForumTopicEdited,
    ForumTopicReopened,
    GeneralForumTopicHidden,
    GeneralForumTopicUnhidden,
)
```

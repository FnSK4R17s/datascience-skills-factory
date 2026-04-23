# Class Reference Map

Sources: `telegram.rst`, `telegram.ext.rst`, `telegram.at-tree.rst`,
`telegram.inline-tree.rst`, `telegram.payments-tree.rst`,
`telegram.passport-tree.rst`, `telegram.games-tree.rst`,
`telegram.stickers-tree.rst`, `telegram.ext.handlers-tree.rst`,
`telegram.ext.persistence-tree.rst`, `telegram.ext.acd-tree.rst`,
`telegram.ext.rate-limiting-tree.rst`, `telegram_auxil.rst`.

## How to use this file

The scraped documentation consists mostly of Sphinx `autoclass` stubs — they
reference the library's Python docstrings but do not copy them. For full class
signatures, attributes, and method details, use one of:

1. `help(telegram.ext.Application)` in a Python REPL with PTB installed.
2. The installed package's `__doc__` attributes.
3. The official rendered docs at python-telegram-bot.readthedocs.io.

This file maps module structure so you know where each class lives.

## `telegram` package — top-level types

**Core objects:** `Update`, `Message`, `User`, `Chat`, `ChatFullInfo`,
`Bot`, `TelegramObject`.

**Media types:** `Animation`, `Audio`, `Document`, `InputFile`, `InputMedia*`,
`Photo`, `PhotoSize`, `Sticker`, `StickerSet`, `Video`, `VideoNote`, `Voice`.

**Keyboard types:** `InlineKeyboardButton`, `InlineKeyboardMarkup`,
`ReplyKeyboardMarkup`, `ReplyKeyboardRemove`, `KeyboardButton`,
`KeyboardButtonPollType`, `KeyboardButtonRequestChat`, `KeyboardButtonRequestUsers`,
`ForceReply`, `ReplyParameters`.

**Message components:** `MessageEntity`, `MessageOrigin*`, `LinkPreviewOptions`,
`TextQuote`, `ExternalReplyInfo`.

**Reactions:** `ReactionType`, `ReactionTypeEmoji`, `ReactionTypeCustomEmoji`,
`ReactionTypePaid`, `ReactionCount`, `MessageReactionUpdated`,
`MessageReactionCountUpdated`.

**Chat lifecycle:** `ChatInviteLink`, `ChatJoinRequest`, `ChatMember*`,
`ChatMemberUpdated`, `ChatPermissions`, `ChatAdministratorRights`.

**Business:** `BusinessConnection`, `BusinessIntro`, `BusinessLocation`,
`BusinessOpeningHours`, `BusinessOpeningHoursInterval`, `BusinessMessagesDeleted`.

**Other updates:** `Poll`, `PollAnswer`, `PollOption`, `InputPollOption`,
`Dice`, `Contact`, `Location`, `Venue`, `Story`, `ProximityAlertTriggered`.

**Bot settings:** `BotCommand`, `BotCommandScope*`, `BotDescription`, `BotName`,
`BotShortDescription`, `MenuButton*`, `WebAppInfo`, `WebAppData`, `WebhookInfo`.

**Paid media (v21):** `PaidMedia*`, `InputPaidMedia*`.

**Gifts / boosts:** `Gift`, `Gifts`, `ChatBoost*`, `UserChatBoosts`.

**Forum topics:** `ForumTopic`, `ForumTopic*`.

**Constants:** `telegram.constants` module — enums for `ParseMode`, `ChatType`,
`MessageEntityType`, `BotCommandScopeType`, `MenuButtonType`, etc.

**Errors:** `telegram.error` — `TelegramError`, `Forbidden`, `BadRequest`,
`TimedOut`, `NetworkError`, `RetryAfter`, `ChatMigrated`, `Conflict`,
`InvalidToken`.

**Helpers:** `telegram.helpers` — `create_deep_linked_url`, `escape_markdown`,
`mention_html`, `mention_markdown`.

**Request layer:** `telegram.request` — `BaseRequest`, `HTTPXRequest` (default
HTTP backend, wraps `httpx`). Do not use directly; customize via
`ApplicationBuilder().request(...)`.

## Inline mode (`telegram.inline-tree.rst`)

`InlineQuery`, `ChosenInlineResult`, `InlineQueryResult*` (21 result types),
`InputMessageContent*`, `InlineQueryResultsButton`, `PreparedInlineMessage`.

## Payments (`telegram.payments-tree.rst`)

`LabeledPrice`, `Invoice`, `PreCheckoutQuery`, `SuccessfulPayment`,
`ShippingAddress`, `ShippingOption`, `ShippingQuery`, `OrderInfo`,
`StarTransaction`, `StarTransactions`, `RefundedPayment`,
`RevenueWithdrawalState*`, `TransactionPartner*`, `AffiliateInfo`.

## Passport (`telegram.passport-tree.rst`)

`PassportData`, `EncryptedPassportElement`, `EncryptedCredentials`,
`PassportElementError*`, `Credentials`, `SecureData`, `SecureValue`,
`PersonalDetails`, `IdDocumentData`, `ResidentialAddress`, `PassportFile`,
`DataCredentials`, `FileCredentials`.

## Games (`telegram.games-tree.rst`)

`Game`, `GameHighScore`, `CallbackGame`.

## Stickers (`telegram.stickers-tree.rst`)

`Sticker`, `StickerSet`, `InputSticker`, `MaskPosition`, `Gift`, `Gifts`.

## `telegram.ext` package

**Application layer:** `Application`, `ApplicationBuilder`, `Updater`,
`ExtBot`, `Defaults`, `BaseUpdateProcessor`, `SimpleUpdateProcessor`.

**Context:** `CallbackContext`, `ContextTypes`.

**Job scheduling:** `JobQueue`, `Job`.

**Handlers (from `telegram.ext.handlers-tree.rst`):**
`BaseHandler`, `CommandHandler`, `MessageHandler`, `CallbackQueryHandler`,
`InlineQueryHandler`, `ConversationHandler`, `TypeHandler`, `PrefixHandler`,
`ChatMemberHandler`, `ChatJoinRequestHandler`, `ChatBoostHandler`,
`BusinessConnectionHandler`, `BusinessMessagesDeletedHandler`,
`MessageReactionHandler`, `PollHandler`, `PollAnswerHandler`,
`PreCheckoutQueryHandler`, `ShippingQueryHandler`, `PaidMediaPurchasedHandler`,
`StringCommandHandler`, `StringRegexHandler`, `ChosenInlineResultHandler`.
`ApplicationHandlerStop` — raise to stop handler group propagation.

**Filters:** `telegram.ext.filters` module — `filters.TEXT`, `filters.PHOTO`,
`filters.COMMAND`, `filters.Regex`, `filters.ChatType.*`, `filters.FORWARDED`,
`filters.StatusUpdate.*`, `MessageFilter` (base for custom filters).

**Persistence (from `telegram.ext.persistence-tree.rst`):**
`BasePersistence`, `PicklePersistence`, `DictPersistence`, `PersistenceInput`.

**Arbitrary callback data (from `telegram.ext.acd-tree.rst`):**
`CallbackDataCache`, `InvalidCallbackData`.

**Rate limiting (from `telegram.ext.rate-limiting-tree.rst`):**
`BaseRateLimiter`, `AIORateLimiter`.

## Autoclass stub count

The 336-file scrape contains approximately 243 `autoclass`-only stubs (one per
class). Their content defers entirely to Python docstrings. The tree files above
list every class by module; the actual docstrings are in the installed package.

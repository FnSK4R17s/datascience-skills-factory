# Telegram Passport

Sources: `telegram.passport-tree.rst`, `examples.passportbot.rst`, `examples.rst`.

## What Telegram Passport is

Telegram Passport is a unified authorization method for services requiring real
identity verification. Users upload documents once; bots receive encrypted
credential data. Requires an RSA key pair — the public key is registered with
BotFather, the private key stays with the bot.

Install extra: `pip install "python-telegram-bot[passport]"` (adds `cryptography`).
(Source: `examples.rst` — "Note: To use Telegram Passport, you must install PTB
via `pip install "python-telegram-bot[passport]"`")

## When to use

Use Passport only when you genuinely need government-issued ID verification (KYC,
ICO onboarding, etc.). For simpler "is this person an adult / real person" checks,
Phone Number verification or Payment flow is usually sufficient. Passport adds
significant implementation complexity and UX friction.

## How it works

1. Bot sends an HTML page with a Telegram Login Widget configured with the
   requested passport data types (e.g., `personal_details`, `passport`,
   `phone_number`).
2. User authorizes the request inside Telegram and sends encrypted data.
3. Bot receives a `Message` with `passport_data` field containing
   `EncryptedPassportElement` objects.
4. Bot decrypts with the private key to get plaintext credentials.

## Handler

```python
from telegram.ext import MessageHandler, filters

async def passport_handler(update, context):
    passport_data = update.message.passport_data
    # passport_data.credentials — EncryptedCredentials
    # Decrypt with your private key:
    credentials = passport_data.decrypted_credentials
    for element in passport_data.decrypted_data:
        print(element.type, element.data)  # e.g. "personal_details", PersonalDetails

app.add_handler(MessageHandler(filters.PASSPORT_DATA, passport_handler))
```

Decryption is handled by PTB's `EncryptedCredentials.decrypt()` and
`EncryptedPassportElement.decrypt()` when you set the bot's private key:

```python
app = (
    ApplicationBuilder()
    .token(TOKEN)
    .private_key(open("private.key", "rb").read())
    .build()
)
```

## Key classes (from `telegram.passport-tree.rst`)

| Class | Purpose |
|-------|---------|
| `PassportData` | Top-level container in the `Message` |
| `EncryptedPassportElement` | One document type (id, passport, phone, etc.) |
| `EncryptedCredentials` | Decryption keys for the elements |
| `PassportElementError*` | Error types for reporting validation failures |
| `PersonalDetails` | Decrypted personal info |
| `IdDocumentData` | Decrypted ID document fields |
| `ResidentialAddress` | Decrypted address data |
| `Credentials`, `SecureData`, `SecureValue` | Internal decryption data model |

## Reporting errors to the user

If document validation fails (e.g., photo is unreadable), call
`set_passport_data_errors` to tell Telegram which fields are invalid:

```python
from telegram import PassportElementErrorDataField

await context.bot.set_passport_data_errors(
    user_id=update.effective_user.id,
    errors=[
        PassportElementErrorDataField(
            type="personal_details",
            field_name="first_name",
            data_hash="...",
            message="Name does not match document",
        )
    ],
)
```

## Niche warning

Telegram Passport sees very limited real-world use. Most bots do not need it.
The implementation requires a correctly configured HTML page and RSA key
management — see the official Telegram Passport guide and `examples.passportbot.rst`
for a working reference.

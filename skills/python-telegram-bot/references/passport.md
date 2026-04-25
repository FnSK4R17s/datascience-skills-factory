# Telegram Passport

Sources: `telegram.passport-tree.rst`, `examples.passportbot.rst`, `examples.rst`.

## What Telegram Passport is

Telegram Passport is a unified authorization method for services requiring real
identity verification. Users upload documents once to Telegram; bots receive
encrypted credential data. Requires an RSA key pair — the public key is
registered with BotFather, the private key stays with your bot.

Install extra: `pip install "python-telegram-bot[passport]"` (adds `cryptography`).
(Source: `examples.rst` — "Note: To use Telegram Passport, you must install PTB
via `pip install "python-telegram-bot[passport]"`")

## When to use Passport

Use Passport only when you genuinely need government-issued ID verification:
- KYC (Know Your Customer) for financial services
- ICO onboarding
- Age-gated services requiring legal verification

For simpler verification needs, consider:
- Phone number verification (easier, PTB provides `request_contact=True` keyboard button)
- Payment flow (Telegram handles identity for payments)

Passport adds significant UX friction and implementation complexity. Most bots
do not need it.

## How Telegram Passport works

1. Bot's public RSA key is registered with BotFather.
2. Bot serves an HTML page with a Telegram Login Widget configured with the
   requested data types.
3. User opens the HTML page, authorizes the request inside Telegram.
4. Telegram sends an update with a `Message` containing `passport_data`.
5. Bot decrypts the data using the private RSA key.

## Generating the RSA key pair

```bash
# Generate 2048-bit RSA key pair (minimum; 4096 recommended)
openssl genrsa -out private.key 2048
openssl rsa -in private.key -pubout -out public.key
```

Register `public.key` with BotFather via `/setpublickey`.
Keep `private.key` secret — never commit it to source control.

## ApplicationBuilder — loading the private key

```python
app = (
    ApplicationBuilder()
    .token(TOKEN)
    .private_key(open("private.key", "rb").read())
    .build()
)
```

## Handling passport_data updates

```python
from telegram.ext import MessageHandler, filters

async def passport_handler(update, context):
    passport_data = update.message.passport_data
    if passport_data is None:
        return

    # Decrypted credentials (decrypted using private key automatically by PTB)
    credentials = passport_data.decrypted_credentials
    secure_data = credentials.secure_data

    # Iterate over each passport element
    for element in passport_data.decrypted_data:
        print(f"Element type: {element.type}")

        if element.type == "personal_details":
            details = element.data   # PersonalDetails object
            print(f"Name: {details.first_name} {details.last_name}")
            print(f"DOB: {details.birth_date}")
            print(f"Nationality: {details.nationality}")

        elif element.type == "passport":
            id_doc = element.data   # IdDocumentData
            print(f"Doc number: {id_doc.document_no}")
            print(f"Expiry: {id_doc.expiry_date}")

        elif element.type == "phone_number":
            print(f"Phone: {element.phone_number}")

        elif element.type == "email":
            print(f"Email: {element.email}")

        # Download document files
        if element.files:
            for file in element.files:
                tg_file = await file.get_file()
                await tg_file.download_to_drive(f"doc_{element.type}_{file.file_unique_id}.jpg")

app.add_handler(MessageHandler(filters.PASSPORT_DATA, passport_handler))
```

PTB automatically decrypts `passport_data` when `private_key` is configured
via `ApplicationBuilder`. Access via `element.data` for structured data and
`element.files` for document files.

## HTML page for Telegram Login Widget

The HTML page initiates the Passport flow. Users open it in a browser; it
opens Telegram to authorize and send data.

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Passport Verification</title>
    <script src="https://telegram.org/js/telegram-widget.js?22"
            data-telegram-login="YOUR_BOT_USERNAME"
            data-size="large"
            data-auth-url="https://yourdomain.com/passport-callback">
    </script>
</head>
<body>
    <h1>Identity Verification</h1>
    <p>Click the button above to verify your identity with Telegram Passport.</p>

    <script type="text/javascript">
        Telegram.Passport.createAuthButton('passport-btn', {
            bot_id: YOUR_BOT_ID,
            scope: {
                data: [
                    { type: 'personal_details' },
                    { type: 'phone_number' },
                    { type: 'email' }
                ],
                v: 1
            },
            public_key: 'YOUR_PUBLIC_KEY_PEM_CONTENT',
            nonce: 'RANDOM_NONCE_32_CHARS',
            callback_url: 'https://yourdomain.com/passport-callback'
        });
    </script>
</body>
</html>
```

(Source: `examples.passportbot.rst` — HTML page with full widget configuration)

## Passport element types

| Type | Contents |
|---|---|
| `personal_details` | `IdDocumentData` — name, DOB, nationality |
| `passport` | `IdDocumentData` + photos of passport |
| `driver_license` | `IdDocumentData` + photos |
| `identity_card` | `IdDocumentData` + photos |
| `internal_passport` | `IdDocumentData` + photos |
| `address` | `ResidentialAddress` |
| `utility_bill` | Photos of a utility bill |
| `bank_statement` | Photos of a bank statement |
| `rental_agreement` | Photos |
| `passport_registration` | Photos |
| `temporary_registration` | Photos |
| `phone_number` | Phone number string |
| `email` | Email address string |

## Reporting validation errors to the user

If document validation fails (expired passport, unreadable photo, etc.), call
`set_passport_data_errors` to tell Telegram which fields are invalid. Telegram
will prompt the user to re-upload the rejected documents.

```python
from telegram import (
    PassportElementErrorDataField,
    PassportElementErrorFrontSide,
    PassportElementErrorFile,
)

async def report_passport_errors(update, context):
    errors = []

    # Error in a specific data field
    errors.append(PassportElementErrorDataField(
        type="personal_details",
        field_name="first_name",
        data_hash="...",    # hash of the erroneous data
        message="First name does not match document",
    ))

    # Error in a photo file
    errors.append(PassportElementErrorFrontSide(
        type="passport",
        file_hash="...",    # hash of the erroneous file
        message="Front side photo is blurry",
    ))

    await context.bot.set_passport_data_errors(
        user_id=update.effective_user.id,
        errors=errors,
    )
    await update.message.reply_text(
        "Your documents had issues. Please re-upload them in Telegram."
    )
```

## Key classes

| Class | Purpose |
|---|---|
| `PassportData` | Top-level container in `Message.passport_data` |
| `EncryptedPassportElement` | One document type (id, passport, phone, etc.) |
| `EncryptedCredentials` | Decryption keys for the elements |
| `PersonalDetails` | Decrypted personal info (name, DOB, etc.) |
| `IdDocumentData` | Decrypted ID document fields (document_no, expiry_date) |
| `ResidentialAddress` | Decrypted address data |
| `PassportFile` | One uploaded file — call `get_file()` to download |
| `PassportElementErrorDataField` | Error in a specific data field |
| `PassportElementErrorFrontSide` | Error in front side photo |
| `PassportElementErrorReverseSide` | Error in reverse side photo |
| `PassportElementErrorSelfie` | Error in selfie |
| `PassportElementErrorFile` | Error in a document file |
| `PassportElementErrorFiles` | Error in a set of files |
| `PassportElementErrorTranslationFile` | Error in translation file |
| `PassportElementErrorUnspecified` | Generic error |

(Source: `telegram.passport-tree.rst`)

## Security notes

- Never expose your private RSA key. Load it from a file or secret manager, not
  from environment variables or source code.
- Validate the nonce in the callback to prevent replay attacks.
- Passport data is end-to-end encrypted — Telegram cannot read it.
- Store decrypted data in compliance with your jurisdiction's data protection laws
  (GDPR, etc.). Passport contains highly sensitive PII.
- Delete document files after validation; do not store them permanently unless
  legally required to do so.

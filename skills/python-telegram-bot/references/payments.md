# Payments and Telegram Stars

Sources: `telegram.payments-tree.rst`, `examples.paymentbot.rst`,
`telegram.labeledprice.rst`, `telegram.invoice.rst`,
`telegram.successfulpayment.rst`, `telegram.precheckoutquery.rst`,
`telegram.ext.precheckoutqueryhandler.rst`,
`telegram.ext.shippingqueryhandler.rst`, `inclusions__bot_methods.rst`.

## Overview

PTB supports the Telegram Payments API (Bot API). Bots can:
- Send invoices for digital or physical goods.
- Receive pre-checkout confirmation (validate before payment clears).
- Process successful payments.
- Issue refunds (Telegram Stars only).

For real-money payments, configure a payment provider token via BotFather
(`/mypayments`). Supported providers include Stripe, YooMoney, Sberbank, and
others — see Telegram's Payments documentation for the current list.

For Telegram Stars (in-app currency), no provider token is needed.

## Payment flow (sequence)

```
Bot: send_invoice()
         ↓
User: taps "Pay"
         ↓
Telegram: sends PreCheckoutQuery to bot
         ↓
Bot: MUST answer within 10 seconds
         ├─ answer_pre_checkout_query(ok=True)  → Telegram processes payment
         └─ answer_pre_checkout_query(ok=False, error_message="...") → cancelled
              ↓ (if ok=True)
Telegram: sends Message with successful_payment field
         ↓
Bot: fulfil the order
```

## Sending an invoice

```python
from telegram import LabeledPrice
from telegram.ext import CommandHandler, ContextTypes
from telegram import Update

PROVIDER_TOKEN = "your-stripe-provider-token"   # from BotFather /mypayments


async def send_invoice_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send an invoice for a product."""
    chat_id = update.effective_chat.id

    await context.bot.send_invoice(
        chat_id=chat_id,
        title="Premium Subscription",
        description="Get access to all premium features for one month.",
        payload="premium-monthly-sub",    # internal identifier, not shown to user
        provider_token=PROVIDER_TOKEN,    # omit for Telegram Stars
        currency="USD",
        prices=[
            LabeledPrice(label="Subscription", amount=999),    # $9.99 (cents)
            LabeledPrice(label="Tax",          amount=100),    # $1.00
        ],
        # Optional fields:
        photo_url="https://example.com/product.jpg",
        photo_width=640,
        photo_height=480,
        need_name=False,
        need_phone_number=False,
        need_email=False,
        need_shipping_address=False,
        is_flexible=False,              # True if price depends on shipping option
        protect_content=True,           # prevent forwarding the invoice
    )
```

`amount` is in the smallest currency unit:
- USD/EUR/GBP: cents (100 = $1.00)
- JPY/KRW: whole units (no subdivisions)
- Telegram Stars: whole stars (no subdivisions)

## Handling PreCheckoutQuery

The bot **must** respond within 10 seconds or the payment is cancelled.

```python
from telegram.ext import PreCheckoutQueryHandler

async def pre_checkout_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.pre_checkout_query

    # Validate the payload and check stock/availability
    if query.invoice_payload != "premium-monthly-sub":
        await query.answer(ok=False, error_message="Unknown product.")
        return

    # Check if the user already has this subscription
    if await user_already_subscribed(query.from_user.id):
        await query.answer(ok=False, error_message="You already have an active subscription.")
        return

    # All good — approve
    await query.answer(ok=True)


app.add_handler(PreCheckoutQueryHandler(pre_checkout_handler))
```

`query.from_user` — the user making the payment
`query.invoice_payload` — the `payload` you set in `send_invoice`
`query.currency` — currency code
`query.total_amount` — total amount in smallest unit
`query.order_info` — `OrderInfo` object with name, phone, email, shipping address

## Handling successful payment

```python
from telegram.ext import MessageHandler, filters

async def successful_payment_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    payment = update.message.successful_payment

    # Fulfil the order
    await fulfil_subscription(
        user_id=update.effective_user.id,
        charge_id=payment.telegram_payment_charge_id,  # unique charge ID from Telegram
        provider_charge_id=payment.provider_payment_charge_id,  # from payment provider
        currency=payment.currency,
        total_amount=payment.total_amount,
    )

    await update.message.reply_text(
        "Thank you for your purchase! Your premium subscription is now active."
    )


app.add_handler(MessageHandler(filters.SUCCESSFUL_PAYMENT, successful_payment_handler))
```

`payment.telegram_payment_charge_id` — Telegram's unique payment ID (use for refunds)
`payment.provider_payment_charge_id` — provider's reference (Stripe charge ID, etc.)
`payment.invoice_payload` — the `payload` from your `send_invoice` call

## Complete payment bot

```python
import logging
from telegram import LabeledPrice, Update
from telegram.ext import (
    Application, CommandHandler, MessageHandler, PreCheckoutQueryHandler,
    ContextTypes, filters,
)

logging.basicConfig(level=logging.INFO)
TOKEN = "YOUR_BOT_TOKEN"
PAYMENT_PROVIDER_TOKEN = "your-provider-token"


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "Use /buy to purchase a premium membership.\n"
        "Use /stars to pay with Telegram Stars."
    )


async def buy(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await context.bot.send_invoice(
        chat_id=update.effective_chat.id,
        title="Premium Membership",
        description="1 month of premium access",
        payload="premium-1month",
        provider_token=PAYMENT_PROVIDER_TOKEN,
        currency="USD",
        prices=[LabeledPrice("Premium Membership", 500)],  # $5.00
    )


async def stars_purchase(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """No provider token needed for Stars."""
    await context.bot.send_invoice(
        chat_id=update.effective_chat.id,
        title="Bonus Pack",
        description="100 bonus points",
        payload="bonus-100",
        currency="XTR",   # Telegram Stars
        prices=[LabeledPrice("Bonus Pack", 25)],  # 25 stars
    )


async def precheckout(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.pre_checkout_query
    valid_payloads = {"premium-1month", "bonus-100"}
    if query.invoice_payload not in valid_payloads:
        await query.answer(ok=False, error_message="Invalid order.")
    else:
        await query.answer(ok=True)


async def successful_payment(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    payment = update.message.successful_payment
    payload = payment.invoice_payload

    if payload == "premium-1month":
        await update.message.reply_text("Premium membership activated!")
    elif payload == "bonus-100":
        await update.message.reply_text("100 bonus points added!")

    # Store the charge ID for potential refunds
    context.user_data.setdefault("charges", []).append(
        payment.telegram_payment_charge_id
    )


def main() -> None:
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("buy", buy))
    app.add_handler(CommandHandler("stars", stars_purchase))
    app.add_handler(PreCheckoutQueryHandler(precheckout))
    app.add_handler(MessageHandler(filters.SUCCESSFUL_PAYMENT, successful_payment))
    app.run_polling()


if __name__ == "__main__":
    main()
```

(Source: `examples.paymentbot.rst`)

## Shipping queries (physical goods)

For products that require a physical shipping address:

```python
from telegram import ShippingOption, LabeledPrice
from telegram.ext import ShippingQueryHandler

async def send_physical_invoice(update, context):
    await context.bot.send_invoice(
        chat_id=update.effective_chat.id,
        title="T-Shirt",
        description="Python developer T-shirt, size L",
        payload="tshirt-L",
        provider_token=PAYMENT_PROVIDER_TOKEN,
        currency="USD",
        prices=[LabeledPrice("T-Shirt", 2500)],    # $25.00
        need_shipping_address=True,
        is_flexible=True,    # price can vary based on shipping option
    )


async def shipping_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.shipping_query

    # Determine options based on the shipping address
    country = query.shipping_address.country_code

    if country == "US":
        options = [
            ShippingOption(
                id="standard",
                title="Standard (5-7 days)",
                prices=[LabeledPrice("Shipping", 500)],   # $5.00
            ),
            ShippingOption(
                id="express",
                title="Express (2 days)",
                prices=[LabeledPrice("Shipping", 1500)],  # $15.00
            ),
        ]
        await query.answer(ok=True, shipping_options=options)
    else:
        await query.answer(
            ok=False,
            error_message="Sorry, we only ship to the US currently."
        )


app.add_handler(ShippingQueryHandler(shipping_handler))
```

## Telegram Stars (XTR) — digital goods

Stars are Telegram's in-app currency. No payment provider token required.
Used for digital goods only (digital services, virtual items, content access).

```python
# Send invoice for Stars
await context.bot.send_invoice(
    chat_id=update.effective_chat.id,
    title="Unlock Feature",
    description="Unlock the advanced analytics dashboard",
    payload="feature-analytics",
    currency="XTR",                          # Telegram Stars
    prices=[LabeledPrice("Feature", 50)],   # 50 stars
    # No provider_token needed
)
```

### Refunding Stars

```python
async def refund_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Refund the most recent Stars purchase."""
    charges = context.user_data.get("charges", [])
    if not charges:
        await update.message.reply_text("No purchases found.")
        return

    charge_id = charges[-1]   # telegram_payment_charge_id
    try:
        await context.bot.refund_star_payment(
            user_id=update.effective_user.id,
            telegram_payment_charge_id=charge_id,
        )
        await update.message.reply_text("Refund issued successfully.")
    except Exception as e:
        await update.message.reply_text(f"Refund failed: {e}")
```

### Checking Star transaction history

```python
async def check_transactions(update, context):
    transactions = await context.bot.get_star_transactions(
        offset=0,      # start from the beginning
        limit=10,      # up to 100
    )
    for tx in transactions.transactions:
        print(f"Amount: {tx.amount} stars, date: {tx.date}, source: {tx.source}")
```

## Creating shareable invoice links

```python
link = await context.bot.create_invoice_link(
    title="Premium Access",
    description="One month premium",
    payload="premium-1month",
    provider_token=PAYMENT_PROVIDER_TOKEN,
    currency="USD",
    prices=[LabeledPrice("Premium", 999)],
)
await update.message.reply_text(f"Pay here: {link}")
```

## Key data model

| Class | Key fields |
|---|---|
| `LabeledPrice` | `label` (str), `amount` (int, smallest currency unit) |
| `Invoice` | `title`, `description`, `currency`, `total_amount` — sent in the message |
| `PreCheckoutQuery` | `id`, `from_user`, `currency`, `total_amount`, `invoice_payload`, `order_info` |
| `SuccessfulPayment` | `currency`, `total_amount`, `invoice_payload`, `telegram_payment_charge_id`, `provider_payment_charge_id` |
| `ShippingAddress` | `country_code`, `state`, `city`, `street_line1/2`, `post_code` |
| `ShippingOption` | `id`, `title`, `prices` (list of LabeledPrice) |
| `OrderInfo` | `name`, `phone_number`, `email`, `shipping_address` |
| `StarTransaction` | `id`, `amount`, `date`, `source`, `receiver` |
| `RefundedPayment` | `currency`, `total_amount`, `invoice_payload`, `telegram_payment_charge_id` |

(Source: `telegram.payments-tree.rst`)

# Payments and Telegram Stars

Sources: `telegram.payments-tree.rst`, `examples.paymentbot.rst`,
`telegram.labeledprice.rst`, `telegram.invoice.rst`,
`telegram.successfulpayment.rst`, `telegram.precheckoutquery.rst`,
`telegram.ext.precheckoutqueryhandler.rst`,
`telegram.ext.shippingqueryhandler.rst`, `inclusions__bot_methods.rst`.

## Overview

PTB supports the Telegram Payments API. Bots can send invoices, receive
pre-checkout confirmation, and process successful payments. Configure a payment
provider token via BotFather before use.
(Source: `examples.paymentbot.rst`)

## Sending an invoice

```python
from telegram import LabeledPrice

await context.bot.send_invoice(
    chat_id=update.effective_chat.id,
    title="Product Name",
    description="A detailed description of what the user is buying.",
    payload="unique-payload-string",   # internal identifier, not shown to user
    currency="USD",
    prices=[
        LabeledPrice(label="Item", amount=500),     # 500 = $5.00 (cents)
        LabeledPrice(label="Shipping", amount=100),  # $1.00
    ],
    # provider_token="PROVIDER_TOKEN",  # omit for Telegram Stars (XTR)
)
```

`amount` is in the smallest currency unit (cents for USD, pence for GBP, etc.).
For Telegram Stars (currency `XTR`), amounts are whole stars — no provider token.

## Payment flow

1. Bot sends invoice via `send_invoice`.
2. User taps "Pay" — Telegram sends a `PreCheckoutQuery` update.
3. Bot **must** answer within 10 seconds: `answer_pre_checkout_query(ok=True)` to
   approve or `answer_pre_checkout_query(ok=False, error_message="Reason")` to
   reject.
4. After approval, Telegram processes payment and sends a `Message` with
   `successful_payment` field.

```python
from telegram.ext import PreCheckoutQueryHandler, MessageHandler, filters

async def pre_checkout(update, context):
    query = update.pre_checkout_query
    # Validate payload, check stock, etc.
    if query.invoice_payload != "expected-payload":
        await query.answer(ok=False, error_message="Invalid order.")
        return
    await query.answer(ok=True)

async def successful_payment(update, context):
    payment = update.message.successful_payment
    # payment.total_amount, payment.currency, payment.telegram_payment_charge_id
    await update.message.reply_text("Thank you for your payment!")

app.add_handler(PreCheckoutQueryHandler(pre_checkout))
app.add_handler(MessageHandler(filters.SUCCESSFUL_PAYMENT, successful_payment))
```

## Shipping queries (optional)

If the product requires physical shipping, set `need_shipping_address=True` in
`send_invoice` and handle `ShippingQuery`:

```python
from telegram.ext import ShippingQueryHandler
from telegram import ShippingOption, LabeledPrice

async def shipping_callback(update, context):
    query = update.shipping_query
    options = [
        ShippingOption("fast", "Fast Shipping", [LabeledPrice("Fast", 300)]),
        ShippingOption("slow", "Standard Shipping", [LabeledPrice("Standard", 100)]),
    ]
    await query.answer(ok=True, shipping_options=options)

app.add_handler(ShippingQueryHandler(shipping_callback))
```

## Telegram Stars (XTR)

For digital goods / services billed in Telegram Stars (no fiat):

```python
await context.bot.send_invoice(
    chat_id=update.effective_chat.id,
    title="Premium Feature",
    description="Unlocks feature X",
    payload="premium-unlock",
    currency="XTR",        # Telegram Stars
    prices=[LabeledPrice(label="Price", amount=50)],  # 50 stars
    # No provider_token needed
)
```

Refund Stars via `Bot.refund_star_payment(user_id, telegram_payment_charge_id)`.

## Key classes (from `telegram.payments-tree.rst`)

| Class | Purpose |
|-------|---------|
| `LabeledPrice` | One line item with label + amount |
| `Invoice` | Sent to user; describes what they're paying for |
| `PreCheckoutQuery` | Bot must answer within 10 seconds |
| `SuccessfulPayment` | Attached to message after payment clears |
| `ShippingAddress` | Physical address provided by user |
| `ShippingOption` | Shipping method with price |
| `OrderInfo` | Contact info collected during checkout |
| `StarTransaction` / `StarTransactions` | Star payment ledger entries |
| `RefundedPayment` | Refunded payment details |
| `TransactionPartner*` | Who sent/received Stars in a transaction |

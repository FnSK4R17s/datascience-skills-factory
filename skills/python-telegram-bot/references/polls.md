# Polls

Sources: `examples.pollbot.rst`, `telegram.poll.rst`, `telegram.pollanswer.rst`,
`telegram.polloption.rst`, `telegram.inputpolloption.rst`,
`telegram.ext.pollhandler.rst`, `telegram.ext.pollanswerhandler.rst`,
`inclusions__bot_methods.rst`.

## Sending a poll

```python
from telegram import InputPollOption

await context.bot.send_poll(
    chat_id=update.effective_chat.id,
    question="What is your favourite programming language?",
    options=[
        InputPollOption("Python"),
        InputPollOption("JavaScript"),
        InputPollOption("Rust"),
    ],
    is_anonymous=True,    # default; set False to see who voted
    allows_multiple_answers=False,
)
```

For a quiz-style poll with one correct answer:

```python
await context.bot.send_poll(
    chat_id=update.effective_chat.id,
    question="What year was Python created?",
    options=[
        InputPollOption("1989"),
        InputPollOption("1991"),
        InputPollOption("1995"),
    ],
    type="quiz",
    correct_option_id=1,       # 0-indexed; "1991" is index 1
    explanation="Python was created in 1991 by Guido van Rossum.",
    is_anonymous=True,
)
```

## Handling poll updates

`PollHandler` fires when a non-anonymous poll is updated (votes change):

```python
from telegram.ext import PollHandler, PollAnswerHandler

async def poll_update(update, context):
    poll = update.poll
    # poll.options is a list of PollOption with .text and .voter_count
    for option in poll.options:
        print(f"{option.text}: {option.voter_count} votes")

async def poll_answer(update, context):
    answer = update.poll_answer
    # answer.user, answer.option_ids (list of chosen indices)
    print(f"User {answer.user.id} chose options {answer.option_ids}")

app.add_handler(PollHandler(poll_update))
app.add_handler(PollAnswerHandler(poll_answer))
```

`PollAnswerHandler` fires when a user answers a non-anonymous poll. For anonymous
polls, individual answers are not sent to the bot — only aggregate counts via
`PollHandler`.

## Stopping a poll

```python
stopped_poll = await context.bot.stop_poll(
    chat_id=chat_id,
    message_id=poll_message_id,
)
# stopped_poll is a Poll object with final vote counts
```

## Keyboard button to request a poll

Use `KeyboardButtonPollType` to ask a user to create and share a poll:

```python
from telegram import KeyboardButton, KeyboardButtonPollType, ReplyKeyboardMarkup

button = KeyboardButton(
    "Share a poll",
    request_poll=KeyboardButtonPollType(type="poll"),   # or type="quiz"
)
markup = ReplyKeyboardMarkup([[button]], one_time_keyboard=True)
await update.message.reply_text("Create and share a poll:", reply_markup=markup)
```

When the user sends a poll via this button, the bot receives a message with
`message.poll` set.

## Key data model

| Class | Key fields |
|-------|-----------|
| `Poll` | `id`, `question`, `options`, `total_voter_count`, `is_closed`, `type` |
| `PollOption` | `text`, `voter_count` |
| `InputPollOption` | `text` — used when sending polls |
| `PollAnswer` | `poll_id`, `user`, `option_ids` |

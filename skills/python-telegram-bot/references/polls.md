# Polls

Sources: `examples.pollbot.rst`, `telegram.poll.rst`, `telegram.pollanswer.rst`,
`telegram.polloption.rst`, `telegram.inputpolloption.rst`,
`telegram.ext.pollhandler.rst`, `telegram.ext.pollanswerhandler.rst`,
`inclusions__bot_methods.rst`.

## Sending a regular poll

```python
from telegram import InputPollOption, Update
from telegram.ext import ContextTypes

async def send_poll(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    message = await context.bot.send_poll(
        chat_id=update.effective_chat.id,
        question="What is your favourite programming language?",
        options=[
            InputPollOption("Python"),
            InputPollOption("JavaScript"),
            InputPollOption("Rust"),
            InputPollOption("Go"),
        ],
        is_anonymous=True,             # default; set False to see who voted
        allows_multiple_answers=False, # allow choosing multiple options
        open_period=600,               # auto-close after 600 seconds (optional)
        # close_date=datetime,         # alternative: specific close datetime
    )
    # Save the message.poll.id and message.message_id for later
    context.bot_data[message.poll.id] = {
        "chat_id": update.effective_chat.id,
        "message_id": message.message_id,
    }
```

## Sending a quiz poll (one correct answer)

Quiz polls show the correct answer explanation after the user votes.

```python
async def send_quiz(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await context.bot.send_poll(
        chat_id=update.effective_chat.id,
        question="In what year was Python first released?",
        options=[
            InputPollOption("1989"),
            InputPollOption("1991"),
            InputPollOption("1994"),
            InputPollOption("2000"),
        ],
        type="quiz",                  # "quiz" for quiz polls, "regular" for normal
        correct_option_id=1,          # 0-indexed; index 1 = "1991"
        explanation="Python was created by Guido van Rossum and first released in 1991.",
        explanation_parse_mode="HTML",
        is_anonymous=True,
        open_period=300,              # 5 minutes to answer
    )
```

## Handling poll updates (vote count changes)

`PollHandler` fires when a non-anonymous poll's vote counts change. It receives
the entire `Poll` object with updated vote counts.

```python
from telegram.ext import PollHandler

async def poll_update_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    poll = update.poll
    print(f"Poll '{poll.question}' updated:")
    for option in poll.options:
        bar = "█" * option.voter_count + "░" * (poll.total_voter_count - option.voter_count)
        print(f"  {option.text}: {option.voter_count} votes | {bar}")
    if poll.is_closed:
        print("Poll closed.")


app.add_handler(PollHandler(poll_update_handler))
```

`PollHandler` does NOT fire for anonymous polls — Telegram does not send
individual vote updates for anonymous polls, only aggregate counts when the
poll is closed or stopped.

## Handling individual answers (non-anonymous polls)

`PollAnswerHandler` fires when a specific user votes in a non-anonymous poll
(`is_anonymous=False`). It fires once per user, per answer (including changing
the vote).

```python
from telegram.ext import PollAnswerHandler

async def poll_answer_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    answer = update.poll_answer
    user = answer.user             # the user who voted
    poll_id = answer.poll_id       # the poll's ID
    chosen = answer.option_ids     # list of chosen option indices

    # Retrieve the options from our stored data
    poll_data = context.bot_data.get(poll_id, {})
    options = poll_data.get("options", [])

    choices = [options[i] for i in chosen if i < len(options)]
    print(f"User {user.full_name} voted for: {', '.join(choices)}")

    # Update leaderboard, award points, etc.
    if 1 in chosen:  # index 1 is the correct answer
        context.user_data.setdefault("quiz_score", 0)
        context.user_data["quiz_score"] += 1


app.add_handler(PollAnswerHandler(poll_answer_handler))
```

## Stopping a poll

```python
async def stop_poll_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not context.args:
        await update.message.reply_text("Usage: /stoppoll <message_id>")
        return

    message_id = int(context.args[0])
    stopped_poll = await context.bot.stop_poll(
        chat_id=update.effective_chat.id,
        message_id=message_id,
    )
    # stopped_poll is a Poll object with the final vote counts
    total = stopped_poll.total_voter_count
    results = "\n".join(
        f"{opt.text}: {opt.voter_count} ({opt.voter_count*100//total if total else 0}%)"
        for opt in stopped_poll.options
    )
    await update.message.reply_text(f"Poll closed! Final results:\n{results}")
```

## Complete quiz bot example

```python
import logging
from telegram import Update, InputPollOption
from telegram.ext import (
    Application, CommandHandler, PollHandler, PollAnswerHandler, ContextTypes,
)

logging.basicConfig(level=logging.INFO)
TOKEN = "YOUR_BOT_TOKEN"

QUIZ_DATA = [
    {
        "question": "What is the capital of France?",
        "options": ["London", "Paris", "Berlin", "Madrid"],
        "correct": 1,
        "explanation": "Paris is the capital of France.",
    },
    {
        "question": "Which planet is closest to the Sun?",
        "options": ["Venus", "Earth", "Mercury", "Mars"],
        "correct": 2,
        "explanation": "Mercury is the closest planet to the Sun.",
    },
]


async def start_quiz(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    question_data = QUIZ_DATA[0]   # simplistic: just send first question
    msg = await context.bot.send_poll(
        chat_id=update.effective_chat.id,
        question=question_data["question"],
        options=[InputPollOption(o) for o in question_data["options"]],
        type="quiz",
        correct_option_id=question_data["correct"],
        explanation=question_data["explanation"],
        is_anonymous=False,   # must be False to track individual answers
        open_period=60,
    )
    # Store poll info for tracking
    context.bot_data[msg.poll.id] = {
        "chat_id": update.effective_chat.id,
        "message_id": msg.message_id,
        "correct": question_data["correct"],
        "options": question_data["options"],
        "voters": {},
    }
    await update.message.reply_text("Quiz started! You have 60 seconds.")


async def receive_poll_answer(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    answer = update.poll_answer
    poll_data = context.bot_data.get(answer.poll_id)
    if not poll_data:
        return

    user = answer.user
    chosen = answer.option_ids
    is_correct = poll_data["correct"] in chosen

    poll_data["voters"][user.id] = {
        "name": user.full_name,
        "correct": is_correct,
        "chosen": [poll_data["options"][i] for i in chosen],
    }

    # Update user score
    if is_correct:
        context.user_data.setdefault("score", 0)
        context.user_data["score"] += 1


async def show_score(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    score = context.user_data.get("score", 0)
    await update.message.reply_text(f"Your score: {score}")


def main() -> None:
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("quiz", start_quiz))
    app.add_handler(CommandHandler("score", show_score))
    app.add_handler(PollAnswerHandler(receive_poll_answer))
    app.run_polling()


if __name__ == "__main__":
    main()
```

(Source: `examples.pollbot.rst`)

## Keyboard button to request a poll from the user

Use `KeyboardButtonPollType` to prompt the user to create and share a poll:

```python
from telegram import KeyboardButton, KeyboardButtonPollType, ReplyKeyboardMarkup

async def request_poll(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    button = KeyboardButton(
        "Share a poll",
        request_poll=KeyboardButtonPollType(type="poll"),   # or "quiz"
    )
    markup = ReplyKeyboardMarkup([[button]], one_time_keyboard=True)
    await update.message.reply_text(
        "Create and share a poll with us:",
        reply_markup=markup,
    )
```

When the user sends a poll via this button, the bot receives a message with
`message.poll` set. Handle it:

```python
from telegram.ext import MessageHandler, filters

async def received_shared_poll(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    poll = update.message.poll
    await update.message.reply_text(
        f"Got your poll: '{poll.question}' with {len(poll.options)} options."
    )

app.add_handler(MessageHandler(filters.POLL, received_shared_poll))
```

## Poll data model

| Class | Key fields |
|---|---|
| `Poll` | `id`, `question`, `options` (list of `PollOption`), `total_voter_count`, `is_closed`, `is_anonymous`, `type`, `allows_multiple_answers`, `correct_option_id`, `explanation` |
| `PollOption` | `text`, `voter_count` |
| `InputPollOption` | `text` — used when creating polls |
| `PollAnswer` | `poll_id`, `voter_chat` (for anonymous), `user` (non-anonymous), `option_ids` |

## Poll notes and limitations

- `PollAnswerHandler` only fires for **non-anonymous** polls (`is_anonymous=False`).
- `PollHandler` fires for non-anonymous polls when vote counts update.
- For **anonymous** polls, only `PollHandler` fires when the poll is stopped —
  individual voter identities are never revealed.
- `open_period` must be between 5 and 600 seconds.
- A quiz poll can only have one correct answer (`correct_option_id` = single int).
- Poll questions: max 300 characters.
- Poll options: 2–10 options, each max 100 characters.
- Explanation: max 200 characters.

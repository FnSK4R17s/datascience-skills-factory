# Colang Guide

Colang is an event-driven interaction modeling language for defining guardrail flows.
Interpreted by a Python runtime. Syntax is "pythonic" — indentation matters,
two-space indent is standard.
Source: `docs/configure-rails/colang/index.md`,
`docs/configure-rails/colang/colang-1/colang-language-syntax-guide.md`.

## Colang versions

| NeMo Guardrails Version | Colang Version |
|-------------------------|----------------|
| 0.1 - 0.7 | 1.0 |
| 0.8 | 2.0-alpha |
| >= 0.9 | 2.0-beta |

Colang 1.0 is default. Colang 2.0 adds parallel flows, standard library imports,
generation operator (`...`), async actions. Migration tool:
`nemoguardrails convert "path" --from-version "2.0-alpha"`.

## Core concepts

- **Utterance**: raw text from user or bot
- **Intent**: canonical form (structured representation) of an utterance
- **Event**: something relevant to the conversation (user message, action result, etc.)
- **Action**: custom Python code the bot can invoke
- **Context**: key-value dictionary of conversation data (variables)
- **Flow**: sequence of messages and events with branching logic
- **Rails**: controls on bot behavior (content filtering, topic blocking, etc.)

## Colang 1.0 syntax

### User messages — define canonical forms

```
define user express greeting
  "hello"
  "hi"
  "hey there"
  "good morning"

define user request help
  "I need help"
  "Can you assist me?"
  "Help me with something"

define user ask about weather
  "What's the weather like?"
  "How's the weather today?"
  "Will it rain?"
```

Multiple utterances = examples for LLM-based intent matching. The LLM uses these
to classify new user inputs into the closest canonical form.

### Bot messages

```
define bot express greeting
  "Hello there!"
  "Hi! How can I help?"

define bot refuse to respond
  "I'm sorry, I can't respond to that."

define bot ask welfare
  "How are you feeling today?"
  "How are things going?"
```

Multiple utterances = one chosen randomly at runtime.

#### Bot messages with variables

```
define bot greet by name
  "Hello, $name!"
  "Welcome back, $name!"

# Jinja syntax also works
define bot greet by name
  "Hello, {{ name }}!"

# Conditional with Jinja
define bot status update
  "{% if status == 'active' %}Your account is active.{% else %}Your account is inactive.{% endif %}"
```

### Flows — conversation sequences

```
define flow greeting
  user express greeting
  bot express greeting
  bot ask welfare
```

Flows are pattern-matched against the conversation. When a user message matches
a flow's first step, the flow activates and drives the subsequent bot behavior.

#### Naming flows

```
# Named flow — good for organization and debugging
define flow greeting
  user express greeting
  bot express greeting

# Multiple flows can handle different scenarios
define flow help request
  user request help
  bot offer assistance

define flow farewell
  user express farewell
  bot express farewell
```

### Branching with if (context variables)

```
define flow greeting
  user express greeting
  if $first_time_user
    bot express greeting
    bot ask welfare
  else
    bot express welcome back

define flow premium_check
  user ask about premium features
  if $user_tier == "premium"
    bot explain premium features
  else if $user_tier == "basic"
    bot suggest upgrade
  else
    bot ask to sign up
```

### Branching with when (next user message)

```
define flow greeting and welfare
  user express greeting
  bot express greeting
  bot ask welfare

  when user express happiness
    bot express happiness
  else when user express sadness
    bot express empathy
  else
    bot express understanding

define flow order inquiry
  user ask about order
  bot ask for order number

  when user provide order number
    $order_info = execute lookup_order
    bot provide order info
  else when user express frustration
    bot express empathy
    bot offer to help
```

`if/else` evaluates context variables. `when/else` branches on the next
user message or event.

### Subflows — explicit invocation with `do`

```
define subflow check authentication
  if not $user_authenticated
    bot inform authentication required
    bot ask for credentials
    stop

define subflow rate_limit_check
  $count = execute get_request_count
  if $count > 100
    bot inform rate limited
    stop

define flow sensitive action
  user request account details
  do check authentication
  do rate_limit_check
  $details = execute get_account_details
  bot provide account details
```

Subflows are reusable across multiple flows. Unlike flows, they are not
automatically pattern-matched — they must be invoked with `do`.

### Actions — call Python from flows

```
define flow self check input
  $allowed = execute self_check_input

  if not $allowed
    bot refuse to respond
    stop

define flow answer with search
  user ask factual question
  $results = execute web_search(query=$last_user_message)
  bot provide search results

define flow process order
  user request order
  $order_id = execute create_order(
    product=$product_name,
    quantity=$quantity
  )
  bot confirm order
```

### Variables

Context variables use `$` prefix:

```
# Set a variable
define flow set preferences
  $language = "english"
  $theme = "dark"
  bot confirm preferences

# Use in conditions
define flow language check
  if $language == "spanish"
    bot respond in spanish
  else
    bot respond in english

# Variables from actions
define flow get user info
  $user_data = execute lookup_user(id=$user_id)
  if $user_data
    bot greet by name
  else
    bot ask for name
```

Variables can also be set by the application via `context` role messages:

```python
response = rails.generate(messages=[
    {"role": "context", "content": {"user_name": "Alice", "user_tier": "premium"}},
    {"role": "user", "content": "What features do I have?"}
])
```

### The `stop` keyword

Halts the current flow. Used after blocking a message:

```
define flow block harmful content
  $is_harmful = execute check_harmful_content
  if $is_harmful
    bot refuse to respond
    stop
  # Code after stop is never reached
```

### Topical rails — controlling what the bot discusses

```
define user ask about politics
  "What do you think about the elections?"
  "Who should I vote for?"
  "What's your political opinion?"

define user ask about competitors
  "What do you think about [competitor]?"
  "Is [competitor] better?"
  "Why should I choose you over [competitor]?"

define user ask about personal life
  "Do you have feelings?"
  "Are you alive?"
  "What's your favorite color?"

define bot inform cant discuss topic
  "I'm not able to discuss that topic. Is there something else I can help with?"

define flow block politics
  user ask about politics
  bot inform cant discuss topic

define flow block competitors
  user ask about competitors
  bot inform cant discuss topic

define flow redirect personal
  user ask about personal life
  bot inform cant discuss topic
```

### Dialog rails with context

```
define flow check user role
  if $user_role == "admin"
    bot provide admin response
  else if $user_role == "support"
    bot provide support response
  else
    bot provide standard response

define flow guided conversation
  user express interest in product
  bot ask about use case

  when user describe enterprise use case
    bot recommend enterprise plan
  else when user describe personal use case
    bot recommend personal plan
  else
    bot ask for more details
```

### RAG with fact-checking

```
define flow answer from knowledge base
  user ask about company policy
  $check_facts = True
  bot provide policy answer

define flow answer with custom rag
  user ask question
  $answer = execute custom_rag_search(query=$last_user_message)
  $check_facts = True
  bot $answer
```

### Hallucination detection in flows

```
# Blocking mode
define flow check people facts
  user ask about people
  $check_hallucination = True
  bot respond about people

# Warning mode
define flow check historical facts
  user ask about history
  $hallucination_warning = True
  bot respond about history

define bot inform answer prone to hallucination
  "Note: The previous answer may not be fully accurate. Please verify independently."
```

## Loading .co files

Colang `.co` files are loaded **recursively** from anywhere in the config
directory. Organize them however you like:

```
config/
├── config.yml
├── rails/
│   ├── input.co        # Input rail flows
│   ├── output.co       # Output rail flows
│   └── dialog.co       # Dialog rail flows
├── topics/
│   ├── greetings.co    # Greeting user/bot messages
│   └── blocked.co      # Blocked topic definitions
└── actions.py
```

Watch for unintended flow activation from leftover `.co` files — delete files
you no longer need.

## Colang 2.0 changes

- Smaller core: flows, events, actions.
- Explicit `main` flow entry point.
- Standard library imports.
- Parallel flow execution.
- Generation operator `...` for LLM-generated completions.
- Async action execution via `execute_async=True`.
- Python-like syntax refinements.

Current limitation: Guardrails Library not yet fully usable from within Colang 2.0.
Migration: `nemoguardrails convert "path" --from-version "2.0-alpha" --validate`.

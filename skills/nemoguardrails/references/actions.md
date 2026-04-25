# Custom Actions

Create Python functions callable from Colang flows using the `@action()` decorator.
Source: `docs/configure-rails/actions/creating-actions.md`,
`docs/configure-rails/actions/action-parameters.md`,
`docs/configure-rails/actions/registering-actions.md`,
`docs/configure-rails/actions/built-in-actions.md`.

## The @action() decorator

```python
from nemoguardrails.actions import action

@action()
async def my_custom_action():
    return "result"
```

### Decorator parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `name` | str | function name | Custom action name for Colang |
| `is_system_action` | bool | False | Always run locally, bypass actions server |
| `execute_async` | bool | False | Don't block event loop (Colang 2.x only) |
| `output_mapping` | Callable | default | Interpret return value for blocking decisions |

## Example: Input validation action

```python
from typing import Optional
from nemoguardrails.actions import action

@action(is_system_action=True)
async def check_input_length(context: Optional[dict] = None):
    """Block inputs longer than 1000 characters."""
    user_message = context.get("last_user_message", "")
    return len(user_message) <= 1000  # True = allow, False = block
```

Colang flow:

```
define flow check input length
  $allowed = execute check_input_length
  if not $allowed
    bot inform input too long
    stop

define bot inform input too long
  "Your message is too long. Please keep it under 1000 characters."
```

## Example: Output filtering action

```python
import re
from typing import Optional
from nemoguardrails.actions import action

@action(is_system_action=True)
async def filter_sensitive_patterns(context: Optional[dict] = None):
    """Check bot response for sensitive data patterns."""
    bot_response = context.get("bot_message", "")

    sensitive_patterns = [
        r"\b\d{3}-\d{2}-\d{4}\b",  # SSN
        r"\b\d{16}\b",              # Credit card
        r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b",  # Email
    ]

    for pattern in sensitive_patterns:
        if re.search(pattern, bot_response):
            return False  # Block — contains sensitive data

    return True  # Allow
```

## Example: External API action

```python
import aiohttp
from nemoguardrails.actions import action

@action(execute_async=True)
async def query_knowledge_base(query: str, top_k: int = 5):
    """Query an external knowledge base API without blocking event processing."""
    async with aiohttp.ClientSession() as session:
        async with session.post(
            "https://api.example.com/search",
            json={"query": query, "limit": top_k}
        ) as response:
            data = await response.json()
            return data.get("results", [])
```

Colang:

```
define flow answer with external kb
  user ask question
  $results = execute query_knowledge_base(query=$last_user_message, top_k=3)
  bot provide answer
```

## Example: Action with custom name

```python
@action(name="validate_user_input")
async def _internal_check(text: str):
    """Name exposed to Colang differs from function name."""
    return len(text) > 0
```

Colang: `$is_valid = execute validate_user_input(text=$user_message)`

## Example: Custom LLM call inside an action

```python
from typing import Optional
from langchain_core.language_models import BaseLLM
from nemoguardrails.actions import action

@action(is_system_action=True)
async def summarize_and_validate(
    text: str,
    llm: Optional[BaseLLM] = None
):
    """Two-step action: summarize, then validate the summary."""
    # First LLM call — summarize
    summary_prompt = f"Summarize this text in one sentence: {text}"
    summary = await llm.agenerate([summary_prompt])
    summary_text = summary.generations[0][0].text

    # Second LLM call — validate
    validation_prompt = f"Is this summary accurate? '{summary_text}'. Answer yes/no."
    validation = await llm.agenerate([validation_prompt])

    return {
        "summary": summary_text,
        "validation": validation.generations[0][0].text
    }
```

### Action-specific LLM

Override the default LLM for a specific action:

```python
from langchain_openai import ChatOpenAI

rails = LLMRails(config)
specialized_llm = ChatOpenAI(model="gpt-4o-mini", temperature=0)
rails.register_action_param("summarize_and_validate_llm", specialized_llm)
```

When `summarize_and_validate` runs and requests `llm`, it receives the
specialized model instead of the main LLM.

## Output mapping

Controls how the return value determines blocking.

Default behavior:
- Boolean `True` = allowed, `False` = blocked
- Numeric < 0.5 = blocked
- Other types = allowed by default

```python
# Return True when unsafe (inverted from default)
@action(output_mapping=lambda value: value)
async def check_hallucination(context: Optional[dict] = None):
    """Return True if hallucination detected (should block)."""
    return detect_hallucination(context.get("bot_message", ""))

# Return True when safe (needs inversion)
@action(is_system_action=True, output_mapping=lambda value: not value)
async def check_output_safety(context: Optional[dict] = None):
    """Return True if safe, mapped to not-blocked."""
    return is_safe(context.get("bot_message", ""))

# Custom mapping with score threshold
def score_mapping(result):
    if isinstance(result, dict):
        return result.get("score", 1.0) < 0.7
    return False

@action(output_mapping=score_mapping)
async def score_safety(context: Optional[dict] = None):
    return {"score": compute_score(context.get("bot_message", ""))}
```

## Special parameters

Include these in your function signature — auto-injected by the runtime.
Only available for locally-run actions (always local if `is_system_action=True`).

| Parameter | Type | Description |
|-----------|------|-------------|
| `context` | dict | Conversation state + variables |
| `events` | List[dict] | Full event history |
| `llm` | BaseLLM | Access to main LLM instance |
| `config` | RailsConfig | Full configuration |
| `llm_task_manager` | LLMTaskManager | Prompt rendering |
| `state` | State | Runtime state (Colang 2.x only) |

### Context variables

| Variable | Description | When available |
|----------|-------------|----------------|
| `last_user_message` | Most recent user input | After user input |
| `bot_message` | Current bot output | In output rails |
| `last_bot_message` | Previous bot output | After first response |
| `relevant_chunks` | Retrieved KB chunks | After retrieval |
| `user_intent` | Canonical user intent | After intent generation |
| `bot_intent` | Canonical bot intent | After next step generation |

Custom context variables set in flows are accessible too:

```
# In Colang
$user_preference = "dark_mode"
execute check_preference
```

```python
@action()
async def check_preference(context: Optional[dict] = None):
    return context.get("user_preference") == "dark_mode"
```

### Events parameter

```python
@action()
async def analyze_conversation(events: Optional[list] = None):
    user_messages = [
        e for e in events
        if e.get("type") == "UtteranceUserActionFinished"
    ]
    return {"message_count": len(user_messages)}
```

### Event types

| Event Type | Description |
|------------|-------------|
| `UtteranceUserActionFinished` | User sent a message |
| `StartUtteranceBotAction` | Bot started responding |
| `UtteranceBotActionFinished` | Bot finished responding |
| `StartInternalSystemAction` | System action started |
| `InternalSystemActionFinished` | System action completed |
| `UserIntent` | User intent determined |
| `BotIntent` | Bot intent determined |

### Config parameter

```python
@action()
async def check_config_setting(config: Optional[RailsConfig] = None):
    main_model = next(
        (m for m in config.models if m.type == "main"), None
    )
    max_interactions = config.custom_data.get("max_interactions", 100)
    return {"model_engine": main_model.engine if main_model else None}
```

## Example: Combining all special parameters

```python
from typing import Optional, List
from nemoguardrails.actions import action

@action(is_system_action=True)
async def advanced_safety_check(
    context: Optional[dict] = None,
    events: Optional[List[dict]] = None,
    llm=None,
    config=None,
):
    """Multi-layer check: rate limit, then LLM validation."""
    message = context.get("last_user_message", "")

    # Rate limit based on event history
    interaction_count = len([
        e for e in events
        if e.get("type") == "UtteranceUserActionFinished"
    ])
    max_interactions = config.custom_data.get("max_interactions", 100)
    if interaction_count > max_interactions:
        return False

    # LLM-based check for complex inputs
    if len(message) > 200:
        result = await llm.agenerate([f"Is this user input safe? {message}"])
        return "no" not in result.generations[0][0].text.lower()

    return True
```

Colang:

```
define flow advanced check
  $allowed = execute advanced_safety_check
  if not $allowed
    bot refuse to respond
    stop
```

## Registering actions

### Auto-discovery (recommended)

Place `actions.py` or `actions/` package in your config directory. Functions
decorated with `@action()` are auto-registered on `RailsConfig.from_path()`.

```
config/
├── config.yml
├── actions.py          # Single file
└── actions/            # Or a package
    ├── __init__.py
    ├── validation.py
    └── external_api.py
```

### Programmatic registration

```python
rails = LLMRails(config)
rails.register_action(my_function, name="my_action")
```

### LangChain chain as action

```python
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate

chain = ChatPromptTemplate.from_template("Summarize: {text}") | ChatOpenAI()
rails.register_action(chain, "summarize")
```

Colang: `$result = execute summarize`

## Built-in actions reference

### Core actions

| Action | Description |
|--------|-------------|
| `generate_user_intent` | Convert raw user input to canonical form |
| `generate_next_steps` | Determine next conversation step |
| `generate_bot_message` | Generate bot response text |
| `retrieve_relevant_chunks` | Retrieve context from knowledge base |

### Guardrail actions

| Action | Description |
|--------|-------------|
| `self_check_input` | LLM-based input policy check |
| `self_check_output` | LLM-based output policy check |
| `self_check_facts` | Fact verification against evidence |
| `self_check_hallucination` | Hallucination detection |
| `jailbreak_detection_heuristics` | Perplexity-based jailbreak detection |
| `jailbreak_detection_model` | NIM-based jailbreak classifier |
| `detect_sensitive_data` | Detect PII in text |
| `mask_sensitive_data` | Mask detected PII |
| `llama_guard_check_input` | Llama Guard input moderation |
| `llama_guard_check_output` | Llama Guard output moderation |
| `content_safety_check_input` | NVIDIA content safety (input) |
| `content_safety_check_output` | NVIDIA content safety (output) |

### Example: Combining built-in actions in a custom flow

```
define flow defense_in_depth_input_check
  # Layer 1: jailbreak detection
  $is_jailbreak = execute jailbreak_detection_heuristics
  if $is_jailbreak
    bot refuse to respond
    stop

  # Layer 2: PII detection
  $has_pii = execute detect_sensitive_data
  if $has_pii
    bot ask to remove sensitive data
    stop

  # Layer 3: LLM self-check
  $allowed = execute self_check_input
  if not $allowed
    bot refuse to respond
    stop

define bot ask to remove sensitive data
  "Your message contains sensitive information. Please remove it and try again."
```

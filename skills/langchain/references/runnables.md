# Runnables and LCEL

LangChain Expression Language (LCEL) is the composition layer for v1. Every
object that implements the `Runnable` interface can be chained, parallelized,
retried, or streamed with a uniform API.

## The Runnable interface

Every `Runnable` exposes the same surface:

| Method | Sync | Async |
|--------|------|-------|
| Single invoke | `.invoke(input, config=None)` | `.ainvoke(...)` |
| Streaming | `.stream(input, config=None)` | `.astream(...)` |
| Batch | `.batch(inputs, config=None)` | `.abatch(...)` |
| Event stream | — | `.astream_events(input, version="v2")` |

`input` and `output` types depend on the specific runnable. A prompt
template takes a dict and emits a `PromptValue`; a chat model takes
`PromptValue | list[BaseMessage]` and emits `AIMessage`.

## Composition with `|`

```python
from langchain_core.prompts import ChatPromptTemplate
from langchain_openai import ChatOpenAI
from langchain_core.output_parsers import StrOutputParser

prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    ("human", "{question}"),
])
llm = ChatOpenAI(model="gpt-4o-mini")
parser = StrOutputParser()

chain = prompt | llm | parser          # RunnableSequence
result = chain.invoke({"question": "What is LCEL?"})
```

`|` is syntactic sugar for `RunnableSequence`. Left side output becomes
right side input. Type errors are caught at call time, not definition time.

## Parallel execution

```python
from langchain_core.runnables import RunnableParallel

step = RunnableParallel(
    topic=topic_chain,
    sentiment=sentiment_chain,
)
# Both chains receive the same input; output is {"topic": ..., "sentiment": ...}
out = step.invoke({"text": "..."})
```

## Passthrough and lambda steps

```python
from langchain_core.runnables import RunnablePassthrough, RunnableLambda

# Merge original input into the chain output
chain = RunnablePassthrough.assign(context=retriever) | prompt | llm

# Arbitrary Python
clean = RunnableLambda(lambda x: x.strip())
```

## Config injection

Pass `RunnableConfig` to every call to control callbacks, tags, metadata,
and recursion limits:

```python
from langchain_core.runnables import RunnableConfig

config = RunnableConfig(
    callbacks=[my_handler],
    tags=["prod"],
    metadata={"user_id": "u123"},
    max_concurrency=4,          # for .batch()
)
result = chain.invoke(input, config=config)
```

Config is thread-safe and propagates automatically through nested runnables.

## Fallbacks

```python
primary = ChatOpenAI(model="gpt-4o")
fallback = ChatAnthropic(model="claude-3-haiku")
safe_llm = primary.with_fallbacks([fallback])
```

On exception, the fallback list is tried in order. Works on any Runnable,
not just LLMs.

## Retries

```python
chain_with_retry = chain.with_retry(
    retry_if_exception_type=(RateLimitError,),
    stop_after_attempt=3,
    wait_exponential_jitter=True,
)
```

## Binding parameters

```python
# Fix model params without rebuilding the object
gpt4_json = llm.bind(response_format={"type": "json_object"})
chain = prompt | gpt4_json | parser
```

`.bind()` returns a new `RunnableBinding`; the underlying runnable is
unchanged.

## Common traps

- **Calling `chain(input)` instead of `chain.invoke(input)`** — `__call__`
  is deprecated; callbacks and config do not propagate reliably through it.
- **Forgetting that `.stream()` yields chunks, not the full response** —
  accumulate with `"".join(chain.stream(input))` if you need the whole
  string.
- **Mismatched input keys** — `ChatPromptTemplate` raises `KeyError` at
  `.invoke()` if the dict is missing a variable declared in the template.
  Verify variable names with `prompt.input_variables`.
- **`RunnableParallel` receives the same input as each branch** — do not
  expect branches to see each other's output; use `RunnablePassthrough.assign`
  for that pattern.
- **Async in sync context** — `.ainvoke()` must be awaited inside an
  `async def`. In a sync script, use `.invoke()` or wrap with
  `asyncio.run()`.

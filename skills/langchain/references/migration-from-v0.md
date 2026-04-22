# Migration from LangChain v0

LangChain v1 is a consolidation of the `0.1.x` / `0.2.x` / `0.3.x` line.
The core ideas are the same; the main changes are import paths, deprecated
call patterns, and Pydantic v2 enforcement.

## Package structure

v1 split the monolith into layers. Install what you need:

| Package | What it contains |
|---------|-----------------|
| `langchain-core` | Base types: `Runnable`, messages, prompts, output parsers, tools, callbacks |
| `langchain` | High-level abstractions: chains, agents (mostly soft-deprecated wrappers) |
| `langchain-community` | Third-party integrations; maintained externally |
| `langchain-openai` | OpenAI chat + embedding models |
| `langchain-anthropic` | Anthropic / Claude models |
| `langchain-google-genai` | Google Gemini models |

Rule of thumb: prefer importing from `langchain-core` and the specific
provider package. Avoid importing from `langchain` directly unless you need
the high-level chains.

## Import moves

| Old (v0) | New (v1) |
|---------|---------|
| `from langchain.chat_models import ChatOpenAI` | `from langchain_openai import ChatOpenAI` |
| `from langchain.schema import HumanMessage, AIMessage` | `from langchain_core.messages import HumanMessage, AIMessage` |
| `from langchain.prompts import ChatPromptTemplate` | `from langchain_core.prompts import ChatPromptTemplate` |
| `from langchain.callbacks import ...` | `from langchain_core.callbacks import ...` |
| `from langchain.tools import tool` | `from langchain_core.tools import tool` |
| `from langchain.output_parsers import StrOutputParser` | `from langchain_core.output_parsers import StrOutputParser` |
| `from langchain.embeddings import OpenAIEmbeddings` | `from langchain_openai import OpenAIEmbeddings` |
| `from langchain.vectorstores import Chroma` | `from langchain_community.vectorstores import Chroma` |

The old paths still work in v1 (they emit `DeprecationWarning`). They will
be removed in a future release — migrate when you encounter them.

## Deprecated call patterns

| Old pattern | Replacement |
|-------------|-------------|
| `chain(input)` — `__call__` | `chain.invoke(input)` |
| `llm.predict(text)` | `llm.invoke(text)` |
| `llm.predict_messages(messages)` | `llm.invoke(messages)` |
| `chain.run(input)` | `chain.invoke(input)` |
| `chain.apply(inputs)` | `chain.batch(inputs)` |
| `await chain.arun(input)` | `await chain.ainvoke(input)` |

## Deprecated chain classes

| Old class | v1 replacement |
|-----------|---------------|
| `LLMChain` | LCEL: `prompt \| llm \| parser` |
| `SequentialChain` | `RunnableSequence` via `\|` operator |
| `ConversationalRetrievalChain` | LCEL with `MessagesPlaceholder` for history + retriever step |
| `RetrievalQA` | LCEL: `retriever \| format_docs \| prompt \| llm \| parser` |
| `MapReduceDocumentsChain` | Custom LCEL with `RunnableParallel` or LangGraph map-reduce |

These classes still exist and work in v1; they emit deprecation warnings.
New code should not use them.

## Pydantic v2

LangChain v1 uses Pydantic v2 internally. If your code extends `BaseModel`:

- Replace `validator` with `field_validator` and add `@classmethod`.
- Replace `root_validator` with `model_validator`.
- Remove `.dict()` calls — use `.model_dump()` instead.
- Remove `.schema()` calls — use `.model_json_schema()` instead.

If you see errors like `PydanticUserError: `validator` method not allowed`
when defining a custom runnable or tool, you are mixing v1/v2 Pydantic APIs.

## Memory (changed significantly)

v0 `ConversationBufferMemory` and siblings are removed / soft-deprecated.
v1 manages conversation history explicitly in message lists or in LangGraph
state:

```python
# v0 (deprecated)
memory = ConversationBufferMemory()
chain = LLMChain(llm=llm, memory=memory, prompt=prompt)

# v1 — explicit history
history: list[BaseMessage] = []
prompt = ChatPromptTemplate.from_messages([
    ("system", "You are helpful."),
    MessagesPlaceholder("history"),
    ("human", "{input}"),
])
chain = prompt | llm

def chat(user_input: str) -> str:
    response = chain.invoke({"input": user_input, "history": history})
    history.append(HumanMessage(user_input))
    history.append(response)
    return response.content
```

For persistent cross-session memory, use LangGraph with a persistent
checkpointer (PostgreSQL, Redis, etc.).

## Checking your installed version

```bash
pip show langchain langchain-core langchain-community
```

Compare against the changelog on the LangChain docs site. The v1 release
line increments minor versions frequently; breaking changes are flagged in
the changelog with `BREAKING` tags.

---
name: langchain
description: >
  Guide an agent writing Python code with LangChain v1 (langchain-core,
  langchain, langgraph). Use when code imports langchain or langchain-core,
  when the user asks about Runnables, LCEL, tool calling, structured output,
  or message types, or when debugging chain / agent behavior.
  SKIP if the file only imports openai / anthropic / other provider SDK
  with no LangChain wrapper.
triggers:
  - langchain
  - langchain-core
  - LCEL
  - Runnable
  - ChatPromptTemplate
  - create_react_agent
---

# LangChain v1 (Python)

Help agents write correct, idiomatic code against the LangChain v1 release
line. This is a problem-statement skill with reference data — it defines
the traps and the stable concepts, not the implementation.

The authoritative source is the LangChain Python docs site (search by
name, not by a hardcoded URL; the URL structure shifts with each Mintlify
upgrade). When the docs site and this file disagree, the docs site wins.

## When to invoke

- Code file imports `langchain`, `langchain-core`, `langchain-community`, or
  `langchain-openai` / `langchain-anthropic` / other provider packages.
- User mentions Runnables, LCEL (`|` operator), chains, agents, tool calling,
  structured output, streaming, or LangGraph in a Python context.
- Debugging `invoke` / `stream` / `batch` / `astream_events` behavior.
- Migrating code from LangChain v0 (`0.x`) to v1.

## When NOT to invoke

- File imports only `openai`, `anthropic`, or another raw SDK with no
  LangChain import — this is provider-native code; a LangChain skill adds
  noise.
- User is asking about LangSmith or LangGraph Cloud (deployment / tracing
  infrastructure) rather than application code — defer to their own docs.
- User is writing LangGraph state machine graphs without any chain / LCEL
  composition — that is a LangGraph concern.

## What changed in v1

LangChain v1 is not a rewrite. The primary visible breaks from v0 are:

1. **Package split** — `langchain-core` is now a separate install that
   contains the base abstractions (`Runnable`, message types, output
   parsers). `langchain` depends on it. Many imports that lived under
   `langchain.schema` or `langchain.chat_models` moved; old paths emit
   deprecation warnings, not errors, for now.
2. **`invoke` / `stream` / `batch` as the canonical API** — the
   old `__call__` / `predict` / `run` shortcuts are deprecated.
3. **Pydantic v2 required** — `BaseModel` from Pydantic v2 only. v1
   compatibility shims exist but are not guaranteed long-term.
4. **Structured output unified** — `llm.with_structured_output(Schema)` is
   the single recommended path; per-provider hacks are now internal.

See `references/migration-from-v0.md` for the full deprecation map.

## References

| File | What it covers |
|------|---------------|
| `references/runnables.md` | Runnable protocol, `|` composition, invoke/stream/batch/astream, config injection, fallbacks |
| `references/messages.md` | Message types, content-block model, multimodal payloads, provider abstraction |
| `references/structured-output.md` | `with_structured_output`, schema choices, per-provider failure modes |
| `references/streaming.md` | Token streaming, `astream_events` v2, UI integration, common pitfalls |
| `references/agents.md` | `create_react_agent`, tool calling loop, middleware, interrupt / human-in-the-loop |
| `references/migration-from-v0.md` | Import moves, deprecated methods, v0 → v1 translation table |

Start with the file that matches the user's immediate problem. For new
projects, read `runnables.md` first — LCEL is the foundation everything
else builds on.

## Anti-recommendations

- Do not use `LLMChain` or `ConversationalRetrievalChain` in new code.
  Both are soft-deprecated. Express the same composition with LCEL.
- Do not construct message dicts by hand (`{"role": "user", "content": ...}`).
  Use the typed classes (`HumanMessage`, `AIMessage`, etc.) so provider
  abstraction works correctly.
- Do not call `llm(prompt)` (the `__call__` shortcut). Use
  `llm.invoke(prompt)` so the Runnable protocol and callbacks wire up
  correctly.
- Do not pin a version number in advice (e.g. "install langchain==1.0.3").
  Check the installed version with `pip show langchain` and compare against
  the changelog; the v1 release line moves fast.

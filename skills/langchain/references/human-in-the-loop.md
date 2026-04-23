# Human-in-the-Loop

Source: `docs/human-in-the-loop.md`, `docs/middleware__built-in.md`

## Overview

`HumanInTheLoopMiddleware` pauses agent execution before specified tool calls, waits for a
human decision, then resumes. Requires a checkpointer (state must be persisted across the
interrupt).

## Setup

```python
from langchain.agents import create_agent
from langchain.agents.middleware import HumanInTheLoopMiddleware
from langgraph.checkpoint.memory import InMemorySaver  # use PostgresSaver in production

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[write_file_tool, execute_sql_tool, read_data_tool],
    checkpointer=InMemorySaver(),
    middleware=[
        HumanInTheLoopMiddleware(
            interrupt_on={
                "write_file": True,               # all decisions allowed
                "execute_sql": {
                    "allowed_decisions": ["approve", "reject"]  # no edit
                },
                "read_data": False,               # auto-approve, no interrupt
            },
            description_prefix="Action pending approval",
        )
    ],
)
```

## Decision types

| Decision | Description |
|----------|-------------|
| `approve` | Execute the tool call exactly as proposed |
| `edit` | Execute with modified arguments (agent may reconsider) |
| `reject` | Reject and add explanation to the conversation |

## Interrupt / resume flow

When an interrupt fires, `agent.invoke()` returns early with an `Interrupt` in the state.
Your code inspects the interrupt and resumes by calling the agent again with the same
`thread_id` and no new messages:

```python
import json
from langgraph.types import Command

# Invoke — may pause mid-run
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Delete all test records from DB"}]},
    {"configurable": {"thread_id": "t1"}},
)

# Check for interrupt
interrupts = [m for m in result.get("__interrupt__", [])]
if interrupts:
    interrupt = interrupts[0]
    print("Pending action:", interrupt.value)

    # Resume with approve
    result = agent.invoke(
        Command(resume=[{"type": "approve"}]),
        {"configurable": {"thread_id": "t1"}},
    )

    # Resume with edit
    result = agent.invoke(
        Command(resume=[{"type": "edit", "args": {"query": "DELETE FROM test_records WHERE id > 1000"}}]),
        {"configurable": {"thread_id": "t1"}},
    )

    # Resume with reject
    result = agent.invoke(
        Command(resume=[{"type": "reject", "reason": "Too broad — add a WHERE clause"}]),
        {"configurable": {"thread_id": "t1"}},
    )
```

When multiple tool calls are pending simultaneously, supply one decision per call in the
same order they appear in the interrupt.

## Multiple simultaneous interrupts

When multiple tool calls are intercepted at once, provide decisions in a list:

```python
result = agent.invoke(
    Command(resume=[
        {"type": "approve"},       # for first tool call
        {"type": "reject", "reason": "Not safe"},  # for second
    ]),
    {"configurable": {"thread_id": "t1"}},
)
```

## Frontend patterns

The frontend `useStream` hook surfaces interrupts as reactive state. Wire the `interrupt`
field to an approval UI component (see `docs/frontend__human-in-the-loop.md`). The backend
pattern is the same — the frontend triggers a resume POST with the decision.

## Notes

- `HumanInTheLoopMiddleware` requires a checkpointer on the same agent.
- In production use `AsyncPostgresSaver` (or equivalent async checkpointer).
- Persistent shell sessions (`ShellToolMiddleware`) do not currently support HITL interrupts.
- Editing tool arguments conservatively reduces the chance of unexpected re-planning.

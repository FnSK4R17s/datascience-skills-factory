# Human-in-the-Loop

Source: `docs/human-in-the-loop.md`, `docs/middleware__built-in.md`

## Overview

`HumanInTheLoopMiddleware` pauses agent execution before specified tool calls, waits for
a human decision, and then resumes. Decisions can approve, edit (modify arguments), or
reject (block with feedback). State is persisted via LangGraph's checkpointing so
execution can pause safely and resume later — even across HTTP requests.

## Setup

```python
from langchain.agents import create_agent
from langchain.agents.middleware import HumanInTheLoopMiddleware
from langgraph.checkpoint.memory import InMemorySaver       # dev
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver  # production

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[write_file_tool, execute_sql_tool, read_data_tool],
    # checkpointer required — HITL uses LangGraph's persistence layer
    checkpointer=InMemorySaver(),
    middleware=[
        HumanInTheLoopMiddleware(
            interrupt_on={
                # True = all decisions allowed (approve, edit, reject)
                "write_file": True,
                # Dict = restrict available decisions
                "execute_sql": {
                    "allowed_decisions": ["approve", "reject"],  # no edit
                    # Optional: custom description for the approval UI
                    "description": "SQL execution requires DBA approval",
                },
                # False = auto-approve, no interrupt
                "read_data": False,
            },
            # Default prefix for interrupt messages; combined with tool name + args
            description_prefix="Tool execution pending approval",
        )
    ],
)
```

### Configuration options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `interrupt_on` | `dict` | required | Map tool name → `True`, `False`, or `InterruptOnConfig` |
| `description_prefix` | `str` | `"Tool execution requires approval"` | Prefix for interrupt descriptions |

`InterruptOnConfig` fields:
- `allowed_decisions` — list of `"approve"`, `"edit"`, `"reject"`
- `description` — static string or callable for custom approval message

## Decision types

| Decision | Description | When to use |
|----------|-------------|-------------|
| `approve` | Execute tool call exactly as proposed | Action is safe to run as-is |
| `edit` | Execute with modified arguments | Action is right concept, wrong parameters |
| `reject` | Block and add explanation to conversation | Action is wrong; agent should try again |

Edit conservatively — large argument changes may cause the agent to re-plan
and issue additional tool calls.

## Interrupt / resume flow with `version="v2"`

```python
from langgraph.types import Command

config = {"configurable": {"thread_id": "session-123"}}

# Step 1: first invoke — runs until interrupt or completion
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Delete all records older than 30 days"}]},
    config=config,
    version="v2",  # returns GraphOutput with .value and .interrupts
)

# Step 2: inspect the interrupt
if result.interrupts:
    interrupt = result.interrupts[0]
    # interrupt.value contains action_requests and review_configs
    # {
    #   "action_requests": [
    #     {
    #       "name": "execute_sql",
    #       "arguments": {"query": "DELETE FROM records WHERE created_at < NOW() - INTERVAL '30 days'"},
    #       "description": "SQL execution requires DBA approval\n\nTool: execute_sql\nArgs: ..."
    #     }
    #   ],
    #   "review_configs": [
    #     {"action_name": "execute_sql", "allowed_decisions": ["approve", "reject"]}
    #   ]
    # }
    action = interrupt.value["action_requests"][0]
    print(f"Pending: {action['name']} with args {action['arguments']}")

# Step 3: resume with a decision
# Approve as-is:
result = agent.invoke(
    Command(resume={"decisions": [{"type": "approve"}]}),
    config=config,  # same thread_id
    version="v2",
)

# Or reject with feedback:
result = agent.invoke(
    Command(resume={"decisions": [{"type": "reject", "message": "Too broad — add a customer_id filter"}]}),
    config=config,
    version="v2",
)
```

## Edit decision

Modify the tool call before execution. Provide the full edited action:

```python
result = agent.invoke(
    Command(
        resume={
            "decisions": [
                {
                    "type": "edit",
                    "edited_action": {
                        "name": "execute_sql",  # usually same as original
                        "args": {
                            "query": "DELETE FROM records WHERE created_at < NOW() - INTERVAL '30 days' AND customer_id = 42"
                        },
                    },
                }
            ]
        }
    ),
    config=config,
    version="v2",
)
```

## Multiple simultaneous interrupts

When the model proposes multiple tool calls at once and multiple require approval,
all are bundled into a single interrupt. Provide decisions in the same order:

```python
# interrupt.value["action_requests"] has multiple entries, e.g.:
# [
#   {"name": "write_file", "arguments": {"path": "/tmp/report.csv", "content": "..."}},
#   {"name": "execute_sql", "arguments": {"query": "UPDATE ..."}},
# ]

result = agent.invoke(
    Command(
        resume={
            "decisions": [
                {"type": "approve"},  # for write_file
                {
                    "type": "edit",
                    "edited_action": {
                        "name": "execute_sql",
                        "args": {"query": "UPDATE users SET status='inactive' WHERE last_seen < '2025-01-01'"},
                    },
                },
            ]
        }
    ),
    config=config,
    version="v2",
)
```

## Streaming with HITL

Use `stream()` with `version="v2"` to get real-time tokens and detect interrupts in
a unified chunk stream.

```python
from langgraph.types import Command

config = {"configurable": {"thread_id": "session-789"}}

# First run: stream until interrupt
interrupt_data = None
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "Drop the staging_data table"}]},
    config=config,
    stream_mode=["updates", "messages"],
    version="v2",
):
    if chunk["type"] == "messages":
        token, _metadata = chunk["data"]
        if token.content:
            print(token.content, end="", flush=True)

    elif chunk["type"] == "updates":
        if "__interrupt__" in chunk["data"]:
            interrupt_data = chunk["data"]["__interrupt__"]
            print(f"\n\n[INTERRUPT] {interrupt_data}")
            break

# Present interrupt to human (e.g., render in UI)
# ... human reviews and decides ...

# Resume: stream the remaining agent execution
for chunk in agent.stream(
    Command(resume={"decisions": [{"type": "reject", "message": "Do not drop tables — archive instead"}]}),
    config=config,
    stream_mode=["updates", "messages"],
    version="v2",
):
    if chunk["type"] == "messages":
        token, _metadata = chunk["data"]
        if token.content:
            print(token.content, end="", flush=True)
```

## Execution lifecycle

1. Agent calls the LLM — receives a response with tool calls.
2. `HumanInTheLoopMiddleware.after_model` inspects the tool calls.
3. For any matching `interrupt_on` entries, the middleware builds a `HITLRequest`
   with `action_requests` and `review_configs`.
4. Middleware calls LangGraph's `interrupt()` — halts execution and persists state.
5. `agent.invoke()` returns early with the interrupt(s) in `result.interrupts`.
6. Human (or code) reviews and calls `agent.invoke(Command(resume=...))`.
7. Middleware processes decisions: approved and edited calls are executed; rejected
   calls get a synthesized `ToolMessage` with the rejection reason.
8. Agent continues normally.

## Production setup with async Postgres checkpointer

```python
import asyncio
from langchain.agents import create_agent
from langchain.agents.middleware import HumanInTheLoopMiddleware
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver

DB_URI = "postgresql://user:pass@host:5432/mydb"

async def build_agent():
    async with AsyncPostgresSaver.from_conn_string(DB_URI) as checkpointer:
        await checkpointer.setup()

        agent = create_agent(
            model="anthropic:claude-sonnet-4-6",
            tools=[write_file_tool, execute_sql_tool],
            checkpointer=checkpointer,
            middleware=[
                HumanInTheLoopMiddleware(
                    interrupt_on={
                        "write_file": True,
                        "execute_sql": {"allowed_decisions": ["approve", "reject"]},
                    }
                )
            ],
        )
        return agent


# In an API endpoint:
async def handle_request(user_message: str, thread_id: str):
    agent = await build_agent()
    config = {"configurable": {"thread_id": thread_id}}
    result = await agent.ainvoke(
        {"messages": [{"role": "user", "content": user_message}]},
        config=config,
        version="v2",
    )
    return result

async def handle_decision(thread_id: str, decisions: list[dict]):
    agent = await build_agent()
    config = {"configurable": {"thread_id": thread_id}}
    result = await agent.ainvoke(
        Command(resume={"decisions": decisions}),
        config=config,
        version="v2",
    )
    return result
```

## Custom HITL logic

For specialized workflows, use LangGraph's `interrupt` primitive directly in a
middleware hook. This gives full control over the interrupt value structure and
resume protocol.

```python
from langgraph.types import interrupt
from langchain.agents.middleware import after_model, AgentState
from typing import Any

@after_model
def custom_hitl(state: AgentState, runtime) -> dict[str, Any] | None:
    """Custom HITL: require approval for any tool that modifies data."""
    last_msg = state["messages"][-1]
    destructive_tools = {"delete_records", "update_user", "send_email"}

    pending = [tc for tc in last_msg.tool_calls if tc["name"] in destructive_tools]
    if not pending:
        return None  # nothing to review

    # interrupt() halts execution and stores the value in result.interrupts
    decision = interrupt({
        "pending_tool_calls": pending,
        "message": "These actions require approval before execution.",
    })

    # When resumed, decision contains the human's response
    # Implement your own approve/reject logic here
    if decision.get("approved"):
        return None  # continue — ToolNode will execute the calls
    else:
        # Cancel the tool calls by replacing the AI message
        from langchain.messages import AIMessage, ToolMessage
        feedback = decision.get("reason", "Action rejected.")
        cancelled_messages = [
            ToolMessage(
                content=f"Rejected: {feedback}",
                tool_call_id=tc["id"],
                name=tc["name"],
            )
            for tc in pending
        ]
        return {"messages": cancelled_messages}
```

## Notes

- `HumanInTheLoopMiddleware` requires a checkpointer on the agent.
- Persistent shell sessions (`ShellToolMiddleware`) do not support HITL interrupts.
- For async production use, always use `AsyncPostgresSaver` or equivalent.
- Editing arguments conservatively reduces unexpected re-planning.
- When using HITL in a web API: store the `thread_id` client-side and pass it back
  on the resume request to correlate with the paused state.

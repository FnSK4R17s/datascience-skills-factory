# Multi-agent

Source: `docs/multi-agent__index.md`, `docs/multi-agent__subagents.md`, `docs/multi-agent__handoffs.md`,
`docs/multi-agent__router.md`, `docs/multi-agent__skills.md`, `docs/multi-agent__custom-workflow.md`,
`docs/multi-agent__subagents-personal-assistant.md`, `docs/multi-agent__handoffs-customer-support.md`,
`docs/multi-agent__router-knowledge-base.md`, `docs/multi-agent__skills-sql-assistant.md`

## Pattern overview

| Pattern | When to use |
|---------|-------------|
| Subagents | Main agent coordinates specialists as tools; parallel execution, context isolation |
| Handoffs | Single agent reconfigures itself (tools + prompt) based on state transitions |
| Skills | Single agent loads specialised prompts/context on-demand via tool calls |
| Router | One-shot classifier dispatches to specialist agents in parallel, synthesises results |
| Custom workflow | Full LangGraph control: deterministic + agentic nodes, loops, branches |

## Subagents (supervisor pattern)

A main agent wraps each subagent as a tool. Subagents are stateless per invocation.

```python
from langchain.tools import tool
from langchain.agents import create_agent

calendar_agent = create_agent(model, tools=[check_availability, create_event])
email_agent = create_agent(model, tools=[draft_email, send_email])

@tool("calendar_agent", description="Manage calendar events and scheduling")
def call_calendar(query: str) -> str:
    """Delegate a calendar task."""
    result = calendar_agent.invoke({"messages": [{"role": "user", "content": query}]})
    return result["messages"][-1].text

@tool("email_agent", description="Draft and send emails")
def call_email(query: str) -> str:
    """Delegate an email task."""
    result = email_agent.invoke({"messages": [{"role": "user", "content": query}]})
    return result["messages"][-1].text

supervisor = create_agent(
    model,
    tools=[call_calendar, call_email],
    system_prompt="You coordinate calendar and email specialists."
)
```

SubAgentMiddleware (from `deepagents`) is an alternative approach that registers subagents
through middleware and exposes them via a `task` tool.

## Handoffs (state machine pattern)

Tools return `Command` objects to update state, transitioning the agent through workflow steps.

```python
from langchain.tools import tool
from langchain.messages import ToolMessage
from langgraph.types import Command

@tool
def collect_warranty_status(status: str, runtime) -> Command:
    """Record warranty status and advance to next step."""
    return Command(
        update={
            "warranty_status": status,
            "current_step": "classify_issue",
            "messages": [
                ToolMessage(
                    content=f"Warranty status recorded: {status}",
                    tool_call_id=runtime.tool_call_id,
                )
            ],
        }
    )
```

The agent's middleware reads `current_step` from state and adjusts its system prompt and
available tools accordingly, implementing different behaviour in each step.

## Skills (progressive disclosure)

Load specialized prompts and schemas on-demand instead of upfront:

```python
SKILLS = {
    "sales": {"description": "...", "schema": "...", "queries": "..."},
    "inventory": {"description": "...", "schema": "...", "queries": "..."},
}

@tool
def load_skill(skill_name: str) -> str:
    """Load a specialized skill context."""
    skill = SKILLS.get(skill_name)
    if not skill:
        return f"Unknown skill: {skill_name}"
    return f"Skill loaded:\n{skill['schema']}\n{skill['queries']}"

agent = create_agent(
    model,
    tools=[load_skill, execute_query],
    system_prompt="Available skills: sales, inventory. Load a skill before writing SQL.",
)
```

## Router

Route queries to specialist agents using `Command` (single) or `Send` (parallel fan-out):

```python
from langgraph.types import Command, Send

def classify_query(state: dict) -> list:
    """Classify query and fan out to relevant agents."""
    query = state["messages"][-1].content
    # LLM call or rules to determine relevant agents
    agents = ["github_agent", "notion_agent"]  # example
    return [Send(agent, {"messages": state["messages"]}) for agent in agents]
```

Results are synthesised into a combined response by a final node.

## Custom workflow

Use LangGraph `StateGraph` directly to mix deterministic and agentic nodes:

```python
from langgraph.graph import StateGraph, MessagesState, START, END
from langgraph.prebuilt import ToolNode, tools_condition

builder = StateGraph(MessagesState)
builder.add_node("agent", call_llm)
builder.add_node("tools", ToolNode(tools))
builder.add_edge(START, "agent")
builder.add_conditional_edges("agent", tools_condition)
builder.add_edge("tools", "agent")
graph = builder.compile()
```

`create_agent` agents can be embedded as subgraphs inside any LangGraph graph.

## Tips

- Name agents with `name="snake_case"` — node identifiers can't have spaces.
- When streaming multi-agent output pass `subgraphs=True` to `.stream()`.
- Subagents run in their own context window; keep their system prompts focused.
- Human-in-the-loop requires a `checkpointer` on the outermost agent.

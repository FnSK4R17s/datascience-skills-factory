# Multi-agent

Source: `docs/multi-agent__index.md`, `docs/multi-agent__subagents.md`,
`docs/multi-agent__handoffs.md`, `docs/multi-agent__router.md`,
`docs/multi-agent__skills.md`, `docs/multi-agent__custom-workflow.md`,
`docs/multi-agent__subagents-personal-assistant.md`,
`docs/multi-agent__handoffs-customer-support.md`,
`docs/multi-agent__router-knowledge-base.md`,
`docs/multi-agent__skills-sql-assistant.md`

## Why multi-agent?

Multi-agent systems are justified when:
1. **Context management** — too many tools or too much knowledge for one context window
2. **Distributed development** — different teams maintain different agents independently
3. **Parallelization** — multiple specialist agents run concurrently

At the centre of multi-agent design is **context engineering** — deciding what information
each agent sees. The quality of your system depends on ensuring each agent has access to
the right data for its task.

## Pattern overview

| Pattern | How it works | Best for |
|---------|-------------|----------|
| **Subagents** | Main agent calls specialists as tools; all routing goes through supervisor | Parallel execution, context isolation |
| **Handoffs** | State machine where tools update state to trigger agent reconfiguration | Multi-hop conversations, user-facing dialogues |
| **Skills** | Single agent loads specialised prompts/context on-demand | Simple tasks, context reuse across turns |
| **Router** | Classifier routes to specialists in parallel, results synthesised | One-shot multi-domain queries |
| **Custom workflow** | Full LangGraph `StateGraph` control | Complex, mixed deterministic + agentic flows |

## Performance comparison

Source: `docs/multi-agent__index.md`

### One-shot request ("Buy coffee")

| Pattern | Model calls | Notes |
|---------|:-----------:|-------|
| Subagents | 4 | Extra call because result flows back through main agent |
| Handoffs | 3 | Direct, no overhead |
| Skills | 3 | Direct |
| Router | 3 | Direct |

### Repeat request (same task, second turn)

| Pattern | Turn 2 calls | Total | Reason |
|---------|:---:|:---:|--------|
| Subagents | 4 | 8 | Stateless by design — full flow each time |
| Handoffs | 2 | 5 | Agent stays active from turn 1, skips handoff |
| Skills | 2 | 5 | Skill context already loaded, reused |
| Router | 3 | 6 | Stateless — reroutes every time |

### Multi-domain request ("Compare Python, JS, and Rust for web dev")

| Pattern | Model calls | Total tokens | Notes |
|---------|:-----------:|:---:|--------|
| Subagents | 5 | ~9K | Parallel execution, context isolation per subagent |
| Handoffs | 7+ | ~14K+ | Sequential only; growing conversation history |
| Skills | 3 | ~15K | All skill context in one context window after loading |
| Router | 5 | ~9K | Parallel, explicit routing step |

**Conclusion:** Stateful patterns (Handoffs, Skills) win for repeat requests. Parallel
patterns (Subagents, Router) win for multi-domain tasks. Subagents and Router tie on token
efficiency due to context isolation.

## Pattern 1: Subagents (supervisor)

A main agent wraps each subagent as a tool. Subagents are **stateless per invocation** —
they get a clean context each time. The main agent (supervisor) maintains conversation
history and decides which subagents to invoke.

### Basic implementation

```python
from langchain.tools import tool
from langchain.agents import create_agent

# Create specialist subagents
calendar_agent = create_agent(
    model="openai:gpt-5.4",
    tools=[check_availability, create_event, cancel_event],
    system_prompt="You manage calendar scheduling. Be precise with dates and times.",
    name="calendar_agent",
)

email_agent = create_agent(
    model="anthropic:claude-sonnet-4-6",
    tools=[draft_email, send_email, list_emails],
    system_prompt="You compose and manage emails. Write professionally.",
    name="email_agent",
)

# Wrap each subagent as a tool
@tool("calendar_agent", description="Manage calendar events and scheduling. Use for creating, checking, or cancelling meetings.")
def call_calendar(query: str) -> str:
    """Delegate a calendar task to the calendar specialist."""
    result = calendar_agent.invoke({"messages": [{"role": "user", "content": query}]})
    return result["messages"][-1].text

@tool("email_agent", description="Draft, send, and read emails. Use for all email-related tasks.")
def call_email(query: str) -> str:
    """Delegate an email task to the email specialist."""
    result = email_agent.invoke({"messages": [{"role": "user", "content": query}]})
    return result["messages"][-1].text

# Main supervisor agent
supervisor = create_agent(
    model="openai:gpt-5.4",
    tools=[call_calendar, call_email],
    system_prompt=(
        "You are a personal assistant that coordinates specialists.\n"
        "- For scheduling: use calendar_agent\n"
        "- For emails: use email_agent\n"
        "Always combine results into a clear final response."
    ),
    name="supervisor",
)

result = supervisor.invoke({
    "messages": [{"role": "user", "content": "Schedule a meeting with Sarah for tomorrow at 2pm and email her the invite."}]
})
```

### Single dispatch tool (for many agents / dynamic registries)

```python
from enum import Enum
from langchain.tools import tool
from langchain.agents import create_agent

# Option 1: Enum constraint (type-safe, for small fixed sets)
class AgentName(str, Enum):
    RESEARCH = "research"
    WRITER = "writer"
    REVIEWER = "reviewer"

SUBAGENTS = {
    "research": create_agent(model="openai:gpt-5.4", tools=[search, fetch_url], name="research"),
    "writer": create_agent(model="anthropic:claude-sonnet-4-6", tools=[], name="writer"),
    "reviewer": create_agent(model="openai:gpt-5.4", tools=[], name="reviewer"),
}

@tool
def task(agent_name: AgentName, description: str) -> str:
    """Launch an ephemeral subagent for a task.

    Available agents:
    - research: Research and fact-finding
    - writer: Content creation and editing
    - reviewer: Quality review and feedback
    """
    agent = SUBAGENTS[agent_name.value]
    result = agent.invoke({"messages": [{"role": "user", "content": description}]})
    return result["messages"][-1].text

# Option 2: Tool-based discovery (for dynamic/large registries)
@tool
def list_agents(query: str = "") -> str:
    """List available subagents, optionally filtered by query."""
    agents = {
        "research": "Research and fact-finding from web and databases",
        "writer": "Content creation, editing, and summarization",
        "reviewer": "Code review, document review, quality assurance",
        "data_analyst": "Data analysis, statistics, visualization",
        "legal": "Legal document review and compliance",
    }
    if query:
        agents = {k: v for k, v in agents.items() if query.lower() in k or query.lower() in v}
    return "\n".join(f"- {k}: {v}" for k, v in agents.items())

coordinator = create_agent(
    model="openai:gpt-5.4",
    tools=[task, list_agents],
    system_prompt="Use list_agents to discover available specialists, then use task to delegate work.",
)
```

### Context engineering for subagents

Pass state context to subagents for richer input:

```python
from langchain.agents import AgentState
from langchain.tools import tool, ToolRuntime
from typing import Annotated
from langchain.messages import ToolMessage
from langgraph.types import Command

class SupervisorState(AgentState):
    research_findings: str  # passed to writer subagent

@tool
def call_writer_agent(
    query: str,
    runtime: ToolRuntime[None, SupervisorState],
    tool_call_id: Annotated[str, "InjectedToolCallId"],
) -> Command:
    """Delegate writing task, passing research findings as context."""
    findings = runtime.state.get("research_findings", "")
    enriched_query = f"{query}\n\nUse this research context:\n{findings}"

    result = writer_agent.invoke({
        "messages": [{"role": "user", "content": enriched_query}]
    })

    return Command(
        update={
            "messages": [ToolMessage(
                content=result["messages"][-1].text,
                tool_call_id=tool_call_id,
            )],
        }
    )
```

### Async subagents (background tasks)

For long-running tasks that shouldn't block the conversation:

```python
@tool
def start_research_job(topic: str) -> str:
    """Start a background research job. Returns a job ID to check later."""
    job_id = submit_background_job(topic=topic)
    return f"Research job started. Job ID: {job_id}. Check with check_job_status."

@tool
def check_job_status(job_id: str) -> str:
    """Check the status of a background research job."""
    status = get_job_status(job_id)
    return f"Job {job_id}: {status}"  # "pending", "running", "completed", "failed"

@tool
def get_job_result(job_id: str) -> str:
    """Get the result of a completed background research job."""
    result = fetch_job_result(job_id)
    return result

supervisor = create_agent(
    model="openai:gpt-5.4",
    tools=[start_research_job, check_job_status, get_job_result],
    system_prompt=(
        "For long research tasks, start a background job and tell the user you've started it. "
        "When asked for status, check and report. "
        "When asked for results, retrieve and present them."
    ),
)
```

## Pattern 2: Handoffs (state machine)

Tools return `Command` objects to update state, transitioning the agent through workflow
steps. The agent's middleware reads state and adjusts tools + prompt accordingly.

```python
from langchain.agents import AgentState, create_agent
from langchain.agents.middleware import AgentMiddleware, dynamic_prompt, ModelRequest
from langchain.messages import ToolMessage
from langchain.tools import tool, ToolRuntime
from langgraph.types import Command
from typing import Any
from typing_extensions import NotRequired

class SupportState(AgentState):
    current_step: NotRequired[str]  # "intake", "diagnose", "resolve", "escalate"
    issue_type: NotRequired[str]
    customer_name: NotRequired[str]
    severity: NotRequired[str]

@tool
def record_issue(issue_type: str, severity: str, runtime: ToolRuntime[None, SupportState]) -> Command:
    """Record the customer's issue and advance to diagnosis."""
    return Command(
        update={
            "issue_type": issue_type,
            "severity": severity,
            "current_step": "diagnose",
            "messages": [ToolMessage(
                content=f"Issue recorded: {issue_type} ({severity} severity). Moving to diagnosis.",
                tool_call_id=runtime.tool_call_id,
            )],
        }
    )

@tool
def resolve_issue(resolution: str, runtime: ToolRuntime[None, SupportState]) -> Command:
    """Mark the issue as resolved."""
    return Command(
        update={
            "current_step": "resolved",
            "messages": [ToolMessage(
                content=f"Issue resolved: {resolution}",
                tool_call_id=runtime.tool_call_id,
            )],
        }
    )

@tool
def escalate_to_human(reason: str, runtime: ToolRuntime[None, SupportState]) -> Command:
    """Escalate to a human agent."""
    return Command(
        update={
            "current_step": "escalated",
            "messages": [ToolMessage(
                content=f"Escalated to human agent. Reason: {reason}",
                tool_call_id=runtime.tool_call_id,
            )],
        }
    )

class WorkflowMiddleware(AgentMiddleware):
    """Adjusts agent tools and prompt based on current workflow step."""
    state_schema = SupportState

    def before_model(self, state: SupportState, runtime) -> dict[str, Any] | None:
        step = state.get("current_step", "intake")
        # Could dynamically adjust available tools based on step
        # For now, just log
        print(f"Current step: {step}")
        return None

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[record_issue, resolve_issue, escalate_to_human, search_knowledge_base],
    state_schema=SupportState,
    middleware=[WorkflowMiddleware()],
    system_prompt=(
        "You are a customer support agent.\n"
        "Step 1 (intake): Greet the customer and identify their issue using record_issue.\n"
        "Step 2 (diagnose): Search the knowledge base and try to resolve.\n"
        "Step 3: Either resolve with resolve_issue or escalate with escalate_to_human.\n"
        "Always be empathetic and professional."
    ),
)
```

## Pattern 3: Skills (progressive disclosure)

Load specialized prompts and context on-demand. A single agent stays in control but
acquires domain knowledge by calling `load_skill`. Context persists for subsequent turns.

```python
from langchain.tools import tool
from langchain.agents import create_agent

# Skill definitions — each has schema, example queries, tips
SKILLS = {
    "sales": {
        "description": "Sales database queries and revenue analysis",
        "schema": """
Tables:
  orders(id, customer_id, amount, created_at, status)
  customers(id, name, email, segment, created_at)
  products(id, name, category, price)
        """,
        "example_queries": "Total revenue by month, top customers by spend, conversion rates",
        "tips": "Use COALESCE for nullable fields. Status values: 'pending','shipped','delivered','cancelled'",
    },
    "inventory": {
        "description": "Inventory and warehouse management queries",
        "schema": """
Tables:
  products(id, name, sku, category)
  stock(product_id, warehouse_id, quantity, reserved_qty)
  warehouses(id, name, location, capacity)
        """,
        "example_queries": "Low stock alerts, warehouse utilization, reorder recommendations",
        "tips": "available = quantity - reserved_qty. Alert when available < 10.",
    },
    "hr": {
        "description": "Human resources and employee data queries",
        "schema": """
Tables:
  employees(id, name, department, role, hire_date, salary)
  departments(id, name, manager_id, budget)
  attendance(employee_id, date, hours_worked, leave_type)
        """,
        "example_queries": "Headcount by department, average salary, attendance rates",
        "tips": "leave_type values: 'sick','vacation','personal','unpaid'",
    },
}

@tool
def load_skill(skill_name: str) -> str:
    """Load a specialized skill context for a domain.

    Available skills: sales, inventory, hr
    """
    skill = SKILLS.get(skill_name)
    if not skill:
        return f"Unknown skill: '{skill_name}'. Available: {', '.join(SKILLS.keys())}"

    return (
        f"Skill '{skill_name}' loaded.\n\n"
        f"Schema:\n{skill['schema']}\n\n"
        f"Common queries: {skill['example_queries']}\n\n"
        f"Tips: {skill['tips']}"
    )

@tool
def execute_query(sql: str) -> str:
    """Execute a SQL query against the loaded database."""
    # In a real implementation, execute against your database
    return f"Query results for: {sql[:100]}..."

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[load_skill, execute_query],
    system_prompt=(
        "You are a SQL assistant. Available skills: sales, inventory, hr.\n"
        "Always load the appropriate skill before writing SQL queries.\n"
        "If the skill is already loaded (visible in conversation history), don't reload it."
    ),
)

# Turn 1: loads sales skill, then queries
result1 = agent.invoke({"messages": [{"role": "user", "content": "Show me revenue this month"}]})

# Turn 2: skill context is already in conversation history — 2 model calls instead of 3
result2 = agent.invoke({"messages": [{"role": "user", "content": "Now show top 5 customers"}]})
```

## Pattern 4: Router (fan-out)

A routing step classifies input and dispatches to specialist agents in parallel.
Results are synthesised into a combined response.

```python
from langgraph.types import Send
from langgraph.graph import StateGraph, MessagesState, START, END
from langchain.agents import create_agent

# Specialist agents
github_agent = create_agent(model="openai:gpt-5.4", tools=[search_github], name="github_agent")
notion_agent = create_agent(model="openai:gpt-5.4", tools=[search_notion], name="notion_agent")
slack_agent = create_agent(model="openai:gpt-5.4", tools=[search_slack], name="slack_agent")

# Router node — classifies and fans out
def route_query(state: dict) -> list:
    """Classify query and fan out to relevant specialist agents."""
    query = state["messages"][-1].content

    # Could use an LLM classifier here
    agents_to_query = []
    if any(kw in query.lower() for kw in ["code", "pr", "repository", "github"]):
        agents_to_query.append("github_agent")
    if any(kw in query.lower() for kw in ["doc", "notion", "page", "wiki"]):
        agents_to_query.append("notion_agent")
    if any(kw in query.lower() for kw in ["message", "slack", "channel", "#"]):
        agents_to_query.append("slack_agent")

    if not agents_to_query:
        agents_to_query = ["github_agent", "notion_agent", "slack_agent"]  # search all

    return [Send(agent_name, {"messages": state["messages"]}) for agent_name in agents_to_query]

# Synthesis node — combines results
def synthesize(state: dict) -> dict:
    """Combine results from all specialist agents."""
    synthesis_model = init_chat_model("openai:gpt-5.4")
    response = synthesis_model.invoke([
        {"role": "system", "content": "Synthesize the following search results into a coherent answer."},
        *state["messages"],
    ])
    return {"messages": [response]}

# Build the router graph
class RouterState(MessagesState):
    github_result: str
    notion_result: str
    slack_result: str

builder = StateGraph(RouterState)
builder.add_node("github_agent", github_agent)
builder.add_node("notion_agent", notion_agent)
builder.add_node("slack_agent", slack_agent)
builder.add_node("synthesize", synthesize)

builder.add_conditional_edges(START, route_query)  # fan out
builder.add_edge("github_agent", "synthesize")
builder.add_edge("notion_agent", "synthesize")
builder.add_edge("slack_agent", "synthesize")
builder.add_edge("synthesize", END)

router = builder.compile()
```

### Simpler router: single agent wrapping router as tool

```python
@tool("knowledge_router", description="Search across all company knowledge sources in parallel.")
def call_knowledge_router(query: str) -> str:
    """Fan out search to GitHub, Notion, and Slack simultaneously."""
    import asyncio

    async def search_all():
        results = await asyncio.gather(
            github_agent.ainvoke({"messages": [{"role": "user", "content": query}]}),
            notion_agent.ainvoke({"messages": [{"role": "user", "content": query}]}),
            slack_agent.ainvoke({"messages": [{"role": "user", "content": query}]}),
        )
        return [r["messages"][-1].text for r in results]

    github_res, notion_res, slack_res = asyncio.run(search_all())

    return (
        f"GitHub: {github_res[:300]}\n\n"
        f"Notion: {notion_res[:300]}\n\n"
        f"Slack: {slack_res[:300]}"
    )

main_agent = create_agent(
    model="openai:gpt-5.4",
    tools=[knowledge_router],
    system_prompt="Search company knowledge using the knowledge_router tool.",
)
```

## Pattern 5: Custom workflow

Use LangGraph `StateGraph` directly to mix deterministic and agentic nodes with full
control over the execution graph:

```python
from langgraph.graph import StateGraph, MessagesState, START, END
from langgraph.prebuilt import ToolNode, tools_condition
from langchain_openai import ChatOpenAI

model = ChatOpenAI(model="gpt-5.4")

def call_model(state: MessagesState):
    response = model.bind_tools([search, calculator]).invoke(state["messages"])
    return {"messages": [response]}

tool_node = ToolNode([search, calculator])

# Build graph
builder = StateGraph(MessagesState)
builder.add_node("agent", call_model)
builder.add_node("tools", tool_node)
builder.add_edge(START, "agent")
builder.add_conditional_edges("agent", tools_condition)
builder.add_edge("tools", "agent")
graph = builder.compile()

# Embed a create_agent agent as a subgraph
research_agent = create_agent(
    model="openai:gpt-5.4",
    tools=[search, fetch_url],
    name="research_agent",
)

outer_builder = StateGraph(MessagesState)
outer_builder.add_node("research", research_agent)  # embedded as subgraph
outer_builder.add_node("synthesize", synthesize_node)
outer_builder.add_edge(START, "research")
outer_builder.add_edge("research", "synthesize")
outer_builder.add_edge("synthesize", END)
outer_graph = outer_builder.compile()
```

## Tips

- Name agents with `name="snake_case"` — node identifiers can't have spaces.
- When streaming multi-agent output, pass `subgraphs=True` to `.stream()`.
- Subagents run in their own context window; keep their system prompts focused.
- Human-in-the-loop requires a `checkpointer` on the **outermost** agent.
- For context isolation: subagents or router patterns win.
- For repeat tasks: handoffs and skills win (context reuse between turns).
- Mix patterns: a supervisor can delegate to a router which fans out to skill-equipped agents.

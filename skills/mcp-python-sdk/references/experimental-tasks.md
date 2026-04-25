# Experimental Tasks

Sources: `docs/experimental__tasks.md`, `docs/experimental__tasks-server.md`,
`docs/experimental__tasks-client.md`, `docs/experimental__index.md`,
`docs/mcpio__specification__2025-11-25__basic__utilities__tasks.md`

> **Experimental.** Tracks a draft spec. API may change without notice.
> Enable with `server.experimental.enable_tasks()`.

Tasks enable asynchronous MCP operations. Instead of blocking until work
completes, the receiver returns a task reference immediately; the requestor
polls for status and retrieves the result when ready.

## When to use tasks

- Long-running computations (seconds to minutes)
- Operations needing mid-execution user input (elicitation / sampling)
- Batch processing that should not block the caller
- Integration with external job queues
- OAuth flows requiring user browser interaction

Both client→server (common) and server→client (advanced) directions are
supported.

## Task lifecycle

```
working → completed | failed | cancelled
working → input_required → working (elicitation/sampling loop)
```

Terminal states (`completed`, `failed`, `cancelled`) are final.

## Bidirectional flow

**Client → Server** (most common):
```
Client                              Server
  │                                    │
  │── tools/call (task) ──────────────>│  Creates task, returns immediately
  │<── CreateTaskResult ───────────────│
  │                                    │
  │── tasks/get ──────────────────────>│
  │<── {status: "working"} ────────────│
  │                                    │  ... work continues in background ...
  │── tasks/get ──────────────────────>│
  │<── {status: "completed"} ──────────│
  │                                    │
  │── tasks/result ───────────────────>│
  │<── CallToolResult ─────────────────│
```

**Server → Client** (for elicitation/sampling as tasks):
```
Server                              Client
  │                                    │
  │── elicitation/create (task) ──────>│
  │<── CreateTaskResult ───────────────│
  │                                    │
  │── tasks/get ──────────────────────>│
  │<── {status: "completed"} ──────────│
  │                                    │
  │── tasks/result ───────────────────>│
  │<── ElicitResult ───────────────────│
```

## Capabilities

The SDK manages these automatically when you call `enable_tasks()`.

**Server capabilities:**
- `tasks.requests.tools.call` — accepts task-augmented tool calls

**Client capabilities:**
- `tasks.requests.sampling.createMessage` — accepts task-augmented sampling
- `tasks.requests.elicitation.create` — accepts task-augmented elicitation

## Server implementation

### Basic task server

```python
from mcp.server import Server
from mcp.server.experimental.task_context import ServerTaskContext
from mcp.types import CallToolResult, TextContent, Tool, ToolExecution, TASK_REQUIRED

server = Server("my-server")
server.experimental.enable_tasks()  # creates InMemoryTaskStore, registers handlers


@server.list_tools()
async def list_tools():
    return [
        Tool(
            name="process",
            description="Long-running processing task",
            inputSchema={
                "type": "object",
                "properties": {
                    "input": {"type": "string", "description": "Input to process"},
                    "steps": {"type": "integer", "default": 5},
                },
                "required": ["input"],
            },
            execution=ToolExecution(taskSupport=TASK_REQUIRED),
        ),
    ]


@server.call_tool()
async def handle_tool(name, arguments):
    ctx = server.request_context
    ctx.experimental.validate_task_mode(TASK_REQUIRED)  # raises if not task mode

    async def work(task: ServerTaskContext) -> CallToolResult:
        input_text = arguments.get("input", "")
        steps = arguments.get("steps", 5)

        await task.update_status(f"Starting to process: {input_text}")

        for i in range(steps):
            # Check for cancellation in long loops
            if task.is_cancelled:
                return CallToolResult(
                    content=[TextContent(type="text", text="Task was cancelled")]
                )

            await task.update_status(f"Step {i + 1}/{steps}")
            # Simulate work
            import asyncio
            await asyncio.sleep(0.5)

        result = input_text.upper()
        return CallToolResult(
            content=[TextContent(type="text", text=f"Result: {result}")]
        )

    return await ctx.experimental.run_task(work)
```

`run_task()` creates the task, spawns `work` in the background, and returns
`CreateTaskResult` immediately. It auto-completes on return and auto-fails
on exception.

### Tool task support values

| Value | Meaning |
|-------|---------|
| `TASK_REQUIRED` | Must be called as a task; regular call raises error |
| `TASK_OPTIONAL` | Supports both synchronous and task execution |
| `TASK_FORBIDDEN` | Cannot be called as a task (default for all tools) |

### Elicitation within tasks

```python
async def work(task: ServerTaskContext) -> CallToolResult:
    """Ask user for confirmation mid-task."""
    result = await task.elicit(
        message="Are you sure you want to delete these files?",
        requestedSchema={
            "type": "object",
            "properties": {
                "confirm": {"type": "boolean"},
                "reason": {"type": "string"},
            },
            "required": ["confirm"],
        },
    )

    if result.action == "accept" and result.content.get("confirm"):
        # User confirmed — proceed with deletion
        return CallToolResult(
            content=[TextContent(type="text", text="Files deleted successfully")]
        )

    reason = result.content.get("reason", "No reason given") if result.content else "Cancelled"
    return CallToolResult(
        content=[TextContent(type="text", text=f"Deletion cancelled: {reason}")]
    )
```

Task transitions to `input_required` during elicitation and back to `working`
after the user responds.

### Sampling within tasks

```python
from mcp.types import SamplingMessage, TextContent as SamplingTextContent

async def work(task: ServerTaskContext) -> CallToolResult:
    """Use LLM sampling mid-task."""
    await task.update_status("Requesting LLM analysis...")

    result = await task.create_message(
        messages=[
            SamplingMessage(
                role="user",
                content=SamplingTextContent(
                    type="text",
                    text="Write a haiku about Python programming",
                ),
            )
        ],
        max_tokens=100,
    )

    poem = result.content.text if result.content.type == "text" else str(result.content)
    return CallToolResult(
        content=[TextContent(type="text", text=f"Here's your haiku:\n\n{poem}")]
    )
```

### Custom task store (production)

`InMemoryTaskStore` is for development only. Tasks are lost on restart.

For production, implement `TaskStore` backed by a database or distributed
cache:

```python
from mcp.shared.experimental.tasks import TaskStore, TaskNotFoundError
from mcp.types import GetTaskResult, TaskStatus

class RedisTaskStore(TaskStore):
    def __init__(self, redis_url: str):
        import redis.asyncio as aioredis
        self.redis = aioredis.from_url(redis_url)

    async def create_task(self, task_id: str, ttl: int | None = None) -> None:
        data = {"id": task_id, "status": "working", "statusMessage": None}
        await self.redis.setex(
            f"mcp:task:{task_id}",
            ttl or 3600,
            json.dumps(data),
        )

    async def get_task(self, task_id: str) -> GetTaskResult:
        data = await self.redis.get(f"mcp:task:{task_id}")
        if not data:
            raise TaskNotFoundError(task_id)
        task_data = json.loads(data)
        return GetTaskResult(**task_data)

    # ... implement update_task, complete_task, fail_task, cancel_task


server.experimental.enable_tasks(store=RedisTaskStore("redis://localhost"))
```

## Client usage

### Calling a tool as a task

```python
from mcp.client.session import ClientSession
from mcp.types import CallToolResult

async with ClientSession(read, write) as session:
    await session.initialize()

    # Call tool as a task — returns immediately with task reference
    result = await session.experimental.call_tool_as_task(
        "process",
        {"input": "hello world", "steps": 10},
        ttl=60000,  # task TTL in milliseconds
    )
    task_id = result.task.taskId
    print(f"Task created: {task_id}")
```

### Polling for status

```python
# poll_task() respects server's suggested pollInterval and stops at terminal states
async for status in session.experimental.poll_task(task_id):
    print(f"Status: {status.status}")
    if status.statusMessage:
        print(f"  Message: {status.statusMessage}")

    if status.status == "input_required":
        # Handle elicitation required
        # The elicitation_callback on the session handles this automatically
        print("Waiting for user input...")

    # Terminal states: completed, failed, cancelled
    # poll_task() stops automatically at terminal states
```

### Getting the final result

```python
if status.status == "completed":
    final = await session.experimental.get_task_result(task_id, CallToolResult)
    print("Result:", final.content[0].text)
elif status.status == "failed":
    final = await session.experimental.get_task_result(task_id, CallToolResult)
    print("Error:", final.content[0].text)
elif status.status == "cancelled":
    print("Task was cancelled")
```

### Cancelling a task

```python
await session.experimental.cancel_task(task_id)
```

### Full client pattern with error handling

```python
import asyncio
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.types import CallToolResult, ElicitResult


async def handle_elicitation(context, params) -> ElicitResult:
    """Handle elicitation requests during task execution."""
    print(f"\nTask needs input: {params.message}")
    confirm = input("Confirm? (y/n): ").strip().lower() == "y"
    return ElicitResult(action="accept" if confirm else "decline", content={"confirm": confirm})


async def run_long_task():
    params = StdioServerParameters(command="python", args=["task_server.py"])

    async with stdio_client(params) as (read, write):
        async with ClientSession(
            read,
            write,
            elicitation_callback=handle_elicitation,
        ) as session:
            await session.initialize()

            # Start the task
            create_result = await session.experimental.call_tool_as_task(
                "process",
                {"input": "important data", "steps": 5},
                ttl=120000,
            )
            task_id = create_result.task.taskId
            print(f"Started task: {task_id}")

            # Poll until complete
            final_status = None
            async for status in session.experimental.poll_task(task_id):
                print(f"  [{status.status}] {status.statusMessage or ''}")
                final_status = status

            # Get result
            if final_status and final_status.status == "completed":
                result = await session.experimental.get_task_result(task_id, CallToolResult)
                print("Final result:", result.content[0].text)
            else:
                print(f"Task ended with status: {final_status.status if final_status else 'unknown'}")


asyncio.run(run_long_task())
```

### Elicitation callback registration

```python
from mcp.types import ElicitResult

async def handle_elicitation(context, params) -> ElicitResult:
    # Present the elicitation to the user and collect input
    return ElicitResult(action="accept", content={"confirm": True})

async with ClientSession(read, write, elicitation_callback=handle_elicitation) as session:
    ...
```

## Testing task servers

Use `anyio.create_memory_object_stream()` for in-process wiring:

```python
import pytest
import anyio
from mcp.client.session import ClientSession
from mcp.types import CallToolResult


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.mark.anyio
async def test_task_server():
    s2c_send, s2c_recv = anyio.create_memory_object_stream(10)
    c2s_send, c2s_recv = anyio.create_memory_object_stream(10)

    async def run_server():
        await server.run(
            c2s_recv,
            s2c_send,
            server.create_initialization_options(),
        )

    async def run_client():
        async with ClientSession(s2c_recv, c2s_send) as session:
            await session.initialize()

            # Call as task
            result = await session.experimental.call_tool_as_task(
                "process",
                {"input": "test"},
                ttl=10000,
            )
            task_id = result.task.taskId

            # Poll to completion
            final_status = None
            async for status in session.experimental.poll_task(task_id):
                final_status = status

            assert final_status is not None
            assert final_status.status == "completed"

            # Get result
            final = await session.experimental.get_task_result(task_id, CallToolResult)
            assert final.content[0].text == "Result: TEST"

    async with anyio.create_task_group() as tg:
        tg.start_soon(run_server)
        tg.start_soon(run_client)
```

## Overriding default task handlers (v2)

In v2, experimental decorator methods on `ExperimentalHandlers` are removed.
Override defaults via `on_*` kwargs to `enable_tasks()`:

```python
from mcp.server import Server, ServerRequestContext
from mcp.types import GetTaskRequestParams, GetTaskResult


async def custom_get_task(
    ctx: ServerRequestContext,
    params: GetTaskRequestParams,
) -> GetTaskResult:
    """Custom task retrieval — e.g., from a database."""
    task = await my_db.get_task(params.id)
    return GetTaskResult(
        id=task.id,
        status=task.status,
        statusMessage=task.message,
    )


server.experimental.enable_tasks(on_get_task=custom_get_task)
```

## Spec note

The tasks spec lives in
`docs/mcpio__specification__2025-11-25__basic__utilities__tasks.md`. Tasks were
introduced in spec version 2025-11-25. The SDK wraps the low-level protocol
with the `.experimental` namespace on both `Server` and `ClientSession`.

Progress tokens must be unique across all active requests per session. The
same progress token must be used throughout a task's lifetime — do not reset
it after `CreateTaskResult` is returned.

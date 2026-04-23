# Experimental Tasks

Sources: `docs/experimental__tasks.md`, `docs/experimental__tasks-server.md`,
`docs/experimental__tasks-client.md`, `docs/experimental__index.md`,
`docs/mcpio__specification__2025-11-25__basic__utilities__tasks.md`

> **Experimental.** Tracks a draft spec. API may change without notice.

Tasks enable asynchronous MCP operations. Instead of blocking until work
completes, the receiver returns a task reference immediately; the requestor
polls for status and retrieves the result when ready.

## When to use tasks

- Long-running computations (seconds to minutes)
- Operations needing mid-execution user input (elicitation / sampling)
- Batch processing that should not block the caller
- Integration with external job queues

Both client→server and server→client directions are supported.

## Task lifecycle

```
working → completed | failed | cancelled
working → input_required → working (elicitation/sampling loop)
```

Terminal states (`completed`, `failed`, `cancelled`) are final.

## Capabilities

Declare during initialization. The SDK manages this automatically when you call
`enable_tasks()`.

**Server capabilities:**
- `tasks.requests.tools.call` — accepts task-augmented tool calls

**Client capabilities:**
- `tasks.requests.sampling.createMessage` — accepts task-augmented sampling
- `tasks.requests.elicitation.create` — accepts task-augmented elicitation

## Server implementation

```python
from mcp.server import Server
from mcp.server.experimental.task_context import ServerTaskContext
from mcp.types import CallToolResult, TextContent, Tool, ToolExecution, TASK_REQUIRED

server = Server("my-server")
server.experimental.enable_tasks()  # creates InMemoryTaskStore, registers handlers

@server.list_tools()
async def list_tools():
    return [Tool(
        name="process",
        description="Long-running task",
        inputSchema={"type": "object", "properties": {"input": {"type": "string"}}},
        execution=ToolExecution(taskSupport=TASK_REQUIRED),
    )]

@server.call_tool()
async def handle_tool(name, arguments):
    ctx = server.request_context
    ctx.experimental.validate_task_mode(TASK_REQUIRED)  # raises if not task mode

    async def work(task: ServerTaskContext) -> CallToolResult:
        await task.update_status("Processing...")
        # Check cancellation in loops: if task.is_cancelled: ...
        result = arguments.get("input", "").upper()
        return CallToolResult(content=[TextContent(type="text", text=result)])

    return await ctx.experimental.run_task(work)
```

`run_task()` creates the task, spawns `work` in the background, and returns
`CreateTaskResult` immediately. It auto-completes on return and auto-fails on
exception.

### Tool task support values

| Value | Meaning |
|-------|---------|
| `TASK_REQUIRED` | Must be called as a task |
| `TASK_OPTIONAL` | Supports both sync and task |
| `TASK_FORBIDDEN` | Cannot be called as a task (default) |

### Elicitation within tasks

```python
async def work(task: ServerTaskContext):
    result = await task.elicit(
        message="Delete these files?",
        requestedSchema={"type": "object", "properties": {"confirm": {"type": "boolean"}},
                         "required": ["confirm"]},
    )
    if result.action == "accept" and result.content.get("confirm"):
        return CallToolResult(content=[TextContent(type="text", text="Deleted")])
    return CallToolResult(content=[TextContent(type="text", text="Cancelled")])
```

Task transitions to `input_required` during elicitation and back to `working`
after the user responds.

### Sampling within tasks

```python
async def work(task: ServerTaskContext):
    result = await task.create_message(
        messages=[SamplingMessage(role="user",
                                  content=TextContent(type="text", text="Write a haiku"))],
        max_tokens=100,
    )
    return CallToolResult(content=[TextContent(type="text", text=result.content.text)])
```

### Custom task store

`InMemoryTaskStore` is for development only. For production, implement
`TaskStore` and pass it: `server.experimental.enable_tasks(store=my_store)`.

## Client usage

```python
from mcp.client.session import ClientSession
from mcp.types import CallToolResult

async with ClientSession(read, write) as session:
    await session.initialize()

    # Call as task
    result = await session.experimental.call_tool_as_task(
        "process", {"input": "hello"}, ttl=60000
    )
    task_id = result.task.taskId

    # Poll until terminal
    async for status in session.experimental.poll_task(task_id):
        print(f"Status: {status.status} - {status.statusMessage or ''}")
        if status.status == "input_required":
            # Deliver elicitation and wait
            final = await session.experimental.get_task_result(task_id, CallToolResult)
            break

    if status.status == "completed":
        final = await session.experimental.get_task_result(task_id, CallToolResult)

    # Or cancel:
    # await session.experimental.cancel_task(task_id)
```

`poll_task()` respects server's suggested `pollInterval` and stops at terminal
states automatically.

### Elicitation callback

```python
async def handle_elicitation(context, params):
    return ElicitResult(action="accept", content={"confirm": True})

async with ClientSession(read, write, elicitation_callback=handle_elicitation) as session:
    ...
```

### Client as task receiver

For advanced flows (server sends task-augmented elicitation to client), register
`ExperimentalTaskHandlers` on session creation. This is necessary when a server's
task calls `task.elicit_as_task()` instead of the synchronous form.

## Testing task servers

Use `anyio.create_memory_object_stream()` for in-process wiring:

```python
async def test_task():
    s2c_send, s2c_recv = anyio.create_memory_object_stream(10)
    c2s_send, c2s_recv = anyio.create_memory_object_stream(10)

    async def run_server():
        await server.run(c2s_recv, s2c_send, server.create_initialization_options())

    async def run_client():
        async with ClientSession(s2c_recv, c2s_send) as session:
            await session.initialize()
            result = await session.experimental.call_tool_as_task("process", {})
            ...

    async with anyio.create_task_group() as tg:
        tg.start_soon(run_server)
        tg.start_soon(run_client)
```

## Spec note

The tasks spec lives in
`docs/mcpio__specification__2025-11-25__basic__utilities__tasks.md`. Tasks were
introduced in spec version 2025-11-25. The SDK wraps the low-level protocol with
the `.experimental` namespace on both `Server` and `ClientSession`.

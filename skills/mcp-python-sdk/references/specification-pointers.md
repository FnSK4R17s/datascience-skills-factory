# Specification Pointers

Sources: `docs/mcpio__specification__2025-11-25__index.md`,
`docs/mcpio__specification__2025-11-25__basic__index.md`,
`docs/mcpio__docs__learn__versioning.md`,
`docs/mcpio__specification__2025-11-25__basic__utilities__cancellation.md`,
`docs/mcpio__specification__2025-11-25__basic__utilities__ping.md`,
`docs/mcpio__specification__2025-11-25__schema.md`

The MCP specification is the authoritative wire-format contract. The Python SDK
implements it; this file points to the relevant spec documents and summarizes
what each covers. Do not duplicate spec content here — consult the spec when
the SDK behavior is unclear.

## Current spec version

`2025-11-25` is the current protocol version (`YYYY-MM-DD` format). Version is
negotiated during `initialize` — both sides agree on a single version for the
session. Backwards-compatible changes do not bump the version.

## Spec document map

| Doc | What it covers |
|-----|----------------|
| `docs/mcpio__specification__2025-11-25__index.md` | Spec overview, JSON-RPC 2.0 message types, `_meta`, icons, security overview |
| `docs/mcpio__specification__2025-11-25__basic__index.md` | Base protocol, message types, JSON Schema usage, auth overview |
| `docs/mcpio__specification__2025-11-25__architecture__index.md` | Client-host-server architecture, capability negotiation |
| `docs/mcpio__specification__2025-11-25__basic__lifecycle.md` | Initialize/operation/shutdown phases; version negotiation |
| `docs/mcpio__specification__2025-11-25__basic__transports.md` | stdio and Streamable HTTP wire format |
| `docs/mcpio__specification__2025-11-25__basic__authorization.md` | OAuth 2.1, PKCE, PRM, token passthrough prohibition |
| `docs/mcpio__specification__2025-11-25__server__tools.md` | `tools/list`, `tools/call`, tool schemas |
| `docs/mcpio__specification__2025-11-25__server__resources.md` | `resources/list`, `resources/read`, direct vs template URIs |
| `docs/mcpio__specification__2025-11-25__server__prompts.md` | `prompts/list`, `prompts/get` |
| `docs/mcpio__specification__2025-11-25__server__utilities__completion.md` | Argument autocompletion |
| `docs/mcpio__specification__2025-11-25__server__utilities__logging.md` | `notifications/message`, 8 RFC-5424 log levels, `logging/setLevel` |
| `docs/mcpio__specification__2025-11-25__server__utilities__pagination.md` | Cursor-based pagination for list operations |
| `docs/mcpio__specification__2025-11-25__client__sampling.md` | `sampling/createMessage` — server requests LLM completion |
| `docs/mcpio__specification__2025-11-25__client__elicitation.md` | `elicitation/create` — form and URL modes |
| `docs/mcpio__specification__2025-11-25__client__roots.md` | `roots/list`, `notifications/roots/list_changed` |
| `docs/mcpio__specification__2025-11-25__basic__utilities__cancellation.md` | `notifications/cancelled` — in-flight request cancellation |
| `docs/mcpio__specification__2025-11-25__basic__utilities__ping.md` | `ping` request — connection liveness check |
| `docs/mcpio__specification__2025-11-25__basic__utilities__progress.md` | `progressToken`, `notifications/progress` |
| `docs/mcpio__specification__2025-11-25__basic__utilities__tasks.md` | Tasks (experimental) — deferred result retrieval |
| `docs/mcpio__specification__2025-11-25__schema.md` | Full TypeScript schema (authoritative) |
| `docs/mcpio__specification__2025-11-25__changelog.md` | Changes from 2025-06-18 to 2025-11-25 |

## Key spec constraints (frequently hit in practice)

**Lifecycle is mandatory**: Client sends `initialize` request, server responds,
client sends `notifications/initialized`. No other operations before this
completes. Source: `docs/mcpio__specification__2025-11-25__basic__lifecycle.md`.

**Capabilities at init only**: Declare all capabilities (tools, resources,
prompts, sampling, elicitation, roots, tasks) in `initialize`. They are fixed
for the session; you cannot add them later.

**stdio stdout rule**: In stdio transport, server MUST NOT write non-JSON-RPC to
stdout. Logging goes to stderr. Source: `docs/mcpio__specification__2025-11-25__basic__transports.md`.

**Authorization is HTTP-only**: OAuth 2.1 authorization applies to HTTP-based
transports. stdio servers SHOULD retrieve credentials from environment instead.

**Cancellation vs tasks/cancel**: Use `notifications/cancelled` for regular
in-flight requests. For task-augmented requests, use `tasks/cancel` instead.

**Cursor-based pagination**: List operations use opaque cursors. Clients pass
`cursor` from the previous response's `nextCursor` field. An absent `nextCursor`
means the last page.

**Progress tokens**: Must be unique across all active requests per session. The
same token must be used throughout a task's lifetime (not reset after
`CreateTaskResult` is returned).

## JSON Schema dialect

MCP uses JSON Schema 2020-12 by default (no `$schema` field present). Schemas
may declare a different dialect via `$schema`. Implementations must support at
least 2020-12.

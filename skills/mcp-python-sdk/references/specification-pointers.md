# Specification Pointers

Sources: `docs/mcpio__specification__2025-11-25__index.md`,
`docs/mcpio__specification__2025-11-25__basic__index.md`,
`docs/mcpio__docs__learn__versioning.md`,
`docs/mcpio__specification__2025-11-25__basic__utilities__cancellation.md`,
`docs/mcpio__specification__2025-11-25__basic__utilities__ping.md`,
`docs/mcpio__specification__2025-11-25__schema.md`

The MCP specification is the authoritative wire-format contract. The Python SDK
implements it; this file points to the relevant spec documents and summarizes
what each covers. Consult the spec when SDK behavior is unclear.

## Current spec version

`2025-11-25` is the current protocol version (YYYY-MM-DD format). Version is
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
| `docs/mcpio__specification__2025-11-25__server__tools.md` | `tools/list`, `tools/call`, tool schemas, outputSchema |
| `docs/mcpio__specification__2025-11-25__server__resources.md` | `resources/list`, `resources/read`, direct vs template URIs |
| `docs/mcpio__specification__2025-11-25__server__prompts.md` | `prompts/list`, `prompts/get` |
| `docs/mcpio__specification__2025-11-25__server__utilities__completion.md` | Argument autocompletion (`completions/complete`) |
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

### Lifecycle is mandatory

Client sends `initialize` request → server responds → client sends
`notifications/initialized`. No other operations before this completes.
Sending tool calls before `initialized` causes protocol errors.

Source: `docs/mcpio__specification__2025-11-25__basic__lifecycle.md`

### Capabilities at init only

Declare all capabilities (tools, resources, prompts, sampling, elicitation,
roots, tasks) in `initialize`. They are fixed for the session; you cannot add
them later. FastMCP infers capabilities automatically from registered handlers.

### stdio stdout rule

In stdio transport, the server MUST NOT write non-JSON-RPC content to stdout.
Any `print()` call corrupts the stream silently. Log to stderr instead.

Source: `docs/mcpio__specification__2025-11-25__basic__transports.md`

### Authorization is HTTP-only

OAuth 2.1 authorization applies to HTTP-based transports. stdio servers SHOULD
retrieve credentials from environment variables instead.

### Cancellation vs tasks/cancel

Use `notifications/cancelled` for regular in-flight requests. For
task-augmented requests, use `tasks/cancel` instead.

### Cursor-based pagination

List operations use opaque cursors. Clients pass `cursor` from the previous
response's `nextCursor` field. An absent `nextCursor` means the last page.
Do not parse or construct cursor values.

### Progress tokens

Must be unique across all active requests per session. The same token must be
used throughout a task's lifetime — do not reset it after `CreateTaskResult`
is returned.

### Token passthrough prohibition

MCP servers MUST NOT forward tokens received from clients to upstream APIs.
Obtain separate tokens for upstream calls. Forwarding tokens enables confused
deputy attacks.

Source: `docs/mcpio__specification__2025-11-25__basic__authorization.md`

### Tool name format

Tool names must match `^[a-zA-Z0-9_-]{1,64}$`. Alphanumerics, underscores,
and hyphens only. No spaces or other special characters.

## JSON Schema dialect

MCP uses JSON Schema 2020-12 by default (no `$schema` field present in the
schemas). Schemas may declare a different dialect via `$schema`.
Implementations must support at least JSON Schema 2020-12.

FastMCP generates JSON Schema 2020-12 automatically from Python type
annotations using Pydantic.

## Protocol version history

| Version | Notable additions |
|---------|-------------------|
| 2025-11-25 | Icons, URL elicitation, tasks (experimental), tool calling in sampling, incremental scope consent, OAuth Client ID Metadata Documents |
| 2025-06-18 | Structured tool output (outputSchema), `_meta` on results, elicitation |
| 2024-11-05 | Initial release with stdio and HTTP+SSE transports |

The current SDK (`v1.x`) targets the 2025-11-25 spec. The v2 pre-alpha also
targets 2025-11-25 with additional API improvements.

## Key JSON-RPC error codes

| Code | Meaning | Common cause |
|------|---------|--------------|
| `-32700` | Parse error | Invalid JSON |
| `-32600` | Invalid request | Malformed JSON-RPC |
| `-32601` | Method not found | Handler not registered / capability not declared |
| `-32602` | Invalid params | Capability mismatch, wrong field names |
| `-32603` | Internal error | Server-side exception |
| `-32042` | URL elicitation required | Tool raised `UrlElicitationRequiredError` |

`-32602` is the most common error during development — usually means a
capability was not declared (e.g., server tried to use sampling but client
didn't declare it), or field names are wrong (v1 camelCase vs v2 snake_case).

# Authorization

Sources: `docs/mcpio__specification__2025-11-25__basic__authorization.md`,
`docs/mcpio__docs__tutorials__security__authorization.md`,
`docs/mcpio__docs__tutorials__security__security_best_practices.md`

## Scope

Authorization applies at the transport level for HTTP-based transports only.

- **HTTP transports** — SHOULD implement this OAuth 2.1 spec.
- **stdio transports** — SHOULD NOT follow this spec; retrieve credentials
  from the environment instead.
- **Custom transports** — MUST follow established security practices for
  their protocol.

Authorization is optional for MCP implementations overall. When supported, it
is based on OAuth 2.1 plus several companion RFCs.

## Standards used

- OAuth 2.1 (draft-ietf-oauth-v2-1) — core authorization framework
- RFC 8414 — OAuth 2.0 Authorization Server Metadata discovery
- RFC 7591 — Dynamic Client Registration (optional)
- RFC 9728 — OAuth 2.0 Protected Resource Metadata (required for servers)
- draft-ietf-oauth-client-id-metadata-document — Client ID Metadata Documents
- RFC 8707 — Resource Indicators for OAuth 2.0 (required, `resource` param)

## Roles

- **MCP server** acts as OAuth 2.1 resource server — validates tokens and
  serves protected resources.
- **MCP client** acts as OAuth 2.1 client — obtains tokens and includes them
  in requests.
- **Authorization server** — issues tokens; may be co-hosted or separate.

## Discovery flow

1. Client makes unauthenticated request to the MCP server.
2. Server returns `401 Unauthorized` with `WWW-Authenticate` header.
3. Client extracts `resource_metadata` URL from the header.
4. Client fetches the Protected Resource Metadata document (RFC 9728).
5. Metadata document contains `authorization_servers` field.
6. Client discovers the authorization server's metadata at well-known URIs:
   - Try `/.well-known/oauth-authorization-server/<path>` first.
   - Try `/.well-known/openid-configuration/<path>` second.
   - Try `<path>/.well-known/openid-configuration` third.
7. Client completes the OAuth 2.1 authorization flow.
8. Client includes `Authorization: Bearer <token>` on all subsequent requests.

Servers MUST serve Protected Resource Metadata at a well-known URI or include
`resource_metadata` in `WWW-Authenticate` headers. Both discovery paths must
be supported.

## Authorization flow (summary)

```
Client → MCP Server: unauthenticated request
MCP Server → Client: 401 + WWW-Authenticate: Bearer resource_metadata="..."
Client → MCP Server: GET resource_metadata URI
MCP Server → Client: { authorization_servers: [...] }
Client → Auth Server: GET authorization server metadata
Auth Server → Client: metadata (endpoints, PKCE support, etc.)

[Client registration — one of:]
  a. Client ID Metadata Documents (preferred when no prior relationship)
  b. Pre-registration (existing relationship)
  c. Dynamic Client Registration (RFC 7591, fallback)

Client → Browser: open authorization URL + code_challenge + resource=<server URI>
Browser → Auth Server: user authorizes
Auth Server → Browser: redirect with code
Browser → Client: code callback
Client → Auth Server: token request + code_verifier + resource=<server URI>
Auth Server → Client: access token (+ refresh token)
Client → MCP Server: MCP request + Authorization: Bearer <token>
```

## Client registration approaches

Priority order when all are available:
1. Pre-registered client info for the specific server.
2. Client ID Metadata Documents (if auth server advertises
   `client_id_metadata_document_supported: true`).
3. Dynamic Client Registration (via `registration_endpoint`).
4. Prompt user to enter client info manually.

**Client ID Metadata Documents:** Client uses an HTTPS URL as its `client_id`.
Auth server fetches metadata from that URL and validates `redirect_uris`.
Metadata must include `client_id`, `client_name`, `redirect_uris`.

## Resource parameter (RFC 8707) — mandatory

Clients MUST include the `resource` parameter in both authorization and token
requests, set to the canonical URI of the MCP server:

```
&resource=https%3A%2F%2Fmcp.example.com
```

Canonical URI rules: lowercase scheme and host, no fragment, no trailing
slash (unless semantically required).

## PKCE — mandatory

Clients MUST implement PKCE (S256 method). Clients MUST verify
`code_challenge_methods_supported` in auth server metadata — if absent, MUST
refuse to proceed (no PKCE = no authorization).

## Token usage and validation

Clients:
- MUST send tokens as `Authorization: Bearer <token>` header.
- MUST NOT include tokens in URI query strings.
- MUST NOT send tokens to any server other than the one that issued them.

Servers:
- MUST validate tokens before processing any request.
- MUST verify the token was issued specifically for this server (audience
  validation, RFC 8707).
- MUST return 401 for invalid or expired tokens, 403 for insufficient scope.
- MUST NOT accept tokens intended for other resources.
- MUST NOT forward received tokens to upstream APIs — obtain separate tokens.

## Scope selection (client strategy)

1. Use `scope` from `WWW-Authenticate` header if present.
2. Otherwise, use all scopes from `scopes_supported` in Protected Resource
   Metadata (omit `scope` param if `scopes_supported` is undefined).

## Scope errors (runtime)

Server returns 403 with `WWW-Authenticate: Bearer error="insufficient_scope",
scope="required_scope1 required_scope2"`.

Client should:
1. Parse required scopes from the challenge.
2. Initiate step-up authorization flow for the new scopes.
3. Retry the original request.
4. Treat as permanent failure after a few retries.

## Security requirements

- All auth server endpoints MUST use HTTPS.
- All redirect URIs MUST be `localhost` or HTTPS.
- Servers MUST validate `Origin` header (DNS rebinding prevention).
- Short-lived access tokens; rotate refresh tokens for public clients.
- Servers MUST reject tokens without them in the audience claim.
- Token passthrough (forwarding received tokens upstream) is explicitly
  forbidden — it enables confused deputy attacks.

# MCP Authorization

Authorization in MCP applies only to HTTP-based transports. The MCP
specification (2025-11-25) defines an OAuth 2.1 profile for server-managed
authorization. This reference describes the problem, the protocol shape, and
the known traps. Implementation is left to the agent reading this file.

## When authorization matters

- Your MCP server is publicly reachable (not behind a VPN or localhost).
- Multiple users or tenants share a single server instance and must have
  isolated access to tools/resources.
- The tools you expose act on sensitive data or perform privileged operations.
- Clients are third-party applications, not only your own.

For single-user local stdio servers, OS process isolation is the security
boundary. No bearer tokens are needed.

## The protocol story

The MCP authorization spec is built on RFC 9728 (OAuth 2.0 Protected Resource
Metadata) and OAuth 2.1. Key elements:

1. **Metadata discovery.** The server exposes `/.well-known/oauth-authorization-server`
   (or is pointed to an external authorization server). Clients fetch this to
   learn the authorization endpoint, token endpoint, and supported flows.

2. **Authorization server.** May be the MCP server itself or a separate IdP
   (Entra ID, Auth0, Cognito, etc.). The MCP server declares which AS it trusts
   via the metadata document.

3. **Client registration.** Clients register with the AS to obtain a `client_id`.
   The spec allows dynamic registration (RFC 7591) but also manual out-of-band
   registration.

4. **Authorization code flow with PKCE.** The user authenticates through the
   AS. The AS issues an authorization code; the client exchanges it for access
   and refresh tokens.

5. **Bearer token.** The client includes the access token in every HTTP request:
   `Authorization: Bearer <token>`.

6. **Resource server validation.** The MCP server validates the token on every
   request — signature check, expiry, audience claim, and scope.

## What the Python SDK provides

The SDK (as of the 2025-11-25 era) provides:

- `mcp.server.auth` — helpers for building the authorization server metadata
  endpoint and for token validation middleware.
- `OAuthServerProvider` protocol — implement this to integrate an external AS.
- `RequireAuth` / scope checking utilities for FastMCP route protection.

The SDK does NOT provide a full, production-ready OAuth authorization server.
It provides the glue layer. For the AS itself, use an established library
(e.g. `authlib`) or delegate to an external IdP.

## Token validation pattern

```python
from mcp.server.auth import OAuthServerProvider, TokenVerifier

class MyTokenVerifier(TokenVerifier):
    async def verify_token(self, token: str) -> TokenInfo | None:
        # Validate JWT signature, expiry, audience
        try:
            payload = jwt.decode(token, PUBLIC_KEY, algorithms=["RS256"])
            return TokenInfo(
                client_id=payload["client_id"],
                scopes=payload.get("scope", "").split(),
            )
        except jwt.JWTError:
            return None  # Invalid token → 401
```

Register the verifier when constructing the FastMCP app or attaching to the
Streamable HTTP transport.

## Scope enforcement

Define scopes that map to your tool/resource permissions:

```python
@mcp.tool(required_scopes=["data:read"])
async def read_data(query: str) -> str:
    ...

@mcp.tool(required_scopes=["data:write"])
async def write_data(key: str, value: str) -> None:
    ...
```

The SDK checks that the verified token carries the required scopes before
dispatching to the handler. Missing scopes → `McpError` with an authorization
error code.

## Known traps

**Audience mismatch.** JWT `aud` claim must match the server's resource
indicator. Many IdPs default to the client ID as the audience; the MCP spec
wants the resource URI. Configure the AS to issue tokens with the correct `aud`.

**Refresh token handling.** The MCP SDK does not handle token refresh on behalf
of the client. Clients must implement the refresh flow themselves and reconnect
if a session expires mid-operation.

**PKCE is mandatory.** OAuth 2.1 drops implicit flow and requires PKCE for
authorization code flow. Clients that implement the older authorization code
flow without PKCE will be rejected by a conforming AS.

**Dynamic vs. static registration.** Dynamic client registration (RFC 7591)
is convenient but requires the AS to support it. Many enterprise IdPs only
support static registration. Decide early which model you support — it affects
how clients onboard.

**Localhost exception.** RFC 8252 allows authorization code redirect to
`http://localhost` for native apps. Some AS implementations reject plain HTTP
even for localhost. Test your AS's behavior with local clients.

## Where to go for authoritative detail

The canonical source is the MCP specification authorization section — use the
`claude-docs` skill or search `modelcontextprotocol.io/specification` for the
current authorization spec. The spec evolves; do not hardcode the 2025-11-25
version as "current" without verifying.

For the OAuth 2.1 baseline, the IETF draft `draft-ietf-oauth-v2-1` is the
reference. For PKCE, RFC 7636.

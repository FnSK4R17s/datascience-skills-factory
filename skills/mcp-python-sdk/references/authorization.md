# Authorization

Sources: `docs/mcpio__specification__2025-11-25__basic__authorization.md`,
`docs/mcpio__docs__tutorials__security__authorization.md`,
`docs/mcpio__docs__tutorials__security__security_best_practices.md`,
`docs/README.md`

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

## Server-side OAuth setup (FastMCP / resource server)

The server implements `TokenVerifier` to validate incoming bearer tokens:

```python
from pydantic import AnyHttpUrl
from mcp.server.auth.provider import AccessToken, TokenVerifier
from mcp.server.auth.settings import AuthSettings
from mcp.server.fastmcp import FastMCP


class SimpleTokenVerifier(TokenVerifier):
    """Token verifier that validates against a hardcoded set of tokens."""

    async def verify_token(self, token: str) -> AccessToken | None:
        """Return AccessToken if valid, None if invalid."""
        # In production: verify JWT signature, check expiry, validate audience
        known_tokens = {
            "valid-token-123": AccessToken(
                token="valid-token-123",
                client_id="my-client",
                scopes=["read", "write"],
                expires_at=None,  # or Unix timestamp
            )
        }
        return known_tokens.get(token)


# Create FastMCP as a Resource Server
mcp = FastMCP(
    "Weather Service",
    json_response=True,
    # Token verifier validates incoming bearer tokens
    token_verifier=SimpleTokenVerifier(),
    # AuthSettings exposes RFC 9728 Protected Resource Metadata
    auth=AuthSettings(
        issuer_url=AnyHttpUrl("https://auth.example.com"),       # AS URL
        resource_server_url=AnyHttpUrl("http://localhost:3001"), # this server's URL
        required_scopes=["read"],
    ),
)


@mcp.tool()
async def get_weather(city: str = "London") -> dict[str, str]:
    """Get weather data — requires authentication."""
    return {
        "city": city,
        "temperature": "22",
        "condition": "Partly cloudy",
    }


if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="0.0.0.0", port=3001)
```

### JWT token verifier (production pattern)

```python
import time
from mcp.server.auth.provider import AccessToken, TokenVerifier

class JWTTokenVerifier(TokenVerifier):
    def __init__(self, public_key: str, audience: str):
        self.public_key = public_key
        self.audience = audience

    async def verify_token(self, token: str) -> AccessToken | None:
        try:
            import jwt
            payload = jwt.decode(
                token,
                self.public_key,
                algorithms=["RS256"],
                audience=self.audience,
            )
            # Validate audience matches this server's URL (RFC 8707)
            if payload.get("aud") != self.audience:
                return None
            if payload.get("exp", 0) < time.time():
                return None

            return AccessToken(
                token=token,
                client_id=payload.get("client_id", ""),
                scopes=payload.get("scope", "").split(),
                expires_at=payload.get("exp"),
            )
        except Exception:
            return None
```

## Discovery flow

How the MCP client finds the authorization server:

```
Client → MCP Server: unauthenticated request
MCP Server → Client: 401 Unauthorized
                      WWW-Authenticate: Bearer resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource"

Client → MCP Server: GET /.well-known/oauth-protected-resource
MCP Server → Client: {
                        "resource": "https://mcp.example.com",
                        "authorization_servers": ["https://auth.example.com"],
                        "scopes_supported": ["read", "write"]
                      }

Client → Auth Server: GET /.well-known/oauth-authorization-server
Auth Server → Client: {
                         "issuer": "https://auth.example.com",
                         "authorization_endpoint": "https://auth.example.com/authorize",
                         "token_endpoint": "https://auth.example.com/token",
                         "code_challenge_methods_supported": ["S256"],
                         ...
                       }
```

Servers MUST serve Protected Resource Metadata at a well-known URI. Both
discovery paths must be supported.

## Authorization flow (full sequence)

```
[Discovery — see above]

[Client registration — one of:]
  a. Client ID Metadata Documents (preferred for new relationships)
  b. Pre-registration (existing relationship)
  c. Dynamic Client Registration (RFC 7591, fallback)

Client → Browser: open authorization URL
                   ?response_type=code
                   &client_id=https://my-client.example.com  (or pre-registered ID)
                   &redirect_uri=http://localhost:3000/callback
                   &scope=read+write
                   &state=random-state
                   &code_challenge=BASE64URL(SHA256(code_verifier))  (PKCE)
                   &code_challenge_method=S256
                   &resource=https://mcp.example.com  (RFC 8707 — REQUIRED)

Browser → Auth Server: user authorizes
Auth Server → Browser: redirect to callback
                        ?code=auth-code&state=random-state

Client → Auth Server: POST /token
                        grant_type=authorization_code
                        &code=auth-code
                        &redirect_uri=...
                        &code_verifier=...  (PKCE verifier)
                        &resource=https://mcp.example.com  (RFC 8707 — REQUIRED)

Auth Server → Client: {
                         "access_token": "...",
                         "token_type": "Bearer",
                         "expires_in": 3600,
                         "refresh_token": "..."
                       }

Client → MCP Server: MCP request
                      Authorization: Bearer <access_token>
```

## Client-side OAuth (connecting to protected servers)

```python
import asyncio
from urllib.parse import parse_qs, urlparse

import httpx
from pydantic import AnyUrl

from mcp import ClientSession
from mcp.client.auth import OAuthClientProvider, TokenStorage
from mcp.client.streamable_http import streamable_http_client
from mcp.shared.auth import OAuthClientInformationFull, OAuthClientMetadata, OAuthToken


class FileTokenStorage(TokenStorage):
    """Persist tokens to a file for reuse across sessions."""

    def __init__(self, path: str):
        self.path = path

    async def get_tokens(self) -> OAuthToken | None:
        import json, os
        if not os.path.exists(self.path):
            return None
        with open(self.path) as f:
            data = json.load(f)
        return OAuthToken(**data)

    async def set_tokens(self, tokens: OAuthToken) -> None:
        import json
        with open(self.path, "w") as f:
            json.dump(tokens.model_dump(), f)

    async def get_client_info(self) -> OAuthClientInformationFull | None:
        return None

    async def set_client_info(self, client_info: OAuthClientInformationFull) -> None:
        pass  # optionally persist client_info too


async def handle_redirect(auth_url: str) -> None:
    print(f"\nOpen this URL in your browser:\n{auth_url}\n")


async def handle_callback() -> tuple[str, str | None]:
    callback_url = input("Paste the callback URL after authorization: ")
    params = parse_qs(urlparse(callback_url).query)
    return params["code"][0], params.get("state", [None])[0]


async def main():
    oauth_auth = OAuthClientProvider(
        server_url="http://localhost:8001",
        client_metadata=OAuthClientMetadata(
            client_name="My MCP Client",
            redirect_uris=[AnyUrl("http://localhost:3000/callback")],
            grant_types=["authorization_code", "refresh_token"],
            response_types=["code"],
            scope="read write",
        ),
        storage=FileTokenStorage("/tmp/mcp-tokens.json"),
        redirect_handler=handle_redirect,
        callback_handler=handle_callback,
    )

    async with httpx.AsyncClient(auth=oauth_auth, follow_redirects=True) as client:
        async with streamable_http_client(
            "http://localhost:8001/mcp",
            http_client=client,
        ) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                tools = await session.list_tools()
                print("Authenticated! Tools:", [t.name for t in tools.tools])


asyncio.run(main())
```

## Client registration approaches

Priority order when all are available:

1. **Pre-registered client info** for the specific server.
2. **Client ID Metadata Documents** (if auth server advertises
   `client_id_metadata_document_supported: true`). Client uses an HTTPS URL
   as its `client_id`; auth server fetches metadata from that URL.
3. **Dynamic Client Registration** (via `registration_endpoint`, RFC 7591).
4. **Manual prompt** — ask user to enter client info.

### Client ID Metadata Document example

The client hosts metadata at an HTTPS URL used as `client_id`:

```json
{
  "client_id": "https://my-app.example.com/mcp-client",
  "client_name": "My MCP Client",
  "redirect_uris": ["https://my-app.example.com/oauth/callback"],
  "grant_types": ["authorization_code", "refresh_token"],
  "response_types": ["code"],
  "scope": "read write"
}
```

## Resource parameter (RFC 8707) — mandatory

Clients MUST include the `resource` parameter in both authorization and token
requests, set to the canonical URI of the MCP server:

```
&resource=https%3A%2F%2Fmcp.example.com
```

**Canonical URI rules:**
- Lowercase scheme and host
- No fragment
- No trailing slash (unless semantically required)

The authorization server MUST bind the issued token to this resource. Tokens
are audience-bound and cannot be used on other servers.

## PKCE — mandatory

Clients MUST implement PKCE with S256 method. Clients MUST verify
`code_challenge_methods_supported` in auth server metadata — if absent, MUST
refuse to proceed (no PKCE = no authorization).

```python
import hashlib
import base64
import secrets

# Generate PKCE pair
code_verifier = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b"=").decode()
code_challenge = base64.urlsafe_b64encode(
    hashlib.sha256(code_verifier.encode()).digest()
).rstrip(b"=").decode()
```

## Token usage and validation

### Client rules

- MUST send tokens as `Authorization: Bearer <token>` header.
- MUST NOT include tokens in URI query strings.
- MUST NOT send tokens to any server other than the one that issued them.

### Server rules

- MUST validate tokens before processing any request.
- MUST verify the token was issued specifically for this server (audience
  validation, RFC 8707).
- MUST return 401 for invalid or expired tokens.
- MUST return 403 for insufficient scope.
- MUST NOT accept tokens intended for other resources.
- **MUST NOT forward received tokens to upstream APIs** — this enables confused
  deputy attacks. Obtain separate tokens for upstream calls.

## Scope errors (runtime)

Server returns 403 with:
```
WWW-Authenticate: Bearer error="insufficient_scope",
                         scope="required_scope1 required_scope2"
```

Client should:
1. Parse required scopes from the challenge.
2. Initiate step-up authorization for the new scopes.
3. Retry the original request.
4. Treat as permanent failure after a few retries.

## Scope selection (client strategy)

1. Use `scope` from `WWW-Authenticate` header if present.
2. Otherwise, use all scopes from `scopes_supported` in Protected Resource
   Metadata (omit `scope` param if `scopes_supported` is undefined).

## Security requirements

- All auth server endpoints MUST use HTTPS.
- All redirect URIs MUST be `localhost` or HTTPS.
- Servers MUST validate `Origin` header (DNS rebinding prevention).
- Short-lived access tokens; rotate refresh tokens for public clients.
- Servers MUST reject tokens without them in the audience claim.
- **Token passthrough (forwarding received tokens upstream) is explicitly
  forbidden** — it enables confused deputy attacks.
- Do not log tokens or include them in error messages.

## stdio servers — use environment instead

For stdio transport, use environment variables for credentials:

```python
import os
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("My Server")

@mcp.tool()
async def call_api(query: str) -> str:
    """Call external API using server-side credentials."""
    api_key = os.environ["MY_API_KEY"]  # from launch config env
    # Use api_key to call external API
    return f"Result for {query}"
```

In Claude Desktop config:
```json
{
  "mcpServers": {
    "my-server": {
      "command": "python",
      "args": ["/path/to/server.py"],
      "env": {"MY_API_KEY": "..."}
    }
  }
}
```

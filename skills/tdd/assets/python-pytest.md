# Python (pytest) — TDD adapter

> Verified against pytest 9.0.3, pytest-asyncio 1.3.0, httpx 0.28.1, fastapi 0.136.0 (April 2026).

## Canonical command

```bash
pytest -q --tb=short
```

`-q` quiet; `--tb=short` minimal traceback. Run from repo root with a `tests/` directory next to `src/` (or wherever the project keeps source).

Subset:
```bash
pytest tests/test_login.py -q --tb=short
pytest tests/test_login.py::test_returns_401 -q
```

## Minimal failing test

`tests/test_calc.py`:
```python
from src.calc import add

def test_add_returns_sum():
    assert add(2, 3) == 5
```

`src/calc.py` does not exist yet → `pytest` exits 2 with `ModuleNotFoundError: No module named 'src.calc'`. That's the RED you want.

Make it pass:
```python
# src/calc.py
def add(a, b):
    return a + b
```

`pytest` → 1 passed, exit 0.

## Async tests (pytest-asyncio)

Set asyncio mode once in `pytest.ini` (or in `pyproject.toml` under `[tool.pytest.ini_options]`):
```ini
[pytest]
asyncio_mode = auto
```

Then mark tests:
```python
import pytest

@pytest.mark.asyncio
async def test_fetches_value():
    async def fetch():
        return 42
    assert await fetch() == 42
```

With `asyncio_mode = auto`, the `@pytest.mark.asyncio` decorator is technically unnecessary, but keeping it is explicit and works.

## FastAPI — sync via `TestClient`

```python
# tests/test_api.py
from fastapi.testclient import TestClient
from src.api import app

client = TestClient(app)

def test_health_returns_ok():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
```

Use this for endpoints that don't need to exercise async behavior in the test itself. `TestClient` wraps the ASGI app and runs the event loop internally.

## FastAPI — async via `httpx.AsyncClient` + `ASGITransport`

When the test must be async (concurrent calls, asyncio fixtures, async DB clients):

```python
import pytest
from httpx import AsyncClient, ASGITransport
from src.api import app

@pytest.mark.asyncio
async def test_health_async():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.get("/health")
    assert r.status_code == 200
```

`ASGITransport` lets `httpx.AsyncClient` talk to a FastAPI app in-process — no server needed, no real network.

## Idioms worth knowing

- **Test name is the spec.** `test_<subject>_<condition>_<expected>` — `test_login_returns_401_for_expired_jwt`. The name reads like a sentence.
- **One logical assertion per test.** Group related asserts when they verify the same observable behavior; split them when they verify independent behaviors.
- **Don't write all tests up front.** One failing test → one minimum impl → one more failing test. (See [SKILL.md](../SKILL.md) anti-horizontal-slice.)
- **Test through the public interface.** No reaching into internal modules to inspect state. If `client.post('/login')` returns 401 with the right body, you don't care which middleware caught the expiry.

## Dev deps

```bash
# pip
pip install pytest pytest-asyncio httpx
# uv
uv add --dev pytest pytest-asyncio httpx
```

For FastAPI projects also add `fastapi` as a runtime dep. `httpx` is the only TestClient backend supported by FastAPI from v0.110+.

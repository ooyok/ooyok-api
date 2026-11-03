# The client argument is automatically supplied by pytest from the client fixture in conftest.py 
from httpx import AsyncClient


async def test_health_returns_ok(client: AsyncClient) -> None:
    resp = await client.get("/health")

    assert resp.status_code == 200
    assert resp.headers["content-type"] == "application/json"
    assert resp.json()["status"] == "ok"


async def test_health_reports_deployed_version(client: AsyncClient) -> None:
    # The version lets a smoke test confirm which build is serving traffic.
    resp = await client.get("/health")

    assert resp.json()["version"] == "test-sha"


async def test_health_requires_no_auth(client: AsyncClient) -> None:
    # Uptime checks and Cloud Run call /health without a token; keep it public once auth exists.
    resp = await client.get("/health", headers={})

    assert resp.status_code == 200

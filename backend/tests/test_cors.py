import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_cors_preflight_options(client: AsyncClient):
    """Verifies OPTIONS preflight request headers for allowed origins."""
    headers = {
        "Origin": "http://localhost:3000",
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "authorization,content-type",
    }
    response = await client.options("/api/auth/login", headers=headers)
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:3000"
    assert "POST" in response.headers.get("access-control-allow-methods", "")
    assert response.headers.get("access-control-allow-credentials") == "true"


@pytest.mark.asyncio
async def test_cors_preflight_vault_sync(client: AsyncClient):
    """Verifies OPTIONS preflight request for vault sync endpoints."""
    headers = {
        "Origin": "https://passman-web.vercel.app",
        "Access-Control-Request-Method": "GET",
        "Access-Control-Request-Headers": "authorization",
    }
    response = await client.options("/api/vault/sync", headers=headers)
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "https://passman-web.vercel.app"
    assert response.headers.get("access-control-allow-credentials") == "true"


@pytest.mark.asyncio
async def test_cors_actual_request_header(client: AsyncClient):
    """Verifies actual GET/POST requests include CORS headers."""
    headers = {
        "Origin": "https://passman.app",
    }
    response = await client.get("/", headers=headers)
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "https://passman.app"
    assert response.headers.get("access-control-allow-credentials") == "true"


@pytest.mark.asyncio
async def test_cors_unauthorized_origin(client: AsyncClient):
    """Verifies unauthorized origins do not receive allow-origin header."""
    headers = {
        "Origin": "http://malicious-site.example.com",
    }
    response = await client.get("/", headers=headers)
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") is None

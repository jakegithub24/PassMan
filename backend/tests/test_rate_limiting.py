import uuid
import pytest
from httpx import AsyncClient

from core.limiter import limiter


@pytest.mark.asyncio
async def test_register_rate_limiting(client: AsyncClient):
    # Reset limiter storage before testing rate limit window
    limiter.reset()

    # 3 requests allowed per minute on /api/auth/register
    for _ in range(3):
        res = await client.post("/api/auth/register", json={
            "email": f"ratetest_{uuid.uuid4().hex[:8]}@example.com",
            "password": "Password123!",
            "salt": "dGVzdF9zYWx0XzEyMzQ1Njc4",
        })
        assert res.status_code in [201, 400, 422]

    # 4th request must be throttled with 429 Too Many Requests
    blocked_res = await client.post("/api/auth/register", json={
        "email": f"ratetest_{uuid.uuid4().hex[:8]}@example.com",
        "password": "Password123!",
        "salt": "dGVzdF9zYWx0XzEyMzQ1Njc4",
    })
    assert blocked_res.status_code == 429
    assert "rate limit exceeded" in blocked_res.text.lower() or "too many requests" in blocked_res.text.lower()


@pytest.mark.asyncio
async def test_login_rate_limiting(client: AsyncClient):
    limiter.reset()

    # 5 requests allowed per minute on /api/auth/login
    for _ in range(5):
        res = await client.post("/api/auth/login", json={
            "email": f"ratetest_{uuid.uuid4().hex[:8]}@example.com",
            "password": "Password123!",
        })
        assert res.status_code in [200, 401]

    # 6th request must be throttled with 429 Too Many Requests
    blocked_res = await client.post("/api/auth/login", json={
        "email": f"ratetest_{uuid.uuid4().hex[:8]}@example.com",
        "password": "Password123!",
    })
    assert blocked_res.status_code == 429
    assert "rate limit exceeded" in blocked_res.text.lower() or "too many requests" in blocked_res.text.lower()

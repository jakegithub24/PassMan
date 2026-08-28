import uuid
import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.security import hash_token
from models.db_models import RefreshToken, User


@pytest.mark.asyncio
async def test_logout_revocation_end_to_end(client: AsyncClient, db_session: AsyncSession):
    unique_suffix = uuid.uuid4().hex[:8]
    test_email = f"logouttest_{unique_suffix}@example.com"
    master_password = "MasterPassword123!@#"
    salt = "dGVzdF9zYWx0XzEyMzQ1Njc4"

    # 1. Register & Login
    await client.post("/api/auth/register", json={
        "email": test_email,
        "password": master_password,
        "salt": salt,
    })
    login_res = await client.post("/api/auth/login", json={
        "email": test_email,
        "password": master_password,
    })
    assert login_res.status_code == 200
    login_data = login_res.json()
    refresh_token = login_data["refresh_token"]
    user_id = login_data["user"]["id"]
    token_digest = hash_token(refresh_token)

    # 2. Verify token is active by doing a successful refresh
    pre_refresh = await client.post("/api/auth/refresh", json={
        "refresh_token": refresh_token,
    })
    assert pre_refresh.status_code == 200

    # 3. Call /api/auth/logout
    logout_res = await client.post("/api/auth/logout", json={
        "refresh_token": refresh_token,
    })
    assert logout_res.status_code == 200
    assert "revoked" in logout_res.json()["message"].lower() or "logged out" in logout_res.json()["message"].lower()

    # 4. Verify database row has revoked_at set
    stmt = select(RefreshToken).where(RefreshToken.token_hash == token_digest)
    result = await db_session.execute(stmt)
    token_row = result.scalar_one_or_none()
    assert token_row is not None
    assert token_row.revoked_at is not None

    # 5. Subsequent /api/auth/refresh must now fail with 401
    post_refresh = await client.post("/api/auth/refresh", json={
        "refresh_token": refresh_token,
    })
    assert post_refresh.status_code == 401
    assert "revoked" in post_refresh.json()["detail"].lower()

    # 6. Clean up user
    stmt = select(User).where(User.id == uuid.UUID(user_id))
    result = await db_session.execute(stmt)
    user = result.scalar_one_or_none()
    if user:
        await db_session.delete(user)
        await db_session.commit()


@pytest.mark.asyncio
async def test_logout_idempotency(client: AsyncClient):
    # Calling logout with random token returns 200 OK
    res = await client.post("/api/auth/logout", json={
        "refresh_token": "random_or_already_revoked_token",
    })
    assert res.status_code == 200

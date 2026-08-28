import uuid
from datetime import datetime, timedelta, timezone
import pytest
from httpx import AsyncClient
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from core.jwt import create_access_token, create_refresh_token, decode_jwt_token
from core.security import hash_token
from models.db_models import RefreshToken, User
from models.schemas import ClientPlatform


@pytest.mark.asyncio
async def test_refresh_token_success(client: AsyncClient, db_session: AsyncSession):
    unique_suffix = uuid.uuid4().hex[:8]
    test_email = f"refreshtest_{unique_suffix}@example.com"
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
        "client_type": "android",
    })
    assert login_res.status_code == 200
    login_data = login_res.json()
    refresh_token = login_data["refresh_token"]
    user_id = login_data["user"]["id"]

    # 2. Call /api/auth/refresh
    refresh_res = await client.post("/api/auth/refresh", json={
        "refresh_token": refresh_token,
    })
    assert refresh_res.status_code == 200, refresh_res.text
    refresh_data = refresh_res.json()

    assert "access_token" in refresh_data
    assert refresh_data["token_type"] == "bearer"
    assert refresh_data["expires_in"] == 600
    assert refresh_data["user"]["email"] == test_email

    # Verify new access token
    new_acc_payload = decode_jwt_token(refresh_data["access_token"])
    assert new_acc_payload["type"] == "access"
    assert new_acc_payload["sub"] == user_id

    # 3. Clean up user
    stmt = select(User).where(User.id == uuid.UUID(user_id))
    result = await db_session.execute(stmt)
    user = result.scalar_one_or_none()
    if user:
        await db_session.delete(user)
        await db_session.commit()


@pytest.mark.asyncio
async def test_refresh_revoked_and_expired_tokens(client: AsyncClient, db_session: AsyncSession):
    unique_suffix = uuid.uuid4().hex[:8]
    test_email = f"revoketest_{unique_suffix}@example.com"
    master_password = "MasterPassword123!@#"
    salt = "dGVzdF9zYWx0XzEyMzQ1Njc4"

    # Register & Login
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

    # 1. Test Revocation
    # Manually revoke token in database
    await db_session.execute(
        update(RefreshToken)
        .where(RefreshToken.token_hash == token_digest)
        .values(revoked_at=datetime.now(timezone.utc))
    )
    await db_session.commit()

    revoked_res = await client.post("/api/auth/refresh", json={
        "refresh_token": refresh_token,
    })
    assert revoked_res.status_code == 401
    assert "revoked" in revoked_res.json()["detail"].lower()

    # 2. Test Expired in DB
    # Un-revoke but set expires_at in the past
    await db_session.execute(
        update(RefreshToken)
        .where(RefreshToken.token_hash == token_digest)
        .values(
            revoked_at=None,
            expires_at=datetime.now(timezone.utc) - timedelta(days=1),
        )
    )
    await db_session.commit()

    expired_res = await client.post("/api/auth/refresh", json={
        "refresh_token": refresh_token,
    })
    assert expired_res.status_code == 401
    assert "expired" in expired_res.json()["detail"].lower()

    # 3. Clean up user
    stmt = select(User).where(User.id == uuid.UUID(user_id))
    result = await db_session.execute(stmt)
    user = result.scalar_one_or_none()
    if user:
        await db_session.delete(user)
        await db_session.commit()


@pytest.mark.asyncio
async def test_refresh_token_confusion_and_unrecognized(client: AsyncClient):
    user_id = uuid.uuid4()
    
    # 1. Token Confusion: Pass access_token to /refresh
    access_token = create_access_token(user_id=user_id)
    confusion_res = await client.post("/api/auth/refresh", json={
        "refresh_token": access_token,
    })
    assert confusion_res.status_code == 401
    assert "Invalid token type" in confusion_res.json()["detail"]

    # 2. Unrecognized Token: Valid JWT signature but not saved in DB
    unregistered_refresh, _, _ = create_refresh_token(user_id=user_id)
    unrec_res = await client.post("/api/auth/refresh", json={
        "refresh_token": unregistered_refresh,
    })
    assert unrec_res.status_code == 401
    assert "not found" in unrec_res.json()["detail"].lower()

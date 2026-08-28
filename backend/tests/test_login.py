import uuid
import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.jwt import decode_jwt_token
from core.security import hash_token
from models.db_models import RefreshToken, User


@pytest.mark.asyncio
async def test_login_success_android_and_web(client: AsyncClient, db_session: AsyncSession):
    unique_suffix = uuid.uuid4().hex[:8]
    test_email = f"logintest_{unique_suffix}@example.com"
    master_password = "MasterPassword123!@#"
    salt = "dGVzdF9zYWx0XzEyMzQ1Njc4"

    # 1. Register user
    reg_res = await client.post("/api/auth/register", json={
        "email": test_email,
        "password": master_password,
        "salt": salt,
    })
    assert reg_res.status_code == 201, reg_res.text
    user_id = reg_res.json()["id"]

    # 2. Login as Android
    login_res_android = await client.post("/api/auth/login", json={
        "email": test_email.upper(),  # Test email case-normalization on login
        "password": master_password,
        "client_type": "android",
    })
    assert login_res_android.status_code == 200, login_res_android.text
    data_android = login_res_android.json()

    assert "access_token" in data_android
    assert "refresh_token" in data_android
    assert data_android["token_type"] == "bearer"
    assert data_android["expires_in"] == 600
    assert data_android["user"]["email"] == test_email
    assert data_android["user"]["salt"] == salt

    # Verify token contents
    access_payload = decode_jwt_token(data_android["access_token"])
    refresh_payload = decode_jwt_token(data_android["refresh_token"])
    assert access_payload["type"] == "access"
    assert access_payload["sub"] == user_id
    assert refresh_payload["type"] == "refresh"
    assert refresh_payload["sub"] == user_id
    assert refresh_payload["exp"] - refresh_payload["iat"] == 10 * 86400

    # Verify hashed token row stored in database
    expected_hash = hash_token(data_android["refresh_token"])
    stmt = select(RefreshToken).where(RefreshToken.token_hash == expected_hash)
    result = await db_session.execute(stmt)
    token_row = result.scalar_one_or_none()
    assert token_row is not None
    assert token_row.user_id == uuid.UUID(user_id)
    assert token_row.revoked_at is None

    # 3. Login as Web
    login_res_web = await client.post("/api/auth/login", json={
        "email": test_email,
        "password": master_password,
        "client_type": "web",
    })
    assert login_res_web.status_code == 200
    data_web = login_res_web.json()
    web_refresh_payload = decode_jwt_token(data_web["refresh_token"])
    assert web_refresh_payload["exp"] - web_refresh_payload["iat"] == 8 * 3600

    # 4. Clean up test user (cascades to refresh_tokens)
    stmt = select(User).where(User.id == uuid.UUID(user_id))
    result = await db_session.execute(stmt)
    user = result.scalar_one_or_none()
    if user:
        await db_session.delete(user)
        await db_session.commit()


@pytest.mark.asyncio
async def test_login_invalid_credentials(client: AsyncClient, db_session: AsyncSession):
    # Non-existent email
    res = await client.post("/api/auth/login", json={
        "email": "nonexistent_user_9999@example.com",
        "password": "AnyPassword123!",
    })
    assert res.status_code == 401
    assert "Invalid email or password" in res.json()["detail"]

    # Register a user and test wrong password
    unique_suffix = uuid.uuid4().hex[:8]
    test_email = f"wrongpw_{unique_suffix}@example.com"
    reg_res = await client.post("/api/auth/register", json={
        "email": test_email,
        "password": "CorrectPassword123!",
        "salt": "dGVzdF9zYWx0XzEyMzQ1Njc4",
    })
    assert reg_res.status_code == 201
    user_id = reg_res.json()["id"]

    # Wrong password
    res = await client.post("/api/auth/login", json={
        "email": test_email,
        "password": "WrongPassword123!",
    })
    assert res.status_code == 401
    assert "Invalid email or password" in res.json()["detail"]

    # Clean up
    stmt = select(User).where(User.id == uuid.UUID(user_id))
    result = await db_session.execute(stmt)
    user = result.scalar_one_or_none()
    if user:
        await db_session.delete(user)
        await db_session.commit()

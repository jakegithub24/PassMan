import uuid
from datetime import timedelta
import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.jwt import create_access_token
from models.db_models import User


@pytest.mark.asyncio
async def test_get_current_user_valid_access_token(client: AsyncClient, db_session: AsyncSession):
    unique_suffix = uuid.uuid4().hex[:8]
    test_email = f"me_test_{unique_suffix}@example.com"
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
    access_token = login_data["access_token"]
    user_id = login_data["user"]["id"]

    # 2. Call GET /api/auth/me with Bearer token
    me_res = await client.get("/api/auth/me", headers={
        "Authorization": f"Bearer {access_token}",
    })
    assert me_res.status_code == 200, me_res.text
    me_data = me_res.json()
    assert me_data["id"] == user_id
    assert me_data["email"] == test_email
    assert me_data["salt"] == salt

    # Clean up user
    stmt = select(User).where(User.id == uuid.UUID(user_id))
    result = await db_session.execute(stmt)
    user = result.scalar_one_or_none()
    if user:
        await db_session.delete(user)
        await db_session.commit()


@pytest.mark.asyncio
async def test_get_current_user_rejections(client: AsyncClient):
    user_id = uuid.uuid4()

    # 1. Missing Authorization header
    res_no_header = await client.get("/api/auth/me")
    assert res_no_header.status_code in [401, 403]

    # 2. Tampered token
    res_tampered = await client.get("/api/auth/me", headers={
        "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.invalid.signature",
    })
    assert res_tampered.status_code == 401
    assert "invalid" in res_tampered.json()["detail"].lower()

    # 3. Token Confusion: Provide refresh_token instead of access_token
    # Register a user to get a real refresh token
    unique_suffix = uuid.uuid4().hex[:8]
    test_email = f"confuse_{unique_suffix}@example.com"
    await client.post("/api/auth/register", json={
        "email": test_email,
        "password": "Password123!",
        "salt": "dGVzdF9zYWx0XzEyMzQ1Njc4",
    })
    login_res = await client.post("/api/auth/login", json={
        "email": test_email,
        "password": "Password123!",
    })
    refresh_token = login_res.json()["refresh_token"]

    res_confusion = await client.get("/api/auth/me", headers={
        "Authorization": f"Bearer {refresh_token}",
    })
    assert res_confusion.status_code == 401
    assert "Invalid token type" in res_confusion.json()["detail"]

    # 4. Expired access token
    expired_token = create_access_token(user_id=user_id, expires_delta=timedelta(minutes=-5))
    res_expired = await client.get("/api/auth/me", headers={
        "Authorization": f"Bearer {expired_token}",
    })
    assert res_expired.status_code == 401
    assert "expired" in res_expired.json()["detail"].lower()

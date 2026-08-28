import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from main import app
from core.database import AsyncSessionLocal
from models.db_models import User
from core.security import verify_password


@pytest.mark.asyncio
async def test_register_success_and_duplicate():
    unique_suffix = uuid.uuid4().hex[:8]
    test_email = f"user_{unique_suffix}@example.com"
    master_password = "MasterPassword123!@#"
    salt = "dGVzdF9zYWx0XzEyMzQ1Njc4"

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Test Successful Registration
        register_payload = {
            "email": f"  {test_email.upper()}  ",  # Test normalization
            "password": master_password,
            "salt": salt,
        }
        response = await client.post("/api/auth/register", json=register_payload)
        assert response.status_code == 201, response.text
        data = response.json()

        assert "id" in data
        assert data["email"] == test_email.lower()
        assert data["salt"] == salt
        assert "password" not in data
        assert "password_hash" not in data

        user_id = data["id"]

        # 2. Verify database record
        async with AsyncSessionLocal() as session:
            stmt = select(User).where(User.email == test_email.lower())
            result = await session.execute(stmt)
            db_user = result.scalar_one_or_none()

            assert db_user is not None
            assert db_user.password_hash.startswith("$argon2id$")
            assert verify_password(master_password, db_user.password_hash) is True

            # 3. Test Duplicate Registration (should fail with 400)
            dup_response = await client.post("/api/auth/register", json=register_payload)
            assert dup_response.status_code == 400
            assert "already exists" in dup_response.json()["detail"]

            # Clean up test user
            await session.delete(db_user)
            await session.commit()


@pytest.mark.asyncio
async def test_register_validation_errors():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Short password
        res = await client.post("/api/auth/register", json={
            "email": "invalid_pw@test.com",
            "password": "short",
            "salt": "valid_salt_12345678",
        })
        assert res.status_code == 422

        # Short salt
        res = await client.post("/api/auth/register", json={
            "email": "invalid_salt@test.com",
            "password": "ValidPassword123!",
            "salt": "short_salt",
        })
        assert res.status_code == 422

        # Invalid email format
        res = await client.post("/api/auth/register", json={
            "email": "not-an-email",
            "password": "ValidPassword123!",
            "salt": "valid_salt_12345678",
        })
        assert res.status_code == 422

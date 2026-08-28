import json
import uuid
import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.db_models import User, VaultEntry


@pytest.mark.asyncio
async def test_create_vault_entry_success(client: AsyncClient, db_session: AsyncSession):
    unique_suffix = uuid.uuid4().hex[:8]
    test_email = f"vault_{unique_suffix}@example.com"
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
    access_token = login_res.json()["access_token"]
    user_id = login_res.json()["user"]["id"]

    # 2. Create valid encrypted vault entry
    valid_encrypted_payload = json.dumps({
        "ciphertext": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
        "iv": "1234567890abcdef",
        "tag": "abcdef1234567890",
    })

    create_res = await client.post(
        "/api/vault/entries",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"encrypted_data": valid_encrypted_payload},
    )
    assert create_res.status_code == 201, create_res.text
    entry_data = create_res.json()

    assert "id" in entry_data
    assert entry_data["user_id"] == user_id
    assert entry_data["encrypted_data"] == valid_encrypted_payload
    assert entry_data["deleted_at"] is None
    entry_id = entry_data["id"]

    # 3. Verify in database
    stmt = select(VaultEntry).where(VaultEntry.id == uuid.UUID(entry_id))
    result = await db_session.execute(stmt)
    db_entry = result.scalar_one_or_none()
    assert db_entry is not None
    assert db_entry.user_id == uuid.UUID(user_id)

    # 4. Clean up user (cascades to vault_entries)
    stmt_user = select(User).where(User.id == uuid.UUID(user_id))
    res_user = await db_session.execute(stmt_user)
    user = res_user.scalar_one_or_none()
    if user:
        await db_session.delete(user)
        await db_session.commit()


@pytest.mark.asyncio
async def test_create_vault_entry_rejects_plaintext_fields(client: AsyncClient):
    unique_suffix = uuid.uuid4().hex[:8]
    test_email = f"zkfail_{unique_suffix}@example.com"
    await client.post("/api/auth/register", json={
        "email": test_email,
        "password": "Password123!",
        "salt": "dGVzdF9zYWx0XzEyMzQ1Njc4",
    })
    login_res = await client.post("/api/auth/login", json={
        "email": test_email,
        "password": "Password123!",
    })
    access_token = login_res.json()["access_token"]
    headers = {"Authorization": f"Bearer {access_token}"}

    valid_zk = json.dumps({"ciphertext": "abc", "iv": "def", "tag": "ghi"})

    # 1. Reject extra body field 'password'
    res1 = await client.post("/api/vault/entries", headers=headers, json={
        "encrypted_data": valid_zk,
        "password": "plaintext_password",
    })
    assert res1.status_code == 422

    # 2. Reject extra body field 'title'
    res2 = await client.post("/api/vault/entries", headers=headers, json={
        "encrypted_data": valid_zk,
        "title": "My Google Login",
    })
    assert res2.status_code == 422

    # 3. Reject plaintext field nested in encrypted_data JSON
    bad_zk = json.dumps({"ciphertext": "abc", "iv": "def", "tag": "ghi", "password": "leaked_password"})
    res3 = await client.post("/api/vault/entries", headers=headers, json={
        "encrypted_data": bad_zk,
    })
    assert res3.status_code == 422
    assert "Zero-knowledge violation" in res3.text

    # 4. Reject incomplete envelope (missing tag)
    incomplete_zk = json.dumps({"ciphertext": "abc", "iv": "def"})
    res4 = await client.post("/api/vault/entries", headers=headers, json={
        "encrypted_data": incomplete_zk,
    })
    assert res4.status_code == 422

    # 5. Reject raw non-JSON string
    res5 = await client.post("/api/vault/entries", headers=headers, json={
        "encrypted_data": "raw_non_json_string",
    })
    assert res5.status_code == 422

import json
import uuid
from datetime import datetime
import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.db_models import User, VaultEntry


@pytest.mark.asyncio
async def test_update_vault_entry_success(client: AsyncClient, db_session: AsyncSession):
    unique_suffix = uuid.uuid4().hex[:8]
    test_email = f"update_{unique_suffix}@example.com"
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
    access_token = login_res.json()["access_token"]
    user_id = login_res.json()["user"]["id"]
    headers = {"Authorization": f"Bearer {access_token}"}

    # 1. Create entry
    initial_payload = json.dumps({"ciphertext": "initial_cipher", "iv": "initial_iv", "tag": "initial_tag"})
    create_res = await client.post("/api/vault/entries", headers=headers, json={"encrypted_data": initial_payload})
    assert create_res.status_code == 201
    entry_id = create_res.json()["id"]
    initial_updated_at = create_res.json()["updated_at"]

    # 2. Update entry
    updated_payload = json.dumps({"ciphertext": "updated_cipher", "iv": "updated_iv", "tag": "updated_tag"})
    update_res = await client.put(f"/api/vault/entries/{entry_id}", headers=headers, json={"encrypted_data": updated_payload})
    assert update_res.status_code == 200, update_res.text
    updated_data = update_res.json()

    assert updated_data["id"] == entry_id
    assert updated_data["encrypted_data"] == updated_payload
    assert updated_data["updated_at"] >= initial_updated_at

    # 3. Clean up user
    stmt = select(User).where(User.id == uuid.UUID(user_id))
    result = await db_session.execute(stmt)
    user = result.scalar_one_or_none()
    if user:
        await db_session.delete(user)
        await db_session.commit()


@pytest.mark.asyncio
async def test_update_vault_entry_isolation_and_not_found(client: AsyncClient, db_session: AsyncSession):
    # Setup User A
    user_a_email = f"usera_{uuid.uuid4().hex[:8]}@example.com"
    await client.post("/api/auth/register", json={"email": user_a_email, "password": "Password123!", "salt": "dGVzdF9zYWx0XzEyMzQ1Njc4"})
    login_a = await client.post("/api/auth/login", json={"email": user_a_email, "password": "Password123!"})
    token_a = login_a.json()["access_token"]
    user_a_id = login_a.json()["user"]["id"]

    # Setup User B
    user_b_email = f"userb_{uuid.uuid4().hex[:8]}@example.com"
    await client.post("/api/auth/register", json={"email": user_b_email, "password": "Password123!", "salt": "dGVzdF9zYWx0XzEyMzQ1Njc4"})
    login_b = await client.post("/api/auth/login", json={"email": user_b_email, "password": "Password123!"})
    token_b = login_b.json()["access_token"]
    user_b_id = login_b.json()["user"]["id"]

    # User A creates an entry
    payload_a = json.dumps({"ciphertext": "cipher_a", "iv": "iv_a", "tag": "tag_a"})
    create_res = await client.post("/api/vault/entries", headers={"Authorization": f"Bearer {token_a}"}, json={"encrypted_data": payload_a})
    entry_a_id = create_res.json()["id"]

    # User B attempts to update User A's entry -> must return 404
    payload_b = json.dumps({"ciphertext": "cipher_b", "iv": "iv_b", "tag": "tag_b"})
    update_res = await client.put(f"/api/vault/entries/{entry_a_id}", headers={"Authorization": f"Bearer {token_b}"}, json={"encrypted_data": payload_b})
    assert update_res.status_code == 404

    # Non-existent entry UUID -> 404
    fake_id = str(uuid.uuid4())
    res_fake = await client.put(f"/api/vault/entries/{fake_id}", headers={"Authorization": f"Bearer {token_a}"}, json={"encrypted_data": payload_a})
    assert res_fake.status_code == 404

    # Clean up both users
    for uid in [user_a_id, user_b_id]:
        stmt = select(User).where(User.id == uuid.UUID(uid))
        res = await db_session.execute(stmt)
        user = res.scalar_one_or_none()
        if user:
            await db_session.delete(user)
            await db_session.commit()

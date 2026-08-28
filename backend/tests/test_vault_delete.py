import json
import uuid
import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.db_models import User, VaultEntry


@pytest.mark.asyncio
async def test_delete_vault_entry_soft_delete_lifecycle(client: AsyncClient, db_session: AsyncSession):
    unique_suffix = uuid.uuid4().hex[:8]
    test_email = f"delete_{unique_suffix}@example.com"
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
    payload = json.dumps({"ciphertext": "del_cipher", "iv": "del_iv", "tag": "del_tag"})
    create_res = await client.post("/api/vault/entries", headers=headers, json={"encrypted_data": payload})
    assert create_res.status_code == 201
    entry_id = create_res.json()["id"]

    # 2. Soft-delete entry
    del_res = await client.delete(f"/api/vault/entries/{entry_id}", headers=headers)
    assert del_res.status_code == 200, del_res.text
    assert "deleted successfully" in del_res.json()["message"].lower()

    # 3. Verify in database: deleted_at is set
    stmt = select(VaultEntry).where(VaultEntry.id == uuid.UUID(entry_id))
    result = await db_session.execute(stmt)
    entry_in_db = result.scalar_one_or_none()
    assert entry_in_db is not None
    assert entry_in_db.deleted_at is not None

    # 4. Attempting to delete again returns 404 (already deleted)
    dup_del = await client.delete(f"/api/vault/entries/{entry_id}", headers=headers)
    assert dup_del.status_code == 404

    # 5. Attempting to update deleted entry returns 404
    update_res = await client.put(
        f"/api/vault/entries/{entry_id}",
        headers=headers,
        json={"encrypted_data": json.dumps({"ciphertext": "new", "iv": "new", "tag": "new"})},
    )
    assert update_res.status_code == 404

    # Clean up user
    stmt_user = select(User).where(User.id == uuid.UUID(user_id))
    res_user = await db_session.execute(stmt_user)
    user = res_user.scalar_one_or_none()
    if user:
        await db_session.delete(user)
        await db_session.commit()


@pytest.mark.asyncio
async def test_delete_vault_entry_isolation_and_not_found(client: AsyncClient, db_session: AsyncSession):
    # Setup User A
    user_a_email = f"dela_{uuid.uuid4().hex[:8]}@example.com"
    await client.post("/api/auth/register", json={"email": user_a_email, "password": "Password123!", "salt": "dGVzdF9zYWx0XzEyMzQ1Njc4"})
    login_a = await client.post("/api/auth/login", json={"email": user_a_email, "password": "Password123!"})
    token_a = login_a.json()["access_token"]
    user_a_id = login_a.json()["user"]["id"]

    # Setup User B
    user_b_email = f"delb_{uuid.uuid4().hex[:8]}@example.com"
    await client.post("/api/auth/register", json={"email": user_b_email, "password": "Password123!", "salt": "dGVzdF9zYWx0XzEyMzQ1Njc4"})
    login_b = await client.post("/api/auth/login", json={"email": user_b_email, "password": "Password123!"})
    token_b = login_b.json()["access_token"]
    user_b_id = login_b.json()["user"]["id"]

    # User A creates entry
    payload_a = json.dumps({"ciphertext": "cipher_a", "iv": "iv_a", "tag": "tag_a"})
    create_res = await client.post("/api/vault/entries", headers={"Authorization": f"Bearer {token_a}"}, json={"encrypted_data": payload_a})
    entry_a_id = create_res.json()["id"]

    # User B attempts to delete User A's entry -> returns 404
    del_other = await client.delete(f"/api/vault/entries/{entry_a_id}", headers={"Authorization": f"Bearer {token_b}"})
    assert del_other.status_code == 404

    # Non-existent entry ID -> 404
    fake_id = str(uuid.uuid4())
    del_fake = await client.delete(f"/api/vault/entries/{fake_id}", headers={"Authorization": f"Bearer {token_a}"})
    assert del_fake.status_code == 404

    # Clean up
    for uid in [user_a_id, user_b_id]:
        stmt = select(User).where(User.id == uuid.UUID(uid))
        res = await db_session.execute(stmt)
        user = res.scalar_one_or_none()
        if user:
            await db_session.delete(user)
            await db_session.commit()

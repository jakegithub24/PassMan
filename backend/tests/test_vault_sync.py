import json
import uuid
from datetime import datetime, timezone
import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.db_models import User, VaultEntry


@pytest.mark.asyncio
async def test_sync_status_endpoint(client: AsyncClient):
    res = await client.get("/api/vault/sync/status")
    assert res.status_code == 200, res.text
    data = res.json()
    assert "server_time" in data
    assert data["status"] == "online"
    # Ensure server_time is valid ISO 8601
    parsed_time = datetime.fromisoformat(data["server_time"])
    assert parsed_time is not None


@pytest.mark.asyncio
async def test_vault_sync_full_and_delta(client: AsyncClient, db_session: AsyncSession):
    unique_suffix = uuid.uuid4().hex[:8]
    test_email = f"sync_{unique_suffix}@example.com"
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

    # 1. Create Entry 1 and Entry 2
    p1 = json.dumps({"ciphertext": "c1", "iv": "iv1", "tag": "t1"})
    p2 = json.dumps({"ciphertext": "c2", "iv": "iv2", "tag": "t2"})
    res1 = await client.post("/api/vault/entries", headers=headers, json={"encrypted_data": p1})
    res2 = await client.post("/api/vault/entries", headers=headers, json={"encrypted_data": p2})
    e1_id = res1.json()["id"]
    e2_id = res2.json()["id"]

    # 2. Delete Entry 2 (creates a tombstone record)
    await client.delete(f"/api/vault/entries/{e2_id}", headers=headers)

    # 3. Initial Full Sync (since is None)
    sync_res = await client.get("/api/vault/sync", headers=headers)
    assert sync_res.status_code == 200, sync_res.text
    sync_data = sync_res.json()

    assert "entries" in sync_data
    assert "server_time" in sync_data
    assert len(sync_data["entries"]) == 2  # Both active and deleted entries

    # Check tombstone preservation
    tombstone = next(e for e in sync_data["entries"] if e["id"] == e2_id)
    active_entry = next(e for e in sync_data["entries"] if e["id"] == e1_id)
    assert tombstone["deleted_at"] is not None
    assert active_entry["deleted_at"] is None

    baseline_time = sync_data["server_time"]

    # 4. Create Entry 3 after baseline time
    p3 = json.dumps({"ciphertext": "c3", "iv": "iv3", "tag": "t3"})
    res3 = await client.post("/api/vault/entries", headers=headers, json={"encrypted_data": p3})
    e3_id = res3.json()["id"]

    # 5. Delta Sync with since=baseline_time
    delta_res = await client.get(f"/api/vault/sync?since={baseline_time}", headers=headers)
    assert delta_res.status_code == 200, delta_res.text
    delta_data = delta_res.json()

    # Only Entry 3 was modified after baseline
    assert len(delta_data["entries"]) == 1
    assert delta_data["entries"][0]["id"] == e3_id

    # 6. Clean up user
    stmt_user = select(User).where(User.id == uuid.UUID(user_id))
    res_user = await db_session.execute(stmt_user)
    user = res_user.scalar_one_or_none()
    if user:
        await db_session.delete(user)
        await db_session.commit()

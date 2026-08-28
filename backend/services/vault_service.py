from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.db_models import VaultEntry
from models.schemas import VaultEntryCreate, VaultEntryOut, VaultEntryUpdate, VaultSyncResponse


async def create_vault_entry(
    db: AsyncSession,
    user_id: UUID,
    entry_in: VaultEntryCreate,
) -> VaultEntry:
    """
    Persist a zero-knowledge encrypted vault entry for the authenticated user.
    The server only receives and stores { ciphertext, iv, tag }.
    """
    entry = VaultEntry(
        user_id=user_id,
        encrypted_data=entry_in.encrypted_data,
    )
    db.add(entry)
    await db.commit()
    await db.refresh(entry)
    return entry


async def update_vault_entry(
    db: AsyncSession,
    user_id: UUID,
    entry_id: UUID,
    entry_in: VaultEntryUpdate,
) -> VaultEntry:
    """
    Update encrypted payload of an existing vault entry and advance updated_at timestamp.
    Ensures multi-tenant isolation by checking user_id ownership.
    """
    stmt = select(VaultEntry).where(
        VaultEntry.id == entry_id,
        VaultEntry.user_id == user_id,
        VaultEntry.deleted_at.is_(None),
    )
    result = await db.execute(stmt)
    entry = result.scalar_one_or_none()

    if not entry:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Vault entry not found.",
        )

    entry.encrypted_data = entry_in.encrypted_data
    entry.updated_at = datetime.now(timezone.utc)

    await db.commit()
    await db.refresh(entry)
    return entry


async def delete_vault_entry(
    db: AsyncSession,
    user_id: UUID,
    entry_id: UUID,
) -> VaultEntry:
    """
    Soft-delete a vault entry: sets deleted_at = NOW() and advances updated_at timestamp.
    Ensures offline delta-sync propagates deletions to other clients.
    """
    stmt = select(VaultEntry).where(
        VaultEntry.id == entry_id,
        VaultEntry.user_id == user_id,
        VaultEntry.deleted_at.is_(None),
    )
    result = await db.execute(stmt)
    entry = result.scalar_one_or_none()

    if not entry:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Vault entry not found.",
        )

    now_utc = datetime.now(timezone.utc)
    entry.deleted_at = now_utc
    entry.updated_at = now_utc

    await db.commit()
    await db.refresh(entry)
    return entry


async def sync_vault_entries(
    db: AsyncSession,
    user_id: UUID,
    since: Optional[datetime] = None,
    limit: int = 500,
) -> VaultSyncResponse:
    """
    Delta synchronization query using composite index (user_id, updated_at DESC):
    - Returns active and soft-deleted (tombstoned) records modified strictly after 'since'.
    - Returns authoritative server_time timestamp for client sync baseline.
    """
    server_time = datetime.now(timezone.utc)
    stmt = select(VaultEntry).where(VaultEntry.user_id == user_id)
    
    if since is not None:
        stmt = stmt.where(VaultEntry.updated_at > since)
        
    stmt = stmt.order_by(VaultEntry.updated_at.desc()).limit(limit + 1)
    result = await db.execute(stmt)
    entries = result.scalars().all()

    has_more = len(entries) > limit
    trimmed = entries[:limit]

    return VaultSyncResponse(
        entries=[VaultEntryOut.model_validate(e) for e in trimmed],
        server_time=server_time,
        has_more=has_more,
    )

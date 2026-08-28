from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.db_models import VaultEntry
from models.schemas import VaultEntryCreate, VaultEntryUpdate


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

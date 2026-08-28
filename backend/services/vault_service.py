from typing import Optional
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.db_models import VaultEntry
from models.schemas import VaultEntryCreate


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

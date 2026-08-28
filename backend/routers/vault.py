from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from core.database import get_db
from core.dependencies import get_current_user
from models.db_models import User
from models.schemas import (
    MessageResponse,
    VaultEntryCreate,
    VaultEntryOut,
    VaultEntryUpdate,
    VaultSyncResponse,
    VaultSyncStatus,
)
from services.vault_service import (
    create_vault_entry,
    delete_vault_entry,
    sync_vault_entries,
    update_vault_entry,
)

router = APIRouter(prefix="/api/vault", tags=["Vault"])


@router.get(
    "/sync/status",
    response_model=VaultSyncStatus,
    status_code=status.HTTP_200_OK,
    summary="Get authoritative sync status and server time",
    description="Returns current authoritative UTC server timestamp and backend operational status for clock alignment.",
)
async def sync_status() -> VaultSyncStatus:
    """Return authoritative server time and status."""
    return VaultSyncStatus(
        server_time=datetime.now(timezone.utc).isoformat(),
        status="online",
    )


@router.post(
    "/entries",
    response_model=VaultEntryOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new encrypted vault entry",
    description="Stores zero-knowledge encrypted vault entry ({ciphertext, iv, tag}). Strictly rejects any plaintext payload fields.",
)
async def create_entry(
    entry_in: VaultEntryCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> VaultEntryOut:
    """Store an encrypted vault record for the authenticated user."""
    entry = await create_vault_entry(db=db, user_id=current_user.id, entry_in=entry_in)
    return VaultEntryOut.model_validate(entry)


@router.put(
    "/entries/{entry_id}",
    response_model=VaultEntryOut,
    status_code=status.HTTP_200_OK,
    summary="Update an existing encrypted vault entry",
    description="Updates the ciphertext payload of an existing active vault entry and advances updated_at timestamp.",
)
async def update_entry(
    entry_id: UUID,
    entry_in: VaultEntryUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> VaultEntryOut:
    """Update an encrypted vault entry for the authenticated user."""
    entry = await update_vault_entry(
        db=db,
        user_id=current_user.id,
        entry_id=entry_id,
        entry_in=entry_in,
    )
    return VaultEntryOut.model_validate(entry)


@router.delete(
    "/entries/{entry_id}",
    response_model=MessageResponse,
    status_code=status.HTTP_200_OK,
    summary="Soft-delete a vault entry",
    description="Marks vault entry with deleted_at timestamp and advances updated_at for sync propagation.",
)
async def delete_entry(
    entry_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> MessageResponse:
    """Soft delete an encrypted vault entry."""
    await delete_vault_entry(
        db=db,
        user_id=current_user.id,
        entry_id=entry_id,
    )
    return MessageResponse(message="Vault entry deleted successfully.")


@router.get(
    "/sync",
    response_model=VaultSyncResponse,
    status_code=status.HTTP_200_OK,
    summary="Delta synchronize vault entries",
    description="Fetches all vault records (active and deleted tombstones) modified strictly after 'since' parameter using index (user_id, updated_at DESC).",
)
async def sync_entries(
    since: Optional[datetime] = Query(
        default=None,
        description="ISO 8601 UTC timestamp baseline. If omitted, returns all entries.",
    ),
    limit: int = Query(
        default=500,
        ge=1,
        le=1000,
        description="Maximum entries to return in single page.",
    ),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> VaultSyncResponse:
    """Perform delta synchronization."""
    return await sync_vault_entries(
        db=db,
        user_id=current_user.id,
        since=since,
        limit=limit,
    )

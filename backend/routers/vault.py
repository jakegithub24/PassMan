from uuid import UUID
from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from core.database import get_db
from core.dependencies import get_current_user
from models.db_models import User
from models.schemas import VaultEntryCreate, VaultEntryOut, VaultEntryUpdate
from services.vault_service import create_vault_entry, update_vault_entry

router = APIRouter(prefix="/api/vault", tags=["Vault"])


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

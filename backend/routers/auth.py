from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from core.database import get_db
from models.schemas import UserCreate, UserOut
from services.auth_service import register_user

router = APIRouter(prefix="/api/auth", tags=["Authentication"])


@router.post(
    "/register",
    response_model=UserOut,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new user account",
    description="Registers a new user with master password hash (Argon2id) and client-side derivation salt.",
)
async def register(
    user_in: UserCreate,
    db: AsyncSession = Depends(get_db),
) -> UserOut:
    """Register a new user account."""
    user = await register_user(db=db, user_in=user_in)
    return UserOut.model_validate(user)

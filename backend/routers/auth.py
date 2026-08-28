from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from core.database import get_db
from models.schemas import TokenPair, UserCreate, UserLogin, UserOut
from services.auth_service import login_user, register_user

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


@router.post(
    "/login",
    response_model=TokenPair,
    status_code=status.HTTP_200_OK,
    summary="Authenticate and obtain dual token pair",
    description="Authenticates master password against Argon2id hash, issues access token (10m) and refresh token (10d Android / 8h Web), and records hashed token in database.",
)
async def login(
    user_login: UserLogin,
    db: AsyncSession = Depends(get_db),
) -> TokenPair:
    """Log in user and issue access/refresh token pair."""
    return await login_user(db=db, user_login=user_login)

from fastapi import APIRouter, Depends, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from core.database import get_db
from core.dependencies import get_current_user
from core.limiter import limiter
from models.db_models import User
from models.schemas import LogoutRequest, MessageResponse, TokenPair, TokenRefreshRequest, UserCreate, UserLogin, UserOut
from services.auth_service import login_user, logout_user, refresh_access_token, register_user

router = APIRouter(prefix="/api/auth", tags=["Authentication"])


@router.post(
    "/register",
    response_model=UserOut,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new user account",
    description="Registers a new user with master password hash (Argon2id) and client-side derivation salt. Rate limited to 3 requests/minute.",
)
@limiter.limit("3/minute")
async def register(
    request: Request,
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
    description="Authenticates master password against Argon2id hash, issues access token (10m) and refresh token (10d Android / 8h Web), and records hashed token in database. Rate limited to 5 requests/minute.",
)
@limiter.limit("5/minute")
async def login(
    request: Request,
    user_login: UserLogin,
    db: AsyncSession = Depends(get_db),
) -> TokenPair:
    """Log in user and issue access/refresh token pair."""
    return await login_user(db=db, user_login=user_login)


@router.post(
    "/refresh",
    response_model=TokenPair,
    status_code=status.HTTP_200_OK,
    summary="Rotate access token using refresh token",
    description="Validates active refresh token against database hash and expiration, and returns a fresh 10-minute access token.",
)
async def refresh_token_endpoint(
    refresh_req: TokenRefreshRequest,
    db: AsyncSession = Depends(get_db),
) -> TokenPair:
    """Exchange valid refresh token for fresh access token."""
    return await refresh_access_token(db=db, refresh_req=refresh_req)


@router.post(
    "/logout",
    response_model=MessageResponse,
    status_code=status.HTTP_200_OK,
    summary="Revoke active refresh token session",
    description="Permanently revokes a refresh token session by setting revoked_at timestamp in the database.",
)
async def logout(
    logout_req: LogoutRequest,
    db: AsyncSession = Depends(get_db),
) -> MessageResponse:
    """Revoke refresh token and terminate session."""
    return await logout_user(db=db, logout_req=logout_req)


@router.get(
    "/me",
    response_model=UserOut,
    status_code=status.HTTP_200_OK,
    summary="Get current authenticated user profile",
    description="Decodes Bearer access token and returns user profile for the authenticated session.",
)
async def get_me(
    current_user: User = Depends(get_current_user),
) -> UserOut:
    """Return authenticated user profile."""
    return UserOut.model_validate(current_user)

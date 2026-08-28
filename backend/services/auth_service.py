import uuid
from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.config import settings
from core.jwt import create_access_token, create_token_pair, decode_jwt_token, validate_token_type
from core.security import hash_password, hash_token, verify_password
from models.db_models import RefreshToken, User
from models.schemas import (
    ClientPlatform,
    LogoutRequest,
    MessageResponse,
    TokenPair,
    TokenRefreshRequest,
    UserCreate,
    UserLogin,
    UserOut,
)


async def get_user_by_email(db: AsyncSession, email: str) -> Optional[User]:
    """Retrieve a user by normalized email address."""
    stmt = select(User).where(User.email == email.strip().lower())
    result = await db.execute(stmt)
    return result.scalar_one_or_none()


async def get_user_by_id(db: AsyncSession, user_id: UUID) -> Optional[User]:
    """Retrieve a user by unique UUID."""
    stmt = select(User).where(User.id == user_id)
    result = await db.execute(stmt)
    return result.scalar_one_or_none()


async def register_user(db: AsyncSession, user_in: UserCreate) -> User:
    """
    Register a new user account:
    1. Validates uniqueness of email.
    2. Hashes master password with Argon2id.
    3. Persists user record with derivation salt.
    """
    normalized_email = user_in.email.strip().lower()
    
    # Check if user already exists
    existing_user = await get_user_by_email(db, normalized_email)
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="An account with this email already exists.",
        )

    # Hash master password with Argon2id
    password_hash = hash_password(user_in.password)

    # Create new User entity
    new_user = User(
        email=normalized_email,
        password_hash=password_hash,
        salt=user_in.salt,
    )

    db.add(new_user)
    await db.commit()
    await db.refresh(new_user)
    return new_user


async def login_user(db: AsyncSession, user_login: UserLogin) -> TokenPair:
    """
    Authenticate user credentials and issue a dual-token pair:
    1. Look up user by email.
    2. Verify master password with Argon2id.
    3. Generate Access (10m) and Refresh (10d Android / 8h Web) tokens.
    4. Store SHA-256 hash of refresh token in database for revocation tracking.
    """
    normalized_email = user_login.email.strip().lower()
    user = await get_user_by_email(db, normalized_email)

    if not user or not verify_password(user_login.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Issue platform-aware token pair
    token_pair, refresh_expires_at, _ = create_token_pair(
        user_id=user.id,
        client_type=user_login.client_type,
    )

    # Persist SHA-256 digest in refresh_tokens table
    refresh_token_record = RefreshToken(
        user_id=user.id,
        token_hash=hash_token(token_pair.refresh_token),
        expires_at=refresh_expires_at,
        revoked_at=None,
    )

    db.add(refresh_token_record)
    await db.commit()

    # Populate user profile in response
    token_pair.user = UserOut.model_validate(user)
    return token_pair


async def refresh_access_token(db: AsyncSession, refresh_req: TokenRefreshRequest) -> TokenPair:
    """
    Validate an active refresh token and issue a fresh access token:
    1. Verify JWT signature & 'type=refresh' claim.
    2. Lookup token SHA-256 hash in database.
    3. Ensure token is not revoked and not expired.
    4. Issue fresh 10-minute access token.
    """
    # 1. Decode & validate JWT structure
    payload_dict = decode_jwt_token(refresh_req.refresh_token)
    payload = validate_token_type(payload_dict, expected_type="refresh")

    user_id = UUID(payload.sub)
    token_digest = hash_token(refresh_req.refresh_token)

    # 2. Check token record in database
    stmt = select(RefreshToken).where(RefreshToken.token_hash == token_digest)
    result = await db.execute(stmt)
    token_record = result.scalar_one_or_none()

    if not token_record:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token not found or unrecognized.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if token_record.revoked_at is not None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token has been revoked.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    now_utc = datetime.now(timezone.utc)
    if token_record.expires_at <= now_utc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token has expired.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 3. Verify user still exists
    user = await get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User account associated with token not found.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 4. Generate new access token
    platform = refresh_req.client_type or payload.client_type or ClientPlatform.ANDROID
    new_access_token = create_access_token(user_id=user.id, client_type=platform)
    platform_str = platform.value if isinstance(platform, ClientPlatform) else str(platform)
    
    expires_in_seconds = (
        settings.WEB_ACCESS_TOKEN_EXPIRES * 60
        if platform_str == ClientPlatform.WEB.value
        else settings.ANDROID_ACCESS_TOKEN_EXPIRES * 60
    )

    return TokenPair(
        access_token=new_access_token,
        refresh_token=refresh_req.refresh_token,
        token_type="bearer",
        expires_in=expires_in_seconds,
        user=UserOut.model_validate(user),
    )


async def logout_user(db: AsyncSession, logout_req: LogoutRequest) -> MessageResponse:
    """
    Revoke an active refresh token session by setting revoked_at = NOW():
    1. Compute SHA-256 hash of provided bearer refresh token.
    2. Mark revoked_at timestamp in refresh_tokens table.
    """
    token_digest = hash_token(logout_req.refresh_token)
    stmt = select(RefreshToken).where(RefreshToken.token_hash == token_digest)
    result = await db.execute(stmt)
    token_record = result.scalar_one_or_none()

    if token_record and token_record.revoked_at is None:
        token_record.revoked_at = datetime.now(timezone.utc)
        await db.commit()

    return MessageResponse(
        message="Session revoked successfully. Logged out.",
    )

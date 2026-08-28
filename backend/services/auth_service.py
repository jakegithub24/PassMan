from typing import Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException, status

from core.jwt import create_token_pair
from core.security import hash_password, hash_token, verify_password
from models.db_models import RefreshToken, User
from models.schemas import TokenPair, UserCreate, UserLogin, UserOut


async def get_user_by_email(db: AsyncSession, email: str) -> Optional[User]:
    """Retrieve a user by normalized email address."""
    stmt = select(User).where(User.email == email.strip().lower())
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

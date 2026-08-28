from typing import Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException, status

from core.security import hash_password, verify_password
from models.db_models import User
from models.schemas import UserCreate


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

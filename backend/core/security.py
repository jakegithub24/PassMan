import hashlib
import logging
from typing import Optional
from argon2 import PasswordHasher
from argon2.exceptions import (
    InvalidHashError,
    VerificationError,
    VerifyMismatchError,
)

logger = logging.getLogger(__name__)

# Argon2id password hasher with memory-hard configuration (OWASP recommended)
# time_cost=3, memory_cost=65536 (64 MB), parallelism=4, hash_len=32, salt_len=16
password_hasher = PasswordHasher(
    time_cost=3,
    memory_cost=65536,
    parallelism=4,
    hash_len=32,
    salt_len=16,
)


def hash_password(password: str) -> str:
    """Hash a plaintext master password using Argon2id."""
    return password_hasher.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verify a plaintext password against an Argon2id hash.
    Returns True if the password matches, False otherwise.
    """
    try:
        return password_hasher.verify(hashed_password, plain_password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False
    except Exception as e:
        logger.error(f"Unexpected error during password verification: {e}")
        return False


def needs_rehash(hashed_password: str) -> bool:
    """Check if a stored password hash needs rehashing due to parameter updates."""
    try:
        return password_hasher.check_needs_rehash(hashed_password)
    except Exception:
        return True


def hash_token(token: str) -> str:
    """
    Compute the SHA-256 hex digest of a bearer refresh token.
    Used for secure database storage and fast lookup without storing raw tokens.
    """
    return hashlib.sha256(token.encode("utf-8")).hexdigest()

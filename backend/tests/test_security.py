import pytest
from core.security import (
    hash_password,
    hash_token,
    needs_rehash,
    verify_password,
)


def test_argon2_password_hashing():
    password = "SuperSecureMasterPassword123!"
    hashed = hash_password(password)

    assert hashed.startswith("$argon2id$")
    assert verify_password(password, hashed) is True
    assert verify_password("WrongPassword123!", hashed) is False
    assert verify_password(password, "invalid_hash_value") is False
    assert needs_rehash(hashed) is False


def test_sha256_token_hashing():
    token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0"
    digest1 = hash_token(token)
    digest2 = hash_token(token)

    assert len(digest1) == 64
    assert digest1 == digest2
    assert digest1 != hash_token(token + "_altered")

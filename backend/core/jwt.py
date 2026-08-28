import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional, Tuple, Union
from uuid import UUID

import jwt
from fastapi import HTTPException, status

from core.config import settings
from models.schemas import ClientPlatform, TokenPayload, TokenPair


def get_current_utc() -> datetime:
    """Return current timezone-aware UTC datetime."""
    return datetime.now(timezone.utc)


def create_access_token(
    user_id: Union[UUID, str],
    client_type: Union[ClientPlatform, str] = ClientPlatform.ANDROID,
    expires_delta: Optional[timedelta] = None,
) -> str:
    """
    Generate a signed JWT access token.
    Default lifespan: 10 minutes (per ANDROID_ACCESS_TOKEN_EXPIRES / WEB_ACCESS_TOKEN_EXPIRES).
    """
    now = get_current_utc()
    platform_str = client_type.value if isinstance(client_type, ClientPlatform) else str(client_type)
    
    if expires_delta:
        expire = now + expires_delta
    else:
        minutes = (
            settings.WEB_ACCESS_TOKEN_EXPIRES
            if platform_str == ClientPlatform.WEB.value
            else settings.ANDROID_ACCESS_TOKEN_EXPIRES
        )
        expire = now + timedelta(minutes=minutes)

    payload: Dict[str, Any] = {
        "sub": str(user_id),
        "type": "access",
        "iat": int(now.timestamp()),
        "exp": int(expire.timestamp()),
        "client_type": platform_str,
    }

    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.ALGORITHM)


def create_refresh_token(
    user_id: Union[UUID, str],
    client_type: Union[ClientPlatform, str] = ClientPlatform.ANDROID,
    expires_delta: Optional[timedelta] = None,
) -> Tuple[str, datetime, str]:
    """
    Generate a signed JWT refresh token.
    Lifespan:
      - Android: 10 days (ANDROID_REFRESH_TOKEN_EXPIRES)
      - Web: 8 hours (WEB_REFRESH_TOKEN_EXPIRES)
    Returns: (raw_token, expires_at_datetime, jti)
    """
    now = get_current_utc()
    platform_str = client_type.value if isinstance(client_type, ClientPlatform) else str(client_type)
    jti = str(uuid.uuid4())

    if expires_delta:
        expire = now + expires_delta
    elif platform_str == ClientPlatform.WEB.value:
        expire = now + timedelta(hours=settings.WEB_REFRESH_TOKEN_EXPIRES)
    else:
        expire = now + timedelta(days=settings.ANDROID_REFRESH_TOKEN_EXPIRES)

    payload: Dict[str, Any] = {
        "sub": str(user_id),
        "type": "refresh",
        "jti": jti,
        "iat": int(now.timestamp()),
        "exp": int(expire.timestamp()),
        "client_type": platform_str,
    }

    token = jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.ALGORITHM)
    return token, expire, jti


def create_token_pair(
    user_id: Union[UUID, str],
    client_type: Union[ClientPlatform, str] = ClientPlatform.ANDROID,
) -> Tuple[TokenPair, datetime, str]:
    """
    Create both Access and Refresh tokens for an authenticated user session.
    Returns: (TokenPair, refresh_expires_at, refresh_jti)
    """
    platform_str = client_type.value if isinstance(client_type, ClientPlatform) else str(client_type)
    access_token = create_access_token(user_id=user_id, client_type=client_type)
    refresh_token, refresh_exp, refresh_jti = create_refresh_token(user_id=user_id, client_type=client_type)
    
    expires_in_seconds = (
        settings.WEB_ACCESS_TOKEN_EXPIRES * 60
        if platform_str == ClientPlatform.WEB.value
        else settings.ANDROID_ACCESS_TOKEN_EXPIRES * 60
    )

    token_pair = TokenPair(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        expires_in=expires_in_seconds,
    )

    return token_pair, refresh_exp, refresh_jti


def decode_jwt_token(token: str) -> Dict[str, Any]:
    """
    Decode and verify a JWT token signature and expiration using JWT_SECRET_KEY.
    Raises HTTPException 401 if expired or invalid.
    """
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token signature or payload.",
            headers={"WWW-Authenticate": "Bearer"},
        )


def validate_token_type(payload: Dict[str, Any], expected_type: str) -> TokenPayload:
    """
    Verify that the decoded token matches the expected 'type' claim ('access' or 'refresh').
    Prevents token confusion / token swapping attacks.
    """
    token_type = payload.get("type")
    if token_type != expected_type:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token type: expected '{expected_type}', got '{token_type}'.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    if not payload.get("sub"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token payload missing subject identifier (sub).",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return TokenPayload(**payload)

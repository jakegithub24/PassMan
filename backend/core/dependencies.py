from uuid import UUID
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.database import get_db
from core.jwt import decode_jwt_token, validate_token_type
from models.db_models import User

# HTTP Bearer security scheme for OpenAPI documentation and header extraction
http_bearer = HTTPBearer(auto_error=True)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(http_bearer),
    db: AsyncSession = Depends(get_db),
) -> User:
    """
    FastAPI dependency that extracts, decodes, and validates the bearer access token,
    and returns the authenticated User ORM model.
    
    Security enforcement:
    1. Extracts Bearer token from 'Authorization' header.
    2. Verifies HMAC-SHA256 signature and timestamp expiry via decode_jwt_token.
    3. Strictly enforces 'type == access' claim via validate_token_type to prevent token confusion.
    4. Fetches active User from database.
    """
    raw_token = credentials.credentials
    payload_dict = decode_jwt_token(raw_token)
    payload = validate_token_type(payload_dict, expected_type="access")

    try:
        user_id = UUID(payload.sub)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Malformed user identifier in token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    stmt = select(User).where(User.id == user_id)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user account not found.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user

from datetime import datetime
from enum import Enum
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


class ClientPlatform(str, Enum):
    """Supported client platforms for session duration differentiation."""
    ANDROID = "android"
    WEB = "web"


# ------------------------------------------------------------------------------
# Auth & User Schemas
# ------------------------------------------------------------------------------

class UserBase(BaseModel):
    email: EmailStr = Field(..., description="Unique email address for user identification")

    @field_validator("email", mode="before")
    @classmethod
    def normalize_email(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip().lower()
        return v


class UserCreate(UserBase):
    """Payload for registering a new user."""
    password: str = Field(
        ...,
        min_length=8,
        description="Master password (never stored in plaintext)",
    )
    salt: str = Field(
        ...,
        min_length=16,
        description="Base64-encoded client-side cryptographic salt used for key derivation",
    )


class UserLogin(UserBase):
    """Payload for user authentication."""
    password: str = Field(..., min_length=1, description="Master password")
    client_type: ClientPlatform = Field(
        default=ClientPlatform.ANDROID,
        description="Client platform to determine refresh token lifespan (android: 10d, web: 8h)",
    )


class UserOut(UserBase):
    """Public user response model."""
    id: UUID = Field(..., description="Unique user UUID")
    salt: str = Field(..., description="Client derivation salt")
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class TokenPair(BaseModel):
    """Dual-token response containing short-lived access and revocable refresh tokens."""
    access_token: str = Field(..., description="Short-lived JWT access token (10 mins)")
    refresh_token: str = Field(..., description="Long-lived JWT refresh token (10d Android / 8h Web)")
    token_type: str = Field(default="bearer", description="OAuth2 token type")
    expires_in: int = Field(..., description="Access token lifetime in seconds (e.g. 600)")
    user: Optional[UserOut] = Field(default=None, description="Authenticated user profile")


class TokenRefreshRequest(BaseModel):
    """Payload for rotating access token via an active refresh token."""
    refresh_token: str = Field(..., description="Active bearer refresh token")
    client_type: Optional[ClientPlatform] = Field(
        default=None,
        description="Optional client platform override",
    )


class LogoutRequest(BaseModel):
    """Payload for revoking a refresh token session."""
    refresh_token: str = Field(..., description="Bearer refresh token to revoke")


class TokenPayload(BaseModel):
    """Decoded internal JWT claim structure."""
    sub: str = Field(..., description="Subject identifier (user UUID)")
    type: str = Field(..., description="Token type ('access' or 'refresh')")
    exp: int = Field(..., description="Expiration timestamp (Unix epoch)")
    iat: int = Field(..., description="Issued at timestamp (Unix epoch)")
    jti: Optional[str] = Field(default=None, description="Unique token identifier (refresh tokens)")
    client_type: Optional[str] = Field(default="android", description="Originating client platform")


class MessageResponse(BaseModel):
    """Standard message response."""
    message: str
    detail: Optional[str] = None


# ------------------------------------------------------------------------------
# Vault Entry Schemas
# ------------------------------------------------------------------------------

import json

class VaultEntryBase(BaseModel):
    encrypted_data: str = Field(
        ...,
        description="Opaque JSON string containing { ciphertext, iv, tag }",
    )

    model_config = ConfigDict(extra="forbid")

    @field_validator("encrypted_data")
    @classmethod
    def validate_zero_knowledge_envelope(cls, v: str) -> str:
        if not isinstance(v, str):
            raise ValueError("encrypted_data must be a string")
        try:
            parsed = json.loads(v)
        except Exception:
            raise ValueError("encrypted_data must be a valid JSON string containing {ciphertext, iv, tag}")
        
        if not isinstance(parsed, dict):
            raise ValueError("encrypted_data JSON payload must be an object")
        
        required_keys = {"ciphertext", "iv", "tag"}
        if not required_keys.issubset(parsed.keys()):
            missing = required_keys - set(parsed.keys())
            raise ValueError(f"encrypted_data payload missing required keys: {missing}")
        
        # Check for forbidden plaintext fields in root keys
        forbidden_keys = {"password", "plaintext", "cleartext", "secret", "title", "username", "notes", "url"}
        found_forbidden = forbidden_keys.intersection(set(k.lower() for k in parsed.keys()))
        if found_forbidden:
            raise ValueError(f"Zero-knowledge violation: Plaintext-shaped fields detected in payload: {found_forbidden}")
        
        return v


class VaultEntryCreate(VaultEntryBase):
    """Payload to create a new encrypted vault entry."""
    pass


class VaultEntryUpdate(VaultEntryBase):
    """Payload to update an existing encrypted vault entry."""
    pass


class VaultEntryOut(VaultEntryBase):
    """Public vault entry representation."""
    id: UUID
    user_id: UUID
    updated_at: datetime
    deleted_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class VaultSyncStatus(BaseModel):
    """Authoritative server time for clock synchronization."""
    server_time: str
    status: str = "online"


class VaultSyncResponse(BaseModel):
    """Delta synchronization payload containing modified and tombstoned records."""
    entries: list[VaultEntryOut] = Field(default_factory=list)
    server_time: datetime
    has_more: bool = False

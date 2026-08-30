from typing import List, Union
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Database Settings
    DATABASE_URL: str = Field(
        default="postgresql+asyncpg://postgres:postgres@localhost:5432/passman",
        description="Async SQLAlchemy database connection string",
    )

    # JWT Security Settings
    JWT_SECRET_KEY: str = Field(
        default="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        description="Secret key for signing JWTs",
    )
    ALGORITHM: str = Field(default="HS256", description="JWT signing algorithm")

    # Android Platform Expiration & Vault Lock (Minutes / Days)
    ANDROID_ACCESS_TOKEN_EXPIRES: int = Field(default=10, description="Android access token expiry in minutes")
    ANDROID_REFRESH_TOKEN_EXPIRES: int = Field(default=10, description="Android refresh token expiry in days")
    ANDROID_VAULT_LOCK: int = Field(default=15, description="Default Android auto-lock duration in minutes")

    # Web Platform Expiration & Vault Lock (Minutes / Hours)
    WEB_ACCESS_TOKEN_EXPIRES: int = Field(default=10, description="Web access token expiry in minutes")
    WEB_REFRESH_TOKEN_EXPIRES: int = Field(default=8, description="Web refresh token expiry in hours")
    WEB_VAULT_LOCK: int = Field(default=15, description="Default Web auto-lock duration in minutes")

    # CORS Settings
    CORS_ORIGINS: Union[str, List[str]] = Field(
        default="http://localhost:3000,http://127.0.0.1:3000,http://localhost:8080,http://127.0.0.1:8080,http://localhost:5000,http://127.0.0.1:5000,http://localhost:5173,https://passman.app,https://passman-web.vercel.app",
        description="Comma-separated or list of allowed CORS origins",
    )

    # Application Settings
    ENVIRONMENT: str = Field(default="development", description="Runtime environment")
    LOG_LEVEL: str = Field(default="info", description="Logging level")

    @field_validator("DATABASE_URL", mode="before")
    @classmethod
    def assemble_database_url(cls, v: str) -> str:
        if isinstance(v, str):
            if v.startswith("postgresql://"):
                return v.replace("postgresql://", "postgresql+asyncpg://", 1)
            elif v.startswith("postgres://"):
                return v.replace("postgres://", "postgresql+asyncpg://", 1)
        return v

    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> List[str]:
        if isinstance(v, str):
            return [origin.strip() for origin in v.split(",") if origin.strip()]
        return v

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )


settings = Settings()

from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import AsyncGenerator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from core.config import settings


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifecycle events manager."""
    # Startup actions
    yield
    # Shutdown actions


app = FastAPI(
    title="PassMan API",
    description="Zero-Knowledge, Offline-First Cross-Platform Password Manager Backend",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

from routers.auth import router as auth_router
from routers.vault import router as vault_router

# Include API Routers
app.include_router(auth_router)
app.include_router(vault_router)


@app.get("/", tags=["Health"])
async def root():
    """Root health check endpoint."""
    return {
        "app": "PassMan API",
        "version": "1.0.0",
        "status": "healthy",
        "environment": settings.ENVIRONMENT,
    }




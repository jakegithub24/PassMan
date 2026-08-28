-- ==============================================================================
-- PassMan Database Schema DDL (Supabase / PostgreSQL 15+)
-- ==============================================================================
-- Purpose:
-- 1. Zero-knowledge encrypted vault storage with soft-delete tombstones for delta sync.
-- 2. Master account authentication with Argon2id password hashing and user salt.
-- 3. Revocable dual-token session management via SHA-256 hashed refresh tokens.
-- 4. Asynchronous security audit logging for compliance and threat tracking.
-- ==============================================================================

-- 1. Cryptographic and UUID Extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------------------------
-- 2. Users Table
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,       -- Argon2id memory-hard password hash
    salt TEXT NOT NULL,                -- Base64 user salt for client key derivation
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast user authentication lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- ------------------------------------------------------------------------------
-- 3. Vault Entries Table (Zero-Knowledge Ciphertext & Soft-Delete Tombstones)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vault_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    encrypted_data TEXT NOT NULL,       -- JSON payload: { ciphertext, iv, tag }
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ NULL         -- Tombstone for delta sync (NOT hard deleted)
);

-- Composite Index optimized for delta sync queries: WHERE user_id = :id AND updated_at > :since ORDER BY updated_at DESC
CREATE INDEX IF NOT EXISTS idx_vault_user_sync ON vault_entries(user_id, updated_at DESC);

-- Index on deleted_at for partial queries
CREATE INDEX IF NOT EXISTS idx_vault_deleted_at ON vault_entries(deleted_at) WHERE deleted_at IS NULL;

-- ------------------------------------------------------------------------------
-- 4. Refresh Tokens Table (Hashed Storage & Revocation Tracking)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT UNIQUE NOT NULL,    -- SHA-256 digest of bearer refresh token
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ NULL,        -- Non-null indicates revoked token session
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Foreign key lookup index on user_id
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);

-- Fast lookup for active non-revoked refresh tokens
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_lookup ON refresh_tokens(token_hash, revoked_at);

-- ------------------------------------------------------------------------------
-- 5. Audit Logs Table (Asynchronous Activity Logging)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,               -- LOGIN, REFRESH, SYNC, CREATE, UPDATE, DELETE
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Composite index for viewing user activity log history
CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON audit_logs(user_id, created_at DESC);

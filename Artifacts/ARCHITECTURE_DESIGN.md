# ARCHITECTURE_DESIGN.md
## Cross-Platform Password Manager — System Architecture Design

This document describes the structural design: layers, data flow, security boundaries, and the reasoning behind each decision. For endpoint specs, schema DDL, and the delivery schedule, see `MVP.md`, `TRD.md`, and `PRD.md`.

---

## 1. Design Principles

1. **Zero-knowledge by default.** Vault plaintext never leaves the device. The server stores and transmits ciphertext only, and has no code path capable of decrypting it.
2. **Encrypt once.** A payload that's already AES-256-GCM ciphertext gains no protection from a second encryption layer at rest. Local storage stays plain; only the *key material* is protected (OS keystore).
3. **Offline is the default state, not a fallback.** UI always renders from local cache first; network is an enhancement layer on top.
4. **Deletes are writes.** Nothing is ever hard-removed from the sync-of-record; it's tombstoned so every device converges to the same state.
5. **Every trigger for a moving part must be justified.** No background timers or duplicate storage layers unless they solve a problem nothing else already solves.

---

## 2. System Layers

```text
┌───────────────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER (Flutter)                   │
│   Login/Signup · Vault List · Add/Edit · Search/Copy              │
│   State: Riverpod (AuthState, VaultState, SyncState)              │
├───────────────────────────────────────────────────────────────────┤
│                       CLIENT SERVICES LAYER                       │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐            │
│  │ AES-256-GCM   │ │ Local Cache   │ │ Dio Client    │            │
│  │ Encrypt/Decr  │ │ sqflite (And) │ │JWT interceptor│            │
│  │ (plaintext    │ │ Hive (Web)    │ │ + refresh-on- │            │
│  │  never sent)  │ │ (plain, no    │ │ 401 retry     │            │
│  │               │ │  2nd encrypt) │ │               │            │
│  └───────────────┘ └───────────────┘ └───────┬───────┘            │
│  Session key lives only in flutter_secure_storage (Keystore/      │
│  Keychain) — never written to the local cache DB.                 │
└──────────────────────────────────────────────┼────────────────────┘
                                               │ HTTPS + Bearer JWT
┌──────────────────────────────────────────────▼──────────────────────┐
│                    API / MIDDLEWARE LAYER (FastAPI)                 │
│  CORS → Rate Limit (5/min on auth) → Logging → Auth (JWT decode)    │
│  ┌────────────┐ ┌────────────┐ ┌──────────────────┐                 │
│  │ Auth Router│ │ Vault      │ │ Refresh Router   │                 │
│  └─────┬──────┘ └─────┬──────┘ └─────────┬────────┘                 │
│        │  Service layer: Argon2id verify, ownership checks,         │
│        │  soft-delete logic, async audit-log writes                 │
└────────┼────────────────────────────────────────────────────────────┘
         │ asyncpg / SQLAlchemy (direct connection, service credential)
┌────────▼────────────────────────────────────────────────────────────┐
│                  PERSISTENCE (Supabase / PostgreSQL)                │
│  users · vault_entries (soft-delete) · refresh_tokens · audit_logs  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Security Boundary

```text
┌───────────────────── DEVICE (trusted for plaintext) ─────────────────┐
│  Master password → key derivation → session key (Keystore/Keychain)  │
│  Vault plaintext ←→ AES-256-GCM ←→ ciphertext                        │
└───────────────────────────────┬──────────────────────────────────────┘
                                │  ciphertext + iv + tag ONLY crosses here
┌────────────────────────────── NETWORK ──────────────────────────────┐
│                          HTTPS / TLS                                │
└───────────────────────────────┬─────────────────────────────────────┘
┌────────────────────── SERVER (never sees plaintext) ────────────────┐
│  FastAPI: validates JWT, checks ownership, stores ciphertext as-is  │
│  Postgres: stores ciphertext, Argon2id password hashes, metadata    │
└─────────────────────────────────────────────────────────────────────┘
```

**What crosses the boundary:** ciphertext, IV, auth tag, timestamps, JWTs.
**What never crosses it:** master password, derived key, vault plaintext.

**Why RLS is not part of this boundary:** FastAPI connects to Postgres with a single service-level credential (asyncpg/SQLAlchemy), not through Supabase's PostgREST layer with per-request user JWTs. Postgres has no way to know "who" is asking, so Row Level Security policies would never trigger — enabling it would be a no-op that looks like a safeguard but isn't one. Ownership enforcement lives in the FastAPI service layer (`WHERE user_id = current_user.id` on every query), which is the layer that actually knows who's asking.

---

## 4. Data Flow: Sync (Delta + Tombstones)

```text
[App Launch / Resume / Manual Sync]
         │
         ▼
[Render local cache instantly — works fully offline]
         │
         ▼
[GET /entries?since=last_synced_at]
         │
         ▼
[Server: WHERE user_id = X AND updated_at > since]
  (includes soft-deleted rows — deleted_at IS NOT NULL allowed through)
         │
         ▼
[Client receives delta batch]
         │
         ├── deleted_at present ──► remove from local cache
         │
         ├── server updated_at > local ──► overwrite local (LWW)
         │
         └── local updated_at > server ──► queue for PUSH (PUT/POST)
         │
         ▼
[Push pending local changes → mark is_pending_sync = 0 on success]
```

This flow is the same on Android and Web because the local cache schema is identical (see `MVP.md §3`) — there is one sync implementation, not two.

---

## 5. Data Flow: Auth + Token Refresh

```text
[Login] ──► Argon2id verify ──► issue access_token (15m) + refresh_token (7d)
                                  (same JWT secret, differentiated by `type` claim)
         │
         ▼
[Dio attaches Authorization: Bearer <access_token> to every request]
         │
         ▼
[401 received] ──► [POST /auth/refresh with stored refresh_token]
         │                          │
         ▼                          ▼
   [retry original request]   [refresh invalid/expired/revoked]
                                     │
                                     ▼
                              [clear tokens → force login]
```

`refresh_tokens` are tracked server-side (hashed) so logout/revocation is enforceable — a client can't keep using a refresh token after the server has invalidated it.

---

## 6. Why Certain Things Were Deliberately Left Out of MVP

| Considered | Decision | Reason |
| :--- | :--- | :--- |
| SQLCipher / encrypted Hive | **Cut** | Encrypts data that's already ciphertext; adds a key-management surface with no security benefit |
| 30s background sync polling | **Cut** | Battery/data cost for a non-core feature; launch/resume/manual triggers are sufficient |
| Hard deletes | **Replaced with soft-delete** | Hard deletes are invisible to delta sync — offline devices would never learn a row was removed |
| RLS as a "fallback" | **Cut** | No-op under a direct service-credential connection; false sense of defense-in-depth |
| Password reset + SMTP | **Deferred to v1.1** | Deliverability/security surface too large to properly test in a 13-day MVP window |
| Two JWT secrets (access/refresh) | **Merged to one + `type` claim** | Two secrets to rotate and protect for no added security over a claim-based split |
| `version` column on vault_entries | **Dropped** | Unused — LWW conflict resolution runs entirely off `updated_at` |

---

## 7. Extension Points (Post-MVP)

- **True DB-level authorization:** route FastAPI through Supabase's PostgREST + per-user JWT claims so RLS policies become meaningful, as a second enforcement layer behind the service-layer checks.
- **Real-time sync:** replace launch/resume/manual triggers with Supabase Realtime or WebSockets once polling proves insufficient for the target usage pattern.
- **Password reset flow:** dedicated reset-token table, SMTP integration, rate-limited reset endpoint, with its own security review.
- **Multi-device conflict UI:** surface LWW overwrites to the user instead of resolving silently, if usage data shows concurrent-edit conflicts are common.

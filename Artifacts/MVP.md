# MVP.md
## Cross-Platform Password Manager (Android & Web) — Offline-First, Zero-Knowledge

**Stack:** Flutter · FastAPI · Supabase (PostgreSQL) · Argon2id · JWT (Access + Refresh) · Client-side AES-256-GCM

---

## 1. Tech Stack (Finalized)

| Layer | Technology | Purpose |
| :--- | :--- | :--- |
| **Frontend (UI)** | Flutter (Riverpod) | Cross-platform (Android + Web) rendering |
| **Android Local DB** | `sqflite` | Local cache — stores already-encrypted blobs, no second encryption layer |
| **Web Local Cache** | `Hive` | Local cache — same shape as Android, no second encryption layer |
| **Backend Framework** | FastAPI (Async, ASGI) | REST API, OpenAPI, OAuth2 JWT |
| **Cloud DB** | Supabase (PostgreSQL 15) | Managed Postgres, direct connection via asyncpg/SQLAlchemy |
| **Password Hashing** | Argon2id (`argon2-cffi`) | Server-side hash for master passwords only |
| **Auth Protocol** | JWT (Access 15 min / Refresh 7 days) | Single secret, differentiated by a `type` claim |
| **Vault Encryption** | AES-256-GCM (client-side, Dart) | Zero-knowledge — server only ever sees ciphertext |
| **HTTP Client** | Dio + Interceptors | Auto JWT injection, auto refresh-on-401 |

### Why local storage isn't double-encrypted
Vault entries are already AES-256-GCM ciphertext before they ever leave the device. Wrapping that ciphertext again in an encrypted database (SQLCipher / Hive-encryption) protects nothing — it's encryption of encryption. The only thing worth protecting locally is the **derived session key**, which lives in `flutter_secure_storage` (Keychain/Keystore), not in a second encrypted DB layer. This also means Android and Web use the **same cache shape and the same sync code.**

---

## 2. Data Models (Supabase / PostgreSQL)

### `users`
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,   -- Argon2id
    salt TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### `vault_entries` (soft-delete enabled — required for correct sync)
```sql
CREATE TABLE vault_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    encrypted_data TEXT NOT NULL,   -- JSON { ciphertext, iv, tag }
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ NULL     -- tombstone; NOT hard-deleted
);
CREATE INDEX idx_vault_user_sync ON vault_entries(user_id, updated_at DESC);
```
> A hard `DELETE` would silently vanish from `?since=` results and offline devices would never learn the row was removed. Deletes are writes (`deleted_at` set + `updated_at` bumped), not row removals. Normal list reads filter `deleted_at IS NULL`; delta sync reads **do not** filter it, so clients can propagate the tombstone.

### `refresh_tokens`
```sql
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT UNIQUE NOT NULL,  -- SHA-256 of raw refresh token
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### `audit_logs`
```sql
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,  -- LOGIN, REFRESH, SYNC, CREATE, UPDATE, DELETE
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```
Written as fire-and-forget async inserts inside existing endpoints — not a separate router/service.

---

## 3. Local Cache Schema (Android & Web — identical shape)

```
local_vault_cache:
  id                 TEXT PRIMARY KEY
  encrypted_data     TEXT   -- ciphertext, as received from server
  iv                 TEXT
  tag                TEXT
  server_updated_at  TEXT
  deleted            INTEGER  -- 1 = tombstoned, hide from UI
  is_pending_sync    INTEGER  -- 1 = local change awaiting push
```
No local encryption library required. Same table on `sqflite` and `Hive`; the merge/sync logic is shared Dart code, not platform-specific.

---

## 4. API Endpoints

| Method | Endpoint | Description | Auth |
| :--- | :--- | :--- | :--- |
| POST | `/api/auth/register` | Sign up (Argon2id hash) | No |
| POST | `/api/auth/login` | Returns `access_token` + `refresh_token` | No |
| POST | `/api/auth/refresh` | Exchange refresh token for new access token | No |
| POST | `/api/auth/logout` | Revoke refresh token | Yes |
| GET | `/api/vault/entries?since=<ts>` | Delta sync — includes tombstones | Yes |
| POST | `/api/vault/entries` | Create entry | Yes |
| PUT | `/api/vault/entries/{id}` | Update entry | Yes |
| DELETE | `/api/vault/entries/{id}` | Soft delete (sets `deleted_at`) | Yes |
| GET | `/api/vault/sync/status` | Current server timestamp | Yes |

> Password reset (forgot-password + SMTP) is **cut from MVP scope** — deliverability, token security, and UI for that flow won't get proper test coverage in this timeline. Ship "re-register / contact support" for v1; add real reset flow in v1.1.

---

## 5. Refresh Token Flow

1. Login issues `access_token` (15 min) + `refresh_token` (7 days) — same JWT secret, differentiated by a `type` claim (`access` / `refresh`). No need to manage two secrets.
2. Stored in `flutter_secure_storage` on both Android and Web.
3. Dio interceptor attaches `Authorization: Bearer <access_token>` to every request.
4. On `401`, interceptor calls `/api/auth/refresh`, retries the original request once.
5. On refresh failure (expired/revoked) → clear tokens → force login screen.

---

## 6. Sync Strategy

### Triggers (no background polling loop)
Sync runs on: **app launch**, **app resume from background**, and **manual pull-to-refresh / "Sync Now."** A constant 30-second timer was cut — it burns battery and data for a feature (near-live sync) that isn't core to a password manager's value, and three explicit triggers are enough for "seamless."

### A. Initial Load
1. Render local cache immediately (instant UI, works offline).
2. Fetch `GET /entries?since=0` in the background, decrypt, merge, rewrite cache.

### B. Delta Sync (on each trigger)
- Client sends `GET /entries?since=<last_synced_at>`.
- Server returns all rows (including tombstones) with `updated_at > since`.
- Client applies **Last-Write-Wins**:
  - `deleted_at` present → remove locally.
  - Server `updated_at` > local → overwrite local.
  - Local `updated_at` > server → push via `PUT`.

### C. Offline Changes
1. Add/edit/delete while offline → encrypt client-side → write to local cache with `is_pending_sync = 1` (deletes just set `deleted = 1` locally, pending push).
2. UI updates optimistically.
3. On next sync trigger, push all pending rows (`POST`/`PUT`/`DELETE`), clear the flag on success.

---

## 7. Middleware Stack (FastAPI)

| Middleware | Implementation | Purpose |
| :--- | :--- | :--- |
| Auth | `Depends(get_current_user)` | Decodes JWT, loads user, on every protected route |
| Logging | `@app.middleware("http")` | Method/path/status/duration → console + async `audit_logs` insert |
| Rate Limiting | `slowapi` | 5 req/min on `/login` and `/refresh` |
| CORS | `CORSMiddleware` | Restricted to Flutter Web deploy origin + localhost |
| Validation | Pydantic models | Structural validation before DB writes |

---

## 8. Work Breakdown Schedule (13 Days)

| Day | Focus | Deliverables |
| :--- | :--- | :--- |
| 1 | Setup | FastAPI + Supabase + Flutter init; schema incl. `deleted_at` |
| 2 | Backend Auth | Register/login, Argon2id, single-secret JWT (access+refresh), `refresh_tokens` table |
| 3 | Vault CRUD | Async CRUD, soft-delete, `?since=` delta endpoint, ownership checks |
| 4 | Middleware | CORS, rate limiting, request logging |
| 5 | Flutter Auth UI | Signup/login screens, Dio interceptor with refresh-on-401 |
| 6 | Encryption Layer | AES-256-GCM in Dart; verify server only ever receives `{ciphertext, iv, tag}` |
| 7 | Flutter Vault UI | List/add/edit/delete, wired to CRUD API |
| 8 | Local Cache | `sqflite` (Android) + `Hive` (Web), shared cache shape and sync logic |
| 9 | Sync Engine | Launch/resume/manual triggers, LWW merge, tombstone handling |
| 10 | Local Auth | Biometric/PIN via `local_auth`; session key in `flutter_secure_storage` |
| 11 | Testing | `pytest-asyncio` unit tests, Flutter widget tests, offline→online sync test, delete-propagation test |
| 12 | Bug Fixing | UI polish, Dio error handling, CORS edge cases |
| 13 | Release | Deploy FastAPI (Render/Fly.io), Supabase prod, Android APK, Web build |

---

## 9. Acceptance Criteria

- [ ] User can register/login; refresh token successfully rotates access tokens.
- [ ] Android app opens instantly showing cached vault, even offline.
- [ ] Adding an entry offline saves locally and syncs automatically on next trigger.
- [ ] Deleting an entry on Device A removes it from Device B on next sync (tombstone propagation).
- [ ] Web app syncs on launch/resume/manual refresh with no CORS errors.
- [ ] FastAPI never stores or logs plaintext passwords or vault data.
- [ ] Rate limiting blocks >5 login attempts/minute from the same IP.
- [ ] Audit logs capture login/refresh/sync/CRUD actions with IP and user agent.
- [ ] Manual "Sync Now" correctly resolves conflicts via Last-Write-Wins.

---

## 10. Deployment Configuration

### Supabase
- Direct `postgresql://` connection from FastAPI (asyncpg/SQLAlchemy).
- Supabase's built-in Auth is disabled — auth is handled entirely by FastAPI/Argon2id.
- **RLS is not enabled.** A direct backend connection with a service-level credential bypasses Postgres RLS entirely — it only takes effect when Postgres itself authenticates the caller (e.g. via PostgREST + per-user JWT claims), which this architecture doesn't use. Ownership is enforced in the FastAPI service layer instead. If per-row DB-level enforcement is wanted later, that's a distinct v1.1 project (routing through Supabase's client SDK), not an MVP checkbox.

### FastAPI `.env`
```env
DATABASE_URL=postgresql://user:pass@aws-0-region.pooler.supabase.com:5432/postgres
JWT_SECRET_KEY=your_super_secret_key
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=7
```

### Flutter
- Android: `minSdkVersion 21`, `android:usesCleartextTraffic="false"`.
- Web: configure CORS in FastAPI to match the deployed Web origin exactly.

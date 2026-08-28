# Authentication & Token Management Logic (AUTH_TOKEN_LOGIC.md)
## PassMan — Dual-Token Lifecycle, Vault Locking & Session Security

**Version:** 1.0 (MVP)  
**Backend:** FastAPI (Python)  
**Client:** Flutter (Android & Web)  
**Token Protocol:** Single-Secret JWT with `type` claim (`access` / `refresh`)  

---

## 1. Overview & Core Architecture

PassMan decouples **Account Authentication** (server-managed identity) from **Vault Decryption** (client-managed zero-knowledge encryption). 

### 1.1 Key Lifetimes & Parameters (Platform-Specific)

#### Android Mobile:
- **`ANDROID_ACCESS_TOKEN_EXPIRES`:** 10 minutes (`ANDROID_ACCESS_TOKEN_EXPIRES = 10`)
- **`ANDROID_REFRESH_TOKEN_EXPIRES`:** 10 days (`ANDROID_REFRESH_TOKEN_EXPIRES = 10`)
- **`ANDROID_VAULT_LOCK`:** 5–30 minutes (user selectable, e.g. 5, 10, 15, 30 min; triggers on inactivity or backgrounding)

#### Web Browser:
- **`WEB_ACCESS_TOKEN_EXPIRES`:** 10 minutes (`WEB_ACCESS_TOKEN_EXPIRES = 10`)
- **`WEB_REFRESH_TOKEN_EXPIRES`:** 8 hours (`WEB_REFRESH_TOKEN_EXPIRES = 8`)
- **`WEB_VAULT_LOCK`:** 5–30 minutes (user selectable, e.g. 5, 10, 15, 30 min; triggers on inactivity or tab hide)

#### General Token Architecture:
- **Token Signing:** Single `JWT_SECRET_KEY` using `HS256`, differentiated by a mandatory `type` claim (`"access"` vs `"refresh"`).
- **Refresh Token Tracking:** SHA-256 hash stored in PostgreSQL `refresh_tokens` table to enable instant server-side revocation upon logout or security events.
- **Vault Auto-Lock:** User-configurable 5–30 minutes timer or immediate on app backgrounding / tab blur, requiring Biometric / PIN unlock (`local_auth`) or master password re-entry.

---

## 2. Platform-Specific Authentication Flows

### 2.1 Android Mobile Flow

```text
┌────────────────────────────────────────────────────────────────────────┐
│                              ANDROID FLOW                              │
│                                                                        │
│  1. Login / Register:                                                  │
│     • User inputs Email + Master Password.                             │
│     • Master password derives session key in memory via PBKDF2/Argon2. │
│     • POST /api/auth/login -> FastAPI verifies Argon2id hash.          │
│     • Server returns { access_token (10m), refresh_token (10d) }.      │
│                                                                        │
│  2. Token & Key Storage:                                               │
│     • refresh_token saved to Android Keystore (flutter_secure_storage). │
│     • access_token kept in memory / Dio auth interceptor.              │
│     • AES session key kept in memory (and secure storage for PIN/Bio). │
│                                                                        │
│  3. Authenticated Requests & Auto-Refresh:                             │
│     • Dio attaches `Authorization: Bearer <access_token>` to requests. │
│     • On HTTP 401 Unauthorized:                                        │
│         - Interceptor pauses request queue.                            │
│         - Calls POST /api/auth/refresh with refresh_token.             │
│         - FastAPI validates token_hash in DB & checks revoked_at.      │
│         - Returns new access_token (and rotated refresh_token).        │
│         - Dio updates memory and retries original request once.        │
│                                                                        │
│  4. App Backgrounding & Vault Lock (5-30 mins / user selectable):      │
│     • App enters background / idle timer expires -> Vault is locked.   │
│     • In-memory plaintext is scrubbed.                                 │
│     • On resume -> Prompt Biometric / PIN via local_auth.              │
│     • Unlock restores session key without re-entering master password. │
│                                                                        │
│  5. Expiration & Forced Logout:                                        │
│     • If refresh token expires (after 10 days) or is revoked:          │
│         - Refresh returns 401 Unauthorized.                            │
│         - Clear flutter_secure_storage and local cache tokens.         │
│         - Erase session key from memory.                               │
│         - Route user to Master Login screen.                           │
└────────────────────────────────────────────────────────────────────────┘
```

---

### 2.2 Web Browser Flow

```text
┌────────────────────────────────────────────────────────────────────────┐
│                                WEB FLOW                                │
│                                                                        │
│  1. Login / Register:                                                  │
│     • User inputs Email + Master Password.                             │
│     • Master password derives AES session key in volatile memory.      │
│     • POST /api/auth/login -> FastAPI issues access (10m) & refresh (8h).│
│                                                                        │
│  2. Token & Key Storage:                                               │
│     • refresh_token saved in flutter_secure_storage (Web Crypto / SS). │
│     • access_token retained in memory / Dio client.                    │
│     • Plaintext master password is never stored or cached.             │
│                                                                        │
│  3. Inactivity, Vault Lock (5-30 mins) & Tab Closing:                  │
│     • When idle timer (5-30m) expires or browser tab closed:           │
│         - AES session key in memory is discarded / vault locked.       │
│         - Next visit requires Master Password unlock.                  │
│     • If refresh token is valid (within 8 hours):                      │
│         - Silent refresh obtains fresh access_token (10m) on unlock.   │
│     • If refresh token expired:                                        │
│         - Full login required.                                         │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. End-to-End Token Lifecycle Diagram

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App as Flutter Client (Dio)
    participant SecStore as Secure Storage (Keystore)
    participant API as FastAPI Backend
    participant DB as PostgreSQL (Supabase)

    Note over User,DB: Phase 1: Authentication & Token Issuance
    User->>App: Enter Email + Master Password
    App->>App: Derive AES-256 Session Key (PBKDF2/Argon2)
    App->>API: POST /api/auth/login { email, password, client_type }
    API->>DB: Query user by email
    API->>API: Verify password with Argon2id
    API->>API: Sign access_token (10m, type=access)<br/>Sign refresh_token (10d Android / 8h Web, type=refresh)
    API->>DB: INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
    API-->>App: 200 OK { access_token, refresh_token }
    App->>SecStore: Write refresh_token & session key
    App->>App: Store access_token in memory

    Note over User,DB: Phase 2: Normal Authenticated API Requests
    App->>API: GET /api/vault/entries (Header: Bearer <access_token>)
    API->>API: Verify JWT signature & type == "access"
    API->>DB: SELECT * FROM vault_entries WHERE user_id = :sub
    API-->>App: 200 OK [encrypted_entries]

    Note over User,DB: Phase 3: Access Token Expiration & Transparent Refresh
    Note over App,API: (10 minutes elapse; Access Token expires)
    App->>API: GET /api/vault/entries (Expired Access Token)
    API-->>App: 401 Unauthorized (TokenExpired)
    
    Note over App: Dio Interceptor intercepts 401
    App->>SecStore: Read refresh_token
    App->>API: POST /api/auth/refresh { refresh_token }
    API->>API: Verify JWT signature & type == "refresh"
    API->>DB: SELECT * FROM refresh_tokens WHERE token_hash = SHA256(token) AND revoked_at IS NULL
    API->>API: Generate new access_token (10m)
    API-->>App: 200 OK { access_token, refresh_token }
    App->>App: Update in-memory access_token
    App->>API: Retry original GET /api/vault/entries (New Token)
    API-->>App: 200 OK [encrypted_entries]

    Note over User,DB: Phase 4: Logout & Server-Side Revocation
    User->>App: Click "Log Out"
    App->>SecStore: Read refresh_token
    App->>API: POST /api/auth/logout { refresh_token }
    API->>DB: UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = SHA256(token)
    API-->>App: 200 OK { message: "Session revoked" }
    App->>SecStore: Clear refresh_token & session keys
    App->>App: Wipe in-memory keys & cache -> Navigate to Login
```

---

## 4. Deterministic Failure Handling Rules

The client adheres to strict deterministic rules when handling authentication states:

```text
Scenario 1: Access Token Expired, Refresh Token Valid
├── Dio catches 401 Unauthorized
├── Calls POST /api/auth/refresh
├── Server validates token_hash against DB (revoked_at IS NULL)
├── Server returns fresh access_token
└── Dio retries failed request once -> SUCCESS

Scenario 2: Refresh Token Expired or Revoked (Logout / Remote Session Kill)
├── Dio catches 401 Unauthorized
├── Calls POST /api/auth/refresh
├── Server returns 401 Unauthorized (Invalid / Expired / Revoked)
├── Client immediately halts all outgoing network requests
├── Client clears flutter_secure_storage (tokens and cached session key)
├── Client erases in-memory cryptographic keys
├── Vault enters hard-locked state
└── UI routes to Master Password Login Screen

Scenario 3: Device Offline During Access Token Expiry
├── API request fails with Connection/Socket error (not 401)
├── Client does NOT invalidate tokens or session
├── App falls back seamlessly to local cache (sqflite / Hive)
└── Vault remains unlocked and operational locally
```

---

## 5. Security & Threat Mitigation

| Security Concern | Mitigation Strategy |
| :--- | :--- |
| **Token Theft from Database Breach** | Refresh tokens are stored strictly as **SHA-256 digests** in the `refresh_tokens` table. A leaked database does not expose raw bearer tokens. |
| **Access Token Interception** | Short 10-minute lifespan minimizes the vulnerability window; all transport enforced over HTTPS / TLS 1.3. |
| **Replay & Token Confusion Attacks** | Single secret with explicit `type: "access"` and `type: "refresh"` claims prevents swapping access tokens for refresh endpoints and vice-versa. |
| **Brute Force & Credential Stuffing** | `slowapi` rate limiting limits `/api/auth/login` and `/api/auth/refresh` to **5 requests per minute per IP**. |
| **Stolen / Lost Device** | Calling `POST /api/auth/logout` sets `revoked_at = NOW()`, permanently blacklisting the refresh token on the backend. |

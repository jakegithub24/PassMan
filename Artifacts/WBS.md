# WBS.md
## Work Breakdown Structure — Cross-Platform Password Manager MVP

Companion to `MVP.md` (scope/schema), `ARCHITECTURE_DESIGN.md` (system design), `PRD.md` (requirements), and `TRD.md` (technical specs). This document breaks the 13-day schedule into task-level units with dependencies, so work can be sequenced and tracked day-to-day.

**Legend:** `[B]` Backend · `[F]` Flutter · `[I]` Infra/DevOps · `[T]` Testing

---

## Phase 1 — Foundations (Days 1–2)

### 1.0 Project Setup — Day 1
| ID | Task | Depends On | Status |
| :-- | :-- | :-- | :-- |
| 1.1 | `[I]` Create Supabase project, note connection string | — | |
| 1.2 | `[B]` Init FastAPI project (Poetry/venv), base folder structure (`routers/`, `services/`, `models/`) | 1.1 | |
| 1.3 | `[B]` Write schema DDL: `users`, `vault_entries` (with `deleted_at`), `refresh_tokens`, `audit_logs` | 1.1 | |
| 1.4 | `[B]` Apply schema to Supabase, verify indexes (`idx_vault_user_sync`) | 1.3 | |
| 1.5 | `[F]` `flutter create`, add core deps: `dio`, `riverpod`, `sqflite`, `hive`, `crypto`, `flutter_secure_storage`, `local_auth` | — | |
| 1.6 | `[I]` `.env` scaffolding for FastAPI (DB URL, JWT secret, token expiries) | 1.2 | |

**Exit criteria:** FastAPI boots locally and connects to Supabase; Flutter project builds on Android + Web targets with no errors.

### 2.0 Backend Auth — Day 2
| ID | Task | Depends On | Status |
| :-- | :-- | :-- | :-- |
| 2.1 | `[B]` Pydantic models: `UserCreate`, `UserLogin`, `TokenPair` | 1.2 | |
| 2.2 | `[B]` `argon2-cffi` hashing service (hash + verify) | 2.1 | |
| 2.3 | `[B]` `POST /api/auth/register` | 2.2 | |
| 2.4 | `[B]` JWT service: single secret, `type` claim (`access`/`refresh`), platform expiries (10m access; 10d Android / 8h Web refresh) | 2.1 | |
| 2.5 | `[B]` `POST /api/auth/login` — verify Argon2id, issue token pair, insert hashed refresh token row | 2.2, 2.4 | |
| 2.6 | `[B]` `POST /api/auth/refresh` — validate refresh hash + expiry, rotate access token | 2.4, 2.5 | |
| 2.7 | `[B]` `POST /api/auth/logout` — set `revoked_at` on refresh token | 2.5 | |
| 2.8 | `[B]` `get_current_user` dependency (decode + validate JWT `type=access`) | 2.4 | |

**Exit criteria:** Register → login → refresh → logout works end-to-end via curl/Postman; no plaintext password ever appears in logs or DB.

---

## Phase 2 — Core API (Days 3–4)

### 3.0 Vault CRUD — Day 3
| ID | Task | Depends On | Status |
| :-- | :-- | :-- | :-- |
| 3.1 | `[B]` `POST /api/vault/entries` — accept `{ciphertext, iv, tag}` only, reject any plaintext-shaped field | 2.8 | |
| 3.2 | `[B]` `PUT /api/vault/entries/{id}` — ownership check, bump `updated_at` | 3.1 | |
| 3.3 | `[B]` `DELETE /api/vault/entries/{id}` — soft delete: set `deleted_at`, bump `updated_at` | 3.1 | |
| 3.4 | `[B]` `GET /api/vault/entries?since=<ts>` — delta query, **includes** tombstoned rows | 3.1 | |
| 3.5 | `[B]` `GET /api/vault/sync/status` — return server `NOW()` | 2.8 | |
| 3.6 | `[B]` Ownership guard applied consistently (`WHERE user_id = current_user.id`) across all 4 routes | 3.1–3.4 | |

**Exit criteria:** Full CRUD + delta sync verified via Postman with two seeded users, confirming no cross-user data leakage.

### 4.0 Middleware & Security — Day 4
| ID | Task | Depends On | Status |
| :-- | :-- | :-- | :-- |
| 4.1 | `[B]` CORS middleware — allowlist Web deploy origin + localhost only | 1.2 | |
| 4.2 | `[B]` `slowapi` rate limiter — 5/min on `/login` and `/refresh` | 2.5, 2.6 | |
| 4.3 | `[B]` Request logging middleware (method/path/status/duration) | 1.2 | |
| 4.4 | `[B]` Wire logging middleware to async `audit_logs` insert (LOGIN/REFRESH/SYNC/CRUD actions) | 4.3, 3.6 | |

**Exit criteria:** Rate limit confirmed to block a 6th rapid login attempt; audit log rows appear correctly for each action type.

---

## Phase 3 — Client Foundations (Days 5–6)

### 5.0 Flutter Auth + Networking — Day 5
| ID | Task | Depends On | Status |
| :-- | :-- | :-- | :-- |
| 5.1 | `[F]` Login/Signup screens (form validation only, no crypto yet) | 1.5 | Done |
| 5.2 | `[F]` Riverpod `AuthState` provider | 5.1 | Done |
| 5.3 | `[F]` Dio client base config + JWT-attach interceptor | 1.5 | Done |
| 5.4 | `[F]` 401 interceptor: call `/auth/refresh`, retry original request once, else force logout | 5.3, 2.6 | Done |
| 5.5 | `[F]` Token storage via `flutter_secure_storage` (Android + Web) | 5.3 | Done |

**Exit criteria:** Live login against backend from Day 2; simulated 401 correctly triggers refresh-and-retry.

### 6.0 Encryption Layer — Day 6
| ID | Task | Depends On | Status |
| :-- | :-- | :-- | :-- |
| 6.1 | `[F]` Key derivation from master password (PBKDF2/Argon2 in Dart) → session key | 5.2 | Done |
| 6.2 | `[F]` AES-256-GCM encrypt function → `{ciphertext, iv, tag}` | 6.1 | Done |
| 6.3 | `[F]` AES-256-GCM decrypt function | 6.1 | Done |
| 6.4 | `[F]` Round-trip unit test: plaintext → encrypt → decrypt → match | 6.2, 6.3 | Done |
| 6.5 | `[F]` Session key stored only in `flutter_secure_storage`, never written to local cache DB | 6.1, 5.5 | Done |

**Exit criteria:** Encrypt/decrypt round-trip test passes; manual inspection confirms only ciphertext is ever sent over the wire (verify against backend logs from 4.3).

---

## Phase 4 — Vault UI & Local Cache (Days 7–8)

### 7.0 Flutter Vault UI — Day 7
| ID | Task | Depends On | Status |
| :-- | :-- | :-- | :-- |
| 7.1 | `[F]` `VaultState` provider (list, add, edit, delete) | 5.2, 6.2 | |
| 7.2 | `[F]` Vault list screen | 7.1 | |
| 7.3 | `[F]` Add/edit entry form → encrypts before send | 7.1, 6.2 | |
| 7.4 | `[F]` Delete confirmation flow | 7.1 | |
| 7.5 | `[F]` Search + copy-to-clipboard on entry | 7.2 | |
| 7.6 | `[F]` Wire list/add/edit/delete to CRUD endpoints (3.1–3.4) | 7.1–7.4 | |

**Exit criteria:** Full CRUD usable end-to-end online, decrypting correctly on read.

### 8.0 Local Cache — Day 8
| ID | Task | Depends On | Status |
| :-- | :-- | :-- | :-- |
| 8.1 | `[F]` Define shared `local_vault_cache` table/box shape (per `MVP.md §3`) | 7.1 | |
| 8.2 | `[F]` `sqflite` implementation (Android) | 8.1 | |
| 8.3 | `[F]` `Hive` implementation (Web) — same interface as 8.2 | 8.1 | |
| 8.4 | `[F]` Cache repository abstraction so UI/sync code is platform-agnostic | 8.2, 8.3 | |
| 8.5 | `[F]` App launch reads cache first, renders instantly before any network call | 8.4 | |

**Exit criteria:** Killing network access still shows the last-synced vault instantly on both platforms.

---

## Phase 5 — Sync & Device Security (Days 9–10)

### 9.0 Sync Engine — Day 9
| ID | Task | Depends On | Status |
| :-- | :-- | :-- | :-- |
| 9.1 | `[F]` Trigger hooks: app launch, resume-from-background, manual pull-to-refresh | 8.5 | |
| 9.2 | `[F]` Delta fetch (`GET /entries?since=`) + `last_synced_at` persistence | 9.1, 3.4 | |
| 9.3 | `[F]` LWW merge logic: tombstone → remove; server newer → overwrite; local newer → queue push | 9.2 | |
| 9.4 | `[F]` Push queue: pending `is_pending_sync=1` rows → `POST`/`PUT`/`DELETE`, clear flag on success | 9.3, 3.1–3.3 | |
| 9.5 | `[F]` "Sync Now" manual button wired to the same engine | 9.1 | |

**Exit criteria:** Two-device manual test — edit on Device A offline, go online, confirm Device B reflects the change (including deletes) after sync trigger.

### 10.0 Device-Level Auth & Auto-Lock — Day 10
| ID | Task | Depends On | Status |
| :-- | :-- | :-- | :-- |
| 10.1 | `[F]` `local_auth` biometric/PIN gate on app open | 6.5 | |
| 10.2 | `[F]` User-selectable auto-lock timer (5–30 min) & background lock (`paused`/`inactive`), requiring re-auth on resume | 10.1 | |
| 10.3 | `[F]` Confirm session key never persists outside `flutter_secure_storage` across lock/unlock cycles | 10.1, 6.5 | |

**Exit criteria:** App locks on background or after user-configured inactivity (5-30m) without biometric/PIN; session key survives unlock without re-derivation from master password (unless secure storage was cleared).

---

## Phase 6 — Testing, Fixes, Release (Days 11–13)

### 11.0 Testing — Day 11
| ID | Task | Depends On | Status |
| :-- | :-- | :-- | :-- |
| 11.1 | `[T]` `pytest-asyncio` suite: auth flow, CRUD ownership, rate limit, soft-delete behavior | 2.x, 3.x, 4.x | |
| 11.2 | `[T]` Flutter widget tests: auth screens, vault list, add/edit form | 5.x, 7.x | |
| 11.3 | `[T]` Manual test: offline edit → reconnect → sync → verify on second device | 9.x | |
| 11.4 | `[T]` Manual test: delete propagation across devices (tombstone) | 9.x | |
| 11.5 | `[T]` Manual test: access token expiry mid-session → transparent refresh | 5.4 | |
| 11.6 | `[T]` Manual test: refresh token expiry/revocation → forced logout | 5.4, 2.6, 2.7 | |

**Exit criteria:** All automated tests pass; all 4 manual scenarios confirmed on both Android and Web.

### 12.0 Bug Fixing & Polish — Day 12
| ID | Task | Depends On | Status |
| :-- | :-- | :-- | :-- |
| 12.1 | Triage and fix issues surfaced in Day 11 testing | 11.x | |
| 12.2 | `[F]` UI polish pass (loading states, error messaging, empty states) | 12.1 | |
| 12.3 | `[B]` Dio/FastAPI error response consistency check | 12.1 | |
| 12.4 | `[I]` Cross-origin CORS re-verified against actual Web deploy domain | 4.1 | |

**Exit criteria:** No known P0/P1 bugs open; UI has no dead-end states.

### 13.0 Release — Day 13
| ID | Task | Depends On | Status |
| :-- | :-- | :-- | :-- |
| 13.1 | `[I]` Deploy FastAPI to Render/Fly.io, set production `.env` | 12.x | |
| 13.2 | `[I]` Point production build at Supabase prod instance | 13.1 | |
| 13.3 | `[F]` Build Android release APK | 12.x | |
| 13.4 | `[F]` Build Flutter Web bundle, deploy (e.g. Netlify) | 12.x | |
| 13.5 | `[I]` Update CORS allowlist with final production Web URL | 13.4, 4.1 | |
| 13.6 | Write README (setup, run, deploy instructions) | 13.1–13.4 | |

**Exit criteria:** Fresh install (APK) and fresh browser session (Web URL) both complete register → use → sync against production successfully.

---

## Dependency Chain Summary (Critical Path)

```
1.1→1.2→1.3→1.4      (Supabase + schema)
1.5                   (Flutter init, parallel)
        │
2.1→2.2→2.4→2.5→2.6→2.7→2.8   (Auth backend)
        │
3.1→3.2/3.3→3.4→3.6           (Vault CRUD)
        │
4.1/4.2/4.3→4.4                (Middleware)
        │
5.1→5.2→5.3→5.4→5.5            (Flutter auth/net)
        │
6.1→6.2/6.3→6.4→6.5            (Encryption)
        │
7.1→7.2/7.3/7.4/7.5→7.6        (Vault UI)
        │
8.1→8.2/8.3→8.4→8.5            (Local cache)
        │
9.1→9.2→9.3→9.4→9.5            (Sync engine)  ← highest-risk phase
        │
10.1→10.2→10.3                  (Device auth)
        │
11.x → 12.x → 13.x               (Test, fix, release)
```

**Highest-risk node:** Phase 5 (Sync Engine, Day 9). Everything upstream (auth, CRUD, encryption, cache) is individually straightforward; sync is where those pieces interact and where LWW/tombstone bugs are most likely to surface. If schedule pressure hits, protect Day 9's scope before trimming polish on Day 12.

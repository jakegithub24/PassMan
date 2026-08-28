# System Limitations & Constraints (LIMITATIONS.md)
## PassMan — Cross-Platform Password Manager MVP

**Version:** 1.0 (MVP)  
**Last Updated:** August 2026  

This document outlines the architectural trade-offs, scope boundaries, security constraints, and technical limitations deliberately adopted in the MVP release of **PassMan**.

---

## 1. Scope & Functional Boundaries (MVP Omissions)

### 1.1 No Password Reset / Account Recovery via Email
- **Limitation:** There is no automated "Forgot Password" or SMTP-based password reset mechanism in the MVP.
- **Rationale:** 
  1. In a true Zero-Knowledge system, the server does not possess the encryption keys. An automated email reset cannot decrypt existing vault data without an escrowed recovery key.
  2. Building and auditing a secure recovery kit flow (with multi-word mnemonic seed phrases or Shamir's Secret Sharing) along with SMTP deliverability exceeds the 13-day MVP schedule.
- **Mitigation / Fallback:** If a user loses their master password, their vault data is mathematically unrecoverable. Users must create a new account. A full recovery-key protocol is planned for v1.1.

### 1.2 No Real-Time WebSocket / Push Notification Sync
- **Limitation:** The MVP does not support instant server-initiated push synchronization (e.g., Supabase Realtime, WebSockets, or Firebase Cloud Messaging).
- **Rationale:** A continuous background WebSocket connection or 30-second polling loop drains mobile battery and mobile data quotas for a utility tool that does not require sub-second multi-user collaboration.
- **Mitigation:** Synchronization triggers deterministically on three discrete events: **App Launch**, **App Resume from Background**, and **Manual Pull-to-Refresh ("Sync Now")**.

### 1.3 Single-User Vaults (No Sharing / Teams / Organizations)
- **Limitation:** Vault entries cannot be shared between multiple users, and there are no organizational permission hierarchies.
- **Rationale:** Cryptographic sharing requires asymmetric public-key infrastructure (e.g., RSA/ECC key pairs per user, encrypted key envelopes per entry). This is deferred to enterprise/team roadmaps.

### 1.4 No Browser Extension & Desktop Native Builds
- **Limitation:** PassMan MVP ships as an **Android APK** and a **Flutter Web Application**. Browser autofill extensions (Chrome/Firefox/Brave) and native desktop binaries (macOS/Windows/Linux) are not included in v1.0.
- **Mitigation:** Desktop users can access their vault via the secure Flutter Web portal and utilize manual copy-to-clipboard functionality.

---

## 2. Cryptographic & Security Constraints

### 2.1 Irreversible Data Loss on Master Password Loss (Zero-Knowledge Invariant)
- **Constraint:** By design, the server never receives or stores the master password, PBKDF2/Argon2 derived session keys, or unencrypted vault payloads.
- **Implication:** The engineering team and server administrators have no mathematical or backdoor capability to recover user credentials. If the user forgets their master password, all vault records are permanently inaccessible.

### 2.2 Local Storage Security Boundaries (Ciphertext at Rest)
- **Constraint:** `sqflite` (Android) and `Hive` (Web) store raw AES-256-GCM ciphertext blobs rather than utilizing secondary whole-database encryption (e.g., SQLCipher).
- **Security Posture:** 
  - Vault entries are already encrypted with AES-256-GCM prior to entering local storage. Encrypting ciphertext again provides no meaningful security advantage.
  - The security of the local store relies strictly on the isolation of the **session key**, which is protected in the hardware-backed **Android Keystore / Keychain** via `flutter_secure_storage`.
  - If a device is compromised at the root/kernel level, secondary database encryption with a key in memory would be equally vulnerable.

### 2.3 Web Platform Storage Isolation Limits
- **Constraint:** On the Web platform, `flutter_secure_storage` relies on browser storage mechanisms (IndexedDB/Web Cryptography API) and session cookies/in-memory tokens.
- **Implication:** The Web client does not have access to a hardware Secure Enclave or hardware-backed Android Keystore. Users on shared/public computers must explicitly log out and clear browser caches to prevent session hijacking.

### 2.4 Single JWT Secret with Claim-Based Differentiation
- **Constraint:** Both Access Tokens (10 min) and Refresh Tokens (Android: 10 days, Web: 8 hours) are signed using a single server `JWT_SECRET_KEY` and differentiated via the `type` claim (`type="access"` vs `type="refresh"`).
- **Implication:** If the server's `JWT_SECRET_KEY` is compromised, all active access and refresh tokens become invalid. A secret rotation invalidates all existing sessions immediately.

---

## 3. Data Synchronization & Concurrency Limitations

### 3.1 Last-Write-Wins (LWW) Conflict Resolution
- **Constraint:** When the same vault entry is edited concurrently on two offline devices, the server accepts the latest timestamp (`updated_at`), overwriting previous changes.
- **Limitation:** There is no field-level 3-way merge or interactive conflict resolution UI in MVP.
- **Edge Case:** If Device A updates the password at `12:00:00` and Device B updates the notes at `12:00:05` while both are offline, Device B's version will completely overwrite Device A's record upon synchronization.

### 3.2 Clock Skew Dependency
- **Constraint:** Delta sync queries rely on ISO-8601 timestamps (`GET /api/vault/entries?since=<ts>`).
- **Mitigation:** The client obtains and synchronizes against the **server's authoritative clock** (`GET /api/vault/sync/status`) during synchronization cycles rather than relying solely on local device system time, mitigating local clock drift.

### 3.3 Soft-Delete Tombstone Retention
- **Constraint:** Deleting an entry marks `deleted_at = NOW()` rather than executing a hard SQL `DELETE`.
- **Implication:** Soft-deleted rows remain in PostgreSQL to allow offline devices that haven't synced in days/weeks to receive the deletion notification.
- **Future Maintenance:** A background database retention policy / cron job will be required in post-MVP releases to purge tombstones older than 90 days.

---

## 4. Backend & Infrastructure Constraints

### 4.1 FastAPI Service-Level Authorization vs. Database RLS
- **Constraint:** PostgreSQL Row Level Security (RLS) is intentionally not enabled in Supabase for the FastAPI connection.
- **Rationale:** FastAPI connects to Supabase via a direct TCP pooler using a single service-role credential (`postgresql://...`). Because PostgreSQL sees all incoming connections under the same DB user, Postgres-level RLS policies cannot evaluate user-specific claims.
- **Limitation:** Tenant isolation relies strictly on the FastAPI application layer (`WHERE user_id = current_user.id` on every query). A bug in the FastAPI service layer could bypass user isolation.

### 4.2 In-Memory Rate Limiting
- **Constraint:** In the MVP deployment, `slowapi` rate limiting (5 req/min on `/login` and `/refresh`) defaults to in-memory tracking.
- **Implication:** If the FastAPI backend is scaled horizontally across multiple instances (e.g., multiple Fly.io or Render containers) without a shared Redis instance, rate limits apply per container rather than globally.

### 4.3 Database Connection Limits
- **Constraint:** Supabase Free/Pro tiers impose connection limits on direct PostgreSQL connections.
- **Mitigation:** FastAPI must connect through the Supabase Transaction / Session Pooler (port 6543 / 5432) with a configured `pool_size` (e.g., max 10–20 connections per API worker) to avoid exhausting PostgreSQL connection slots.

---

## 5. Platform Compatibility Matrix & Restrictions

| Platform | Minimum Supported Version | Hardware / Feature Requirements | Known Limitations |
| :--- | :--- | :--- | :--- |
| **Android** | Android 5.0 (API Level 21) | Hardware Keystore, Biometric sensor / PIN | Rooted devices bypass OS sandboxing; background sync depends on OS battery saver policies. |
| **Web** | Modern Evergreen Browsers (Chrome 90+, Firefox 88+, Safari 14+, Edge 90+) | Web Cryptography API, IndexedDB enabled | No background lock when browser tab is inactive unless closed; storage vulnerable if browser profile is shared. |
| **iOS** | *Not Supported in MVP* | Apple Secure Enclave | Deferred to v1.1. |
| **Desktop** | *Not Supported in MVP* | Windows Hello / Touch ID | Web client recommended. |

---

## 6. Summary Matrix: What PassMan MVP Is vs. What It Is Not

| PassMan MVP IS: | PassMan MVP IS NOT: |
| :--- | :--- |
| **A Zero-Knowledge Vault:** Server only holds encrypted blobs. | **A Master Password Recovery Service:** No master key backdoors. |
| **An Offline-First Tool:** Instant local access and queuing. | **A Real-Time Collaborative Workspace:** No live WebSocket sync. |
| **A Lightweight Single-User Manager:** Fast, focused, robust. | **An Enterprise IAM / Team Credential Vault:** No multi-tenant RBAC. |
| **A Determinate Sync Engine:** LWW conflict handling with tombstones. | **A 3-Way Semantic Merge Engine:** Does not merge individual fields. |

# PassMan 🔐
### Offline-First, Zero-Knowledge Cross-Platform Password Manager

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.110+-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org)
[![Supabase](https://img.shields.io/badge/Supabase-Database-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![AES-256-GCM](https://img.shields.io/badge/Cryptography-AES--256--GCM-blueviolet)]()
[![Argon2id](https://img.shields.io/badge/Password%20Hash-Argon2id-critical)]()
[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

**PassMan** is a secure, lightweight, and modern cross-platform password manager for **Android** and **Web**. Built on an uncompromising **Zero-Knowledge** foundation, PassMan ensures that your passwords and secrets are encrypted on your device before they ever touch the network or database. With its **Offline-First** architecture, PassMan offers instant local access and seamless delta synchronization across devices.

---

## 📑 Comprehensive Documentation Index

All system specifications, design decisions, and operational runbooks are thoroughly documented:

| Document | Description |
| :--- | :--- |
| 📄 [**`PRD.md`**](Artifacts/PRD.md) | **Product Requirements Document:** Vision, personas, user journeys, functional & non-functional requirements, scope boundaries, and acceptance criteria. |
| 📄 [**`TRD.md`**](Artifacts/TRD.md) | **Technical Requirements Document:** Architecture, PostgreSQL schemas/DDL, unified local cache, cryptographic parameters, API contracts, and sync engine algorithms. |
| 📄 [**`LIMITATIONS.md`**](Artifacts/LIMITATIONS.md) | **System Limitations & Constraints:** Deliberate MVP trade-offs (no SMTP reset, zero-knowledge unrecoverability, LWW conflict limits, storage boundaries). |
| 📄 [**`DEPLOYMENT.md`**](Artifacts/DEPLOYMENT.md) | **Deployment & Operations Guide:** Production setup for Supabase Postgres, Dockerized FastAPI (Fly.io/Render), Flutter Web (Netlify), and signed Android release builds. |
| 📂 [**`Artifacts/`**](Artifacts/) | **Core Design Artifacts:**<br/>• [`MVP.md`](Artifacts/MVP.md) — 13-day MVP scope, tech stack, endpoints, and schema.<br/>• [`ARCHITECTURE_DESIGN.md`](Artifacts/ARCHITECTURE_DESIGN.md) — Structural design, security boundaries, and trade-off rationales.<br/>• [`AUTH_TOKEN_LOGIC.md`](Artifacts/AUTH_TOKEN_LOGIC.md) — Dual-token lifecycle, 401 retry interceptor, and vault locking.<br/>• [`WBS.md`](Artifacts/WBS.md) — Task-level Work Breakdown Structure and dependency chain. |

---

## ✨ Key Features & Highlights

- **🔒 Zero-Knowledge Cryptography:** Vault items are encrypted client-side using **AES-256-GCM** (with unique 96-bit IVs and 128-bit authentication tags). The server only processes and stores opaque ciphertext blobs (`{ ciphertext, iv, tag }`).
- **⚡ Offline-First Performance:** Instant UI startup (<200ms) by loading directly from local storage (`sqflite` on Android, `Hive` on Web). Full read, search, add, edit, and delete operations work completely offline.
- **🔄 Deterministic Delta Sync:** Queries `GET /api/vault/entries?since=<last_synced_at>` to pull only changes. Uses **Last-Write-Wins (LWW)** and **soft-delete tombstones** to ensure deleted items cleanly propagate across all devices.
- **🛡️ Battle-Tested Authentication:** Master passwords hashed server-side with memory-hard **Argon2id**. Platform-aware dual-token JWT (10-min Access; 10-day Android / 8-hour Web Refresh) with server-side revocation tracking and transparent HTTP 401 auto-refresh via Dio interceptors.
- **👆 Mobile & Web Device Security:** Hardware-backed session key storage via `flutter_secure_storage` (Android Keystore), user-selectable auto-lock timer (5–30 minutes), and biometric/PIN auto-lock on app backgrounding via `local_auth`.
- **🚫 Unified Storage (No Double Encryption):** Avoids redundant double-encryption layers (SQLCipher) since data is already ciphertext; concentrates hardware protection strictly on the cryptographic session key.

---

## 🏛️ System Architecture & Security Boundary

```text
┌──────────────────────── TRUSTED BOUNDARY: CLIENT DEVICE ────────────────────────┐
│  • Master Password input                                                       │
│  • Key Derivation: Master Password + User Salt ──► AES-256 Session Key          │
│  • AES-256-GCM: Plaintext Entry ◄──► { ciphertext, iv, tag }                   │
│  • Session Key stored strictly in Keystore / flutter_secure_storage            │
│  • Unified Local Cache: sqflite (Android) / Hive (Web)                         │
└───────────────────────────────────────┬────────────────────────────────────────┘
                                        │ HTTPS / TLS 1.3
                                        │ Payload: { ciphertext, iv, tag }
┌───────────────────────────────────────▼────────────────────────────────────────┐
│                     UNTRUSTED BOUNDARY: SERVER & DATABASE                      │
│  • FastAPI: JWT validation, rate limiting (5 req/min), ownership enforcement   │
│  • Supabase (PostgreSQL 15): users, vault_entries, refresh_tokens, audit_logs  │
│  • Server has ZERO capability to decrypt vault entries or recover passwords    │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Technology Stack

| Layer | Technology | Key Libraries / Components |
| :--- | :--- | :--- |
| **Frontend (Mobile & Web)** | Flutter SDK 3.x (Dart 3.x) | `flutter_riverpod`, `dio`, `sqflite`, `hive`, `flutter_secure_storage`, `local_auth` |
| **Backend API** | Python 3.11+ / FastAPI | `uvicorn`, `pydantic` v2, `SQLAlchemy` (async), `asyncpg`, `argon2-cffi`, `slowapi`, `PyJWT` |
| **Cloud Database** | Supabase (PostgreSQL 15) | Direct connection / Transaction pooler (Port 5432 / 6543) |
| **Container & Hosting** | Docker, Fly.io / Render, Netlify | Multi-stage Dockerfile, Netlify SPA headers |

---

## 🚀 Getting Started & Local Development

### 1. Prerequisites
- [Flutter SDK 3.19+](https://docs.flutter.dev/get-started/install)
- [Python 3.11+](https://www.python.org/downloads/) & [Poetry](https://python-poetry.org/) or `venv`
- [Docker](https://www.docker.com/) (optional, for containerized run)
- A free [Supabase](https://supabase.com) PostgreSQL database

---

### 2. Backend Setup (FastAPI)

1. **Clone the repository:**
   ```bash
   git clone https://github.com/jakegithub24/PassMan.git
   cd PassMan/backend
   ```

2. **Create virtual environment and install dependencies:**
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   pip install -r requirements.txt
   ```

3. **Configure Environment Variables (`.env`):**
    Create a `.env` file in the `backend/` directory:
    ```env
    DATABASE_URL=postgresql+asyncpg://postgres:[PASSWORD]@aws-0-[REGION].pooler.supabase.com:6543/postgres
    JWT_SECRET_KEY=your_super_secret_64_char_random_hex_key
    ALGORITHM=HS256
    ANDROID_ACCESS_TOKEN_EXPIRES=10
    ANDROID_REFRESH_TOKEN_EXPIRES=10
    ANDROID_VAULT_LOCK=15
    WEB_ACCESS_TOKEN_EXPIRES=10
    WEB_REFRESH_TOKEN_EXPIRES=8
    WEB_VAULT_LOCK=15
    CORS_ORIGINS=http://localhost:3000,http://localhost:8080,http://127.0.0.1:8000
    ENVIRONMENT=development
    ```

4. **Initialize Database Schema:**
   Run the schema migration SQL against your Supabase instance as detailed in [Section 3 of `DEPLOYMENT.md`](Artifacts/DEPLOYMENT.md#3-database-setup-supabase--postgresql).

5. **Start the API server:**
   ```bash
   uvicorn main:app --reload --host 0.0.0.0 --port 8000
   ```
   Interactive OpenAPI documentation will be available at: `http://localhost:8000/docs`

---

### 3. Frontend Setup (Flutter)

1. **Navigate to the frontend directory:**
   ```bash
   cd ../frontend
   flutter pub get
   ```

2. **Run on Web:**
   ```bash
   flutter run -d chrome --dart-define=API_URL=http://localhost:8000
   ```

3. **Run on Android Emulator / Physical Device:**
   ```bash
   flutter run -d android --dart-define=API_URL=http://10.0.2.2:8000
   ```
   *(Note: `10.0.2.2` maps to the host machine `localhost` inside the standard Android emulator).*

---

## 🧪 Testing & Quality Assurance

### Run Backend Tests
```bash
cd backend
pytest tests/ -v
```

### Run Flutter Client Tests
```bash
cd frontend
flutter test
```

---

## 📦 Production Builds & Deployment

### Build Android Release APK & App Bundle
```bash
cd frontend
# Build APK
flutter build apk --release --dart-define=API_URL=https://api.passman.example.com
# Build Google Play Bundle (AAB)
flutter build appbundle --release --dart-define=API_URL=https://api.passman.example.com
```

### Build Flutter Web Static Bundle
```bash
cd frontend
flutter build web --release \
  --dart-define=API_URL=https://api.passman.example.com \
  --web-renderer canvaskit
```

For complete step-by-step production deployment instructions (Docker, Fly.io, Render, Netlify, KeyStore signing), refer to [**`DEPLOYMENT.md`**](Artifacts/DEPLOYMENT.md).

---

## 🔒 Security Model & Best Practices

- **Zero-Knowledge Invariant:** PassMan servers never receive plaintext passwords or encryption keys.
- **Single-Layer Storage:** Local storage records ciphertext; session keys are stored strictly in hardware keystores.
- **Rate-Limiting:** Authentication endpoints are rate-limited to 5 requests per minute per IP address.
- **Audit Trails:** Sensitive events (`LOGIN`, `REFRESH`, `SYNC`, `CREATE`, `UPDATE`, `DELETE`) are logged asynchronously.

For a full breakdown of threat models and limitations, see [**`TRD.md`**](Artifacts/TRD.md) and [**`LIMITATIONS.md`**](Artifacts/LIMITATIONS.md).

---

## 📄 License

This project is licensed under the terms of the GNU General Public License v3.0 ([LICENSE](LICENSE)).

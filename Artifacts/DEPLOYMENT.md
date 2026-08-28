# Deployment & Operations Guide (DEPLOYMENT.md)
## PassMan — Offline-First, Zero-Knowledge Cross-Platform Password Manager

**Version:** 1.0 (MVP)  
**Target Environments:** Production, Staging, Local Development  
**Backend:** FastAPI (Python 3.11+) · Docker · Fly.io / Render  
**Database:** Supabase Managed PostgreSQL 15  
**Web Frontend:** Flutter Web · Netlify / Vercel / Cloudflare Pages  
**Android Frontend:** Release APK / Android App Bundle (AAB)  

---

## 1. System Architecture Overview

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                           CLIENT DEPLOYMENTS                            │
│  ┌────────────────────────────────────┐  ┌───────────────────────────┐  │
│  │ Android Mobile (APK / AAB)         │  │ Flutter Web (Netlify/CDN) │  │
│  │ • API 21+                          │  │ • Static SPA Bundle       │  │
│  │ • Hardware Keystore + Biometrics   │  │ • HTTPS + Strict CSP      │  │
│  └─────────────────┬──────────────────┘  └─────────────┬─────────────┘  │
└────────────────────┼───────────────────────────────────┼────────────────┘
                     │ HTTPS / TLS 1.3 (Bearer JWT)      │
                     └─────────────────┬─────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────────┐
│                      BACKEND API (Fly.io / Render)                      │
│  Dockerized FastAPI Service · Uvicorn ASGI · Rate Limiter · CORS        │
│  • Endpoint: https://api.passman.example.com                            │
└──────────────────────────────────────┬──────────────────────────────────┘
                                       │ Direct Connection / Connection Pooler
┌──────────────────────────────────────▼──────────────────────────────────┐
│                   DATABASE LAYER (Supabase PostgreSQL)                  │
│  • Managed PostgreSQL 15 on AWS                                         │
│  • Direct / Pooler Connection String (Port 5432 / 6543)                 │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Prerequisites & Tooling Requirements

Before starting deployment, ensure the following CLI tools and accounts are set up:

| Tool / Service | Minimum Version | Purpose |
| :--- | :--- | :--- |
| **Python** | `3.11+` | Backend runtime & scripting |
| **Flutter SDK** | `3.19+` (Dart `3.3+`) | Mobile & Web build compilation |
| **Docker** | `24.0+` | Containerizing FastAPI backend |
| **Android SDK / JDK** | JDK 17, Android SDK 34 | Building signed Android APK/AAB |
| **Supabase Account** | Active project | Managed PostgreSQL instance |
| **Fly.io / Render CLI** | Latest | Cloud container deployment |
| **Netlify / Vercel CLI** | Latest | Static web hosting deployment |

---

## 3. Database Setup (Supabase / PostgreSQL)

### 3.1 Project Provisioning
1. Log in to [Supabase](https://supabase.com) and create a new project (e.g., `passman-prod`).
2. Select your target region (e.g., `us-east-1` or closest to backend deployment).
3. Note the database password and retrieve the **Connection String (URI)** from `Project Settings -> Database -> Connection string`.
   - **Transaction Pooler (Recommended for Serverless/Scale):** `postgresql://postgres.[ref]:[pass]@aws-0-[region].pooler.supabase.com:6543/postgres`
   - **Session / Direct Connection:** `postgresql://postgres:[pass]@db.[ref].supabase.co:5432/postgres`

> **Note on Supabase Auth & RLS:**
> - Disable Supabase built-in GoTrue Auth. PassMan handles user registration, password hashing (Argon2id), and token issuance inside FastAPI.
> - PostgreSQL Row Level Security (RLS) is not required because FastAPI connects via service-level credentials and enforces multi-tenant ownership in application code (`WHERE user_id = current_user.id`).

### 3.2 Executing Database Migration DDL
Execute the following SQL script in the Supabase SQL Editor:

```sql
-- 1. Enable UUID Extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Users Table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    salt TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- 3. Vault Entries Table (Soft-Delete Enabled for Delta Sync)
CREATE TABLE IF NOT EXISTS vault_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    encrypted_data TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ NULL
);
CREATE INDEX IF NOT EXISTS idx_vault_user_sync ON vault_entries(user_id, updated_at DESC);

-- 4. Refresh Tokens Table (Hashed Storage)
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_lookup ON refresh_tokens(token_hash, revoked_at);

-- 5. Audit Logs Table (Asynchronous Logging)
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON audit_logs(user_id, created_at DESC);
```

---

## 4. Backend API Deployment (FastAPI)

### 4.1 Production Dockerfile
Create a production-grade multi-stage `Dockerfile` in the backend root:

```dockerfile
# Multi-stage build for FastAPI
FROM python:3.11-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Final runtime image
FROM python:3.11-slim AS runner

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /root/.local /root/.local
COPY . /app

ENV PATH=/root/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PORT=8000

# Non-root user for security
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8000/api/vault/sync/status || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2", "--proxy-headers"]
```

### 4.2 Production Environment Variables (`.env`)
Configure the following environment secrets in your deployment hosting platform:

```env
# Database connection
DATABASE_URL=postgresql+asyncpg://postgres:[YOUR_PASSWORD]@aws-0-[REGION].pooler.supabase.com:6543/postgres

# JWT Security
JWT_SECRET_KEY=generate_a_64_char_secure_random_hex_string_here
ALGORITHM=HS256

# Android Platform Token & Vault Lock Configuration
ANDROID_ACCESS_TOKEN_EXPIRES=10
ANDROID_REFRESH_TOKEN_EXPIRES=10
ANDROID_VAULT_LOCK=15

# Web Platform Token & Vault Lock Configuration
WEB_ACCESS_TOKEN_EXPIRES=10
WEB_REFRESH_TOKEN_EXPIRES=8
WEB_VAULT_LOCK=15

# CORS Allowed Origins (Comma-separated)
CORS_ORIGINS=https://passman.netlify.app,https://app.passman.example.com

# Server Environment
ENVIRONMENT=production
LOG_LEVEL=info
```

### 4.3 Deploying to Fly.io
1. Initialize Fly configuration:
   ```bash
   fly launch --no-deploy
   ```
2. Set production secrets on Fly:
   ```bash
   fly secrets set \
     DATABASE_URL="postgresql+asyncpg://..." \
     JWT_SECRET_KEY="super_secure_random_key" \
     CORS_ORIGINS="https://passman.netlify.app"
   ```
3. Deploy the application:
   ```bash
   fly deploy
   ```

### 4.4 Deploying to Render
1. Create a new **Web Service** connected to your Git repository.
2. Select **Docker** environment runtime.
3. Configure the environment variables listed in Section 4.2 in the Render Dashboard.
4. Set Health Check Path to `/api/vault/sync/status`.
5. Deploy service and obtain the assigned HTTPS URL (e.g., `https://passman-api.onrender.com`).

---

## 5. Flutter Web Deployment

### 5.1 Compilation & Build
Flutter Web requires injecting the production API URL at build time using `--dart-define`:

```bash
cd frontend

# Clean previous build artifacts
flutter clean
flutter pub get

# Build production web bundle with CanvasKit renderer
flutter build web --release \
  --dart-define=API_URL=https://api.passman.example.com \
  --dart-define=ENV=production \
  --web-renderer canvaskit
```

The compiled static assets will be located in `build/web/`.

### 5.2 Deploying to Netlify
1. Create a `build/web/_redirects` file for single-page application (SPA) routing:
   ```text
   /*    /index.html   200
   ```
2. Create `build/web/_headers` to enforce secure HTTP headers:
   ```text
   /*
     X-Frame-Options: DENY
     X-Content-Type-Options: nosniff
     Referrer-Policy: strict-origin-when-cross-origin
     Content-Security-Policy: default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; font-src 'self' data:; connect-src 'self' https://api.passman.example.com; img-src 'self' data:;
   ```
3. Deploy via Netlify CLI:
   ```bash
   netlify deploy --dir=build/web --prod
   ```

---

## 6. Android Mobile Build & Release

### 6.1 Generate Release Keystore
Generate a cryptographically secure upload keystore (if not already existing):

```bash
keytool -genkey -v -keystore android/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

### 6.2 Configure `android/key.properties`
Create `android/key.properties` (never commit this file to source control):

```properties
storePassword=YourKeystorePassword
keyPassword=YourKeyPassword
keyAlias=upload
storeFile=../upload-keystore.jks
```

### 6.3 Verify `android/app/build.gradle`
Ensure release signing configuration is bound to `key.properties`:

```groovy
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 34
        versionCode 1
        versionName "1.0.0"
    }

    signingConfigs {
        release {
            keyAlias = keystoreProperties['keyAlias']
            keyPassword = keystoreProperties['keyPassword']
            storeFile = keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword = keystoreProperties['storePassword']
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.release
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}
```

### 6.4 Verify `AndroidManifest.xml`
Confirm security permissions in `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
    <uses-permission android:name="android.permission.USE_FINGERPRINT"/>

    <application
        android:label="PassMan"
        android:usesCleartextTraffic="false"
        android:icon="@mipmap/ic_launcher">
        ...
    </application>
</manifest>
```

### 6.5 Build Signed Release APK & App Bundle
```bash
cd frontend

# Build universal release APK
flutter build apk --release \
  --dart-define=API_URL=https://api.passman.example.com \
  --dart-define=ENV=production

# Output: build/app/outputs/flutter-apk/app-release.apk

# Build Google Play App Bundle (AAB)
flutter build appbundle --release \
  --dart-define=API_URL=https://api.passman.example.com \
  --dart-define=ENV=production

# Output: build/app/outputs/bundle/release/app-release.aab
```

---

## 7. Environment Variables Reference Matrix

| Variable Name | Required | Default / Example | Purpose |
| :--- | :--- | :--- | :--- |
| `DATABASE_URL` | **Yes** | `postgresql+asyncpg://user:pass@pooler:5432/postgres` | Async SQLAlchemy PostgreSQL connection string |
| `JWT_SECRET_KEY` | **Yes** | `64-character hex string` | HS256 HMAC secret for signing Access & Refresh tokens |
| `ALGORITHM` | No | `HS256` | JWT signing algorithm |
| `ANDROID_ACCESS_TOKEN_EXPIRES` | No | `10` | Expiration window for Android access tokens (minutes) |
| `ANDROID_REFRESH_TOKEN_EXPIRES` | No | `10` | Expiration window for Android refresh tokens (days) |
| `ANDROID_VAULT_LOCK` | No | `15` | Default auto-lock duration on Android (5-30 minutes, user selectable) |
| `WEB_ACCESS_TOKEN_EXPIRES` | No | `10` | Expiration window for Web access tokens (minutes) |
| `WEB_REFRESH_TOKEN_EXPIRES` | No | `8` | Expiration window for Web refresh tokens (hours) |
| `WEB_VAULT_LOCK` | No | `15` | Default auto-lock duration on Web (5-30 minutes, user selectable) |
| `CORS_ORIGINS` | **Yes** | `https://passman.netlify.app` | Comma-separated list of allowed Web origins |
| `ENVIRONMENT` | No | `production` (`development`, `staging`, `production`) | Application runtime environment |
| `API_URL` (Flutter) | **Yes** | `https://api.passman.example.com` | Base HTTP endpoint for mobile & web clients |

---

## 8. Post-Deployment Verification & Smoke Testing Checklist

After completing the deployments, execute the following smoke tests:

### 8.1 Backend API Verification
```bash
# 1. Verify health/status endpoint
curl -i -X GET https://api.passman.example.com/api/vault/sync/status

# 2. Test User Registration
curl -i -X POST https://api.passman.example.com/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"MasterPassword123!","salt":"dGVzdHNhbHQ="}'

# 3. Test User Login & Token Issuance
curl -i -X POST https://api.passman.example.com/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"MasterPassword123!"}'

# 4. Verify Rate Limiting (execute login 6 times rapidly -> expect 429 on 6th)
```

### 8.2 End-to-End Client Verification
- [ ] **Web Browser Check:** Open the deployed Netlify URL. Confirm no CORS errors appear in DevTools Console.
- [ ] **Zero-Knowledge Check:** Inspect Network DevTools during entry creation. Confirm the `POST /api/vault/entries` request body contains only `{ ciphertext, iv, tag }` with no plaintext passwords.
- [ ] **Offline Flow Check (Android):**
  1. Open Android APK in Flight Mode.
  2. Confirm cached vault renders in $<200\text{ ms}$.
  3. Add a new credential.
  4. Disable Flight Mode.
  5. Pull down to refresh; confirm item status updates to synced (`is_pending_sync = 0`).
- [ ] **Cross-Device Tombstone Check:**
  1. Delete an entry on Web.
  2. Open Android app and trigger sync.
  3. Confirm the deleted entry disappears from the local Android list immediately.

---

## 9. Operations & Maintenance Runbooks

### 9.1 Database Backup & Recovery
- Supabase automatically performs daily backups.
- To take an on-demand manual SQL dump:
  ```bash
  pg_dump "postgresql://postgres:[PASSWORD]@db.[REF].supabase.co:5432/postgres" \
    --clean --if-exists -f passman_backup_$(date +%Y%m%d_%H%M%S).sql
  ```

### 9.2 JWT Secret Key Emergency Rotation
If the `JWT_SECRET_KEY` is compromised:
1. Generate a new 64-character random key:
   ```bash
   openssl rand -hex 32
   ```
2. Update the `JWT_SECRET_KEY` secret on Fly.io / Render.
3. Restart the API instances.
4. *Effect:* All existing access and refresh tokens will be invalidated immediately. All users will be prompted to log in again with their master password.

### 9.3 Revoked Token & Tombstone Cleanup Job
To prevent unbounded table growth in PostgreSQL over time, schedule a weekly maintenance query:

```sql
-- Purge revoked or expired refresh tokens older than 30 days
DELETE FROM refresh_tokens 
WHERE (revoked_at IS NOT NULL AND revoked_at < NOW() - INTERVAL '30 days')
   OR (expires_at < NOW() - INTERVAL '30 days');

-- Purge tombstones older than 90 days (Ensure all active devices have synced)
DELETE FROM vault_entries 
WHERE deleted_at IS NOT NULL 
  AND deleted_at < NOW() - INTERVAL '90 days';
```

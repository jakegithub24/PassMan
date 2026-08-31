# PassMan Staging Deployment & Multi-Device Testing Guide

This guide details the complete end-to-end setup for staging and testing PassMan across multiple devices using:
* **Backend**: FastAPI running locally on your laptop (`http://localhost:8000`).
* **Tunnel**: [ngrok](https://ngrok.com/) forwarding port `8000` to a secure public HTTPS URL.
* **Mobile**: Release APK installed on a physical Android phone connecting via ngrok.
* **Web**: Flutter Web client running locally on the same laptop.
* **Database**: Local PostgreSQL or remote [Supabase](https://supabase.com) instance.

---

## 1. Architecture Topology

```
                   ┌──────────────────────────────────────────────┐
                   │               PHYSICAL LAPTOP                │
                   │                                              │
                   │  ┌─────────────────┐   ┌──────────────────┐  │
                   │  │  PostgreSQL DB  │   │  Flutter Web UI  │  │
                   │  │  (Port 5432)    │   │  (Port 3000)     │  │
                   │  └────────┬────────┘   └────────┬─────────┘  │
                   │           │                     │            │
                   │           ▼                     ▼            │
                   │  ┌────────────────────────────────────────┐  │
                   │  │      FastAPI Backend (Port 8000)       │  │
                   │  └───────────────────┬────────────────────┘  │
                   │                      │                       │
                   │                      ▼                       │
                   │  ┌────────────────────────────────────────┐  │
                   │  │              ngrok tunnel              │  │
                   │  └───────────────────┬────────────────────┘  │
                   └──────────────────────┼───────────────────────┘
                                          │
                         HTTPS Public URL │ (Internet)
                                          ▼
                   ┌──────────────────────────────────────────────┐
                   │            PHYSICAL ANDROID PHONE            │
                   │                                              │
                   │  ┌────────────────────────────────────────┐  │
                   │  │          PassMan Release APK           │  │
                   │  │   (Encrypted SQLite + Biometrics)      │  │
                   │  └────────────────────────────────────────┘  │
                   └──────────────────────────────────────────────┘
```

---

## 2. Prerequisites

1. **Python 3.12+** & **uv** package manager.
2. **Flutter SDK 3.x** configured in PATH.
3. **ngrok CLI** installed and authenticated ([download ngrok](https://ngrok.com/download)).
4. **Android Phone**:
   - Developer Options enabled.
   - USB Debugging enabled (if installing via ADB) or USB file transfer.
5. **Google Chrome** (for running Flutter Web).

---

## 3. Step-by-Step Setup

### Step 1: Configure & Start PostgreSQL Database

Ensure PostgreSQL is running locally or obtain your remote Supabase connection string.

Apply the database schema and indexes:
```bash
cd backend
uv run python apply_schema.py
```

---

### Step 2: Start the FastAPI Backend

1. Create or edit `backend/.env`:
   ```env
   DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/passman
   JWT_SECRET_KEY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
   ENVIRONMENT=staging
   LOG_LEVEL=info
   PORT=8000
   ANDROID_ACCESS_TOKEN_EXPIRES=10
   ANDROID_REFRESH_TOKEN_EXPIRES=10
   ANDROID_VAULT_LOCK=15
   WEB_ACCESS_TOKEN_EXPIRES=10
   WEB_REFRESH_TOKEN_EXPIRES=8
   WEB_VAULT_LOCK=15
   CORS_ORIGINS=http://localhost:3000,http://127.0.0.1:3000,http://localhost:8080,https://*.ngrok-free.app,https://*.ngrok.app
   ```

2. Start the FastAPI server:
   ```bash
   cd backend
   uv run uvicorn main:app --host 0.0.0.0 --port 8000 --reload
   ```

3. Verify health endpoint in your browser:
   [http://localhost:8000/](http://localhost:8000/) → should return `{"status": "healthy"}`.

---

### Step 3: Launch the ngrok Tunnel

In a new terminal window on your laptop, start an HTTP tunnel pointing to port `8000`:
```bash
ngrok http 8000
```

ngrok will output your forwarding HTTPS URL. For example:
```
Forwarding   https://a1b2-c3d4-e5f6.ngrok-free.app -> http://localhost:8000
```

> **Note**: Save this URL (e.g. `https://a1b2-c3d4-e5f6.ngrok-free.app`). You will compile the Android APK with it.

---

### Step 4: Build & Install Android APK on Physical Phone

1. Build the release APK with the ngrok URL injected via `--dart-define`:
   ```bash
   cd apps
   flutter build apk --release --dart-define=API_BASE_URL=https://a1b2-c3d4-e5f6.ngrok-free.app
   ```

2. Install the APK on your Android device:
   * **Via ADB (USB Connected)**:
     ```bash
     adb install -r build/app/outputs/flutter-apk/app-release.apk
     ```
   * **Via Direct Transfer**:
     Copy `apps/build/app/outputs/flutter-apk/app-release.apk` to your phone via Google Drive, Telegram, or USB cable, and tap to install.

---

### Step 5: Start the Flutter Web Client

In another terminal on your laptop, run Flutter Web pointing to the local backend:
```bash
cd apps
flutter run -d chrome --web-port 3000 --dart-define=API_BASE_URL=http://localhost:8000
```

The Web client will open at `http://localhost:3000`.

---

## 4. End-to-End Multi-Device Verification Matrix

| Step | Action | Platform | Expected Outcome |
| :--- | :--- | :--- | :--- |
| **1** | Register account `test@example.com` with master password | **Android Phone** | Account created; client key derived via PBKDF2/Argon2id; vault initialized. |
| **2** | Add a new login entry (e.g. "GitHub - myuser / P@ss123") | **Android Phone** | Item encrypted with AES-256-GCM locally; synced to backend via ngrok. |
| **3** | Log in as `test@example.com` with the same master password | **Laptop Web** | Session authenticated; local encryption key derived; vault synced from backend. |
| **4** | Verify vault contents | **Laptop Web** | "GitHub" entry appears decrypted and readable on Web. |
| **5** | Add a card entry (e.g. "Visa Card") | **Laptop Web** | Encrypted and uploaded to backend. |
| **6** | Pull to refresh / trigger auto-sync | **Android Phone** | "Visa Card" immediately appears on Android. |
| **7** | **Offline Test**: Enable Airplane Mode on phone | **Android Phone** | App remains fully operational; SQLite cache accessible. |
| **8** | Create "Offline Note" in Airplane Mode | **Android Phone** | Entry marked pending sync (`is_pending_sync = 1`). |
| **9** | Disable Airplane Mode | **Android Phone** | App detects network reconnect and flushes pending entry to backend. |
| **10** | Refresh Web vault | **Laptop Web** | "Offline Note" synced from backend and decrypted. |

---

## 5. Troubleshooting & Tips

### 1. ngrok Free Tier "ngrok-skip-browser-warning"
If you test endpoints via browser through ngrok, ngrok free tier displays an interstitial warning page. Native Dio requests from the Android app pass standard JSON headers (`Accept: application/json`) which bypass this interstitial automatically.

### 2. Physical Device Network Errors
* Ensure your laptop does not enter sleep mode.
* Verify ngrok is running in your terminal and shows requests arriving (`POST /api/auth/login 200 OK`).
* Ensure `CORS_ORIGINS` in `backend/.env` contains your ngrok domain and `http://localhost:3000`.

### 3. Rebuilding APK for a New ngrok URL
If you restart ngrok and receive a new forwarding URL, rebuild the APK with the updated URL:
```bash
flutter build apk --release --dart-define=API_BASE_URL=https://NEW-SUBDOMAIN.ngrok-free.app
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

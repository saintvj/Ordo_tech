# Ordo Menu Scanner Proxy (Development Only)

A lightweight Node.js development proxy that interfaces with Google's Gemini API via the official `@google/genai` SDK. It securely holds the Gemini API key locally on your development machine, receives menu photos from the Ordo Flutter app, and returns structured menu JSON.

## Security Guarantees
- **Never committed**: The `.env` file containing your `GEMINI_API_KEY` is ignored by git.
- **Local loopback only**: The server binds strictly to `127.0.0.1` and is never exposed to public or external network interfaces.
- **No secrets in client**: Flutter code never sees or contains the Gemini API key.
- **Redacted errors**: Error messages returned to the client sanitize and redact API keys if ever present.

## Prerequisites
- Node.js v22 or higher (v24 recommended)
- A Gemini API key from [Google AI Studio](https://aistudio.google.com/app/apikey)

## Quick Start (PowerShell)

### 1. Install dependencies
```powershell
cd tools/menu-scanner-proxy
npm install
```

### 2. Configure environment
Copy `.env.example` to `.env`:
```powershell
Copy-Item .env.example .env
```
Open `.env` and set your key:
```env
GEMINI_API_KEY=your_actual_gemini_api_key
GEMINI_MODEL=gemini-3.8-flash
PORT=8787
```

### 3. Run automated tests
```powershell
npm test
```

### 4. Start the server
```powershell
npm start
```
The server will start listening at:
`http://127.0.0.1:8787`

### 5. Verify health check
In another PowerShell window:
```powershell
Invoke-RestMethod -Uri http://127.0.0.1:8787/health -Method GET
```
Expected output:
```json
{"status":"ok","model":"gemini-3.8-flash"}
```

## Android Physical Device Setup
When testing on a physical Android device connected via USB with USB debugging enabled, run:
```powershell
adb reverse tcp:8787 tcp:8787
```
This forwards loopback port 8787 from the Android device to your computer's 127.0.0.1:8787.

## Endpoints
- `GET /health`: Health and model verification.
- `POST /api/menu/scan`: Multipart form upload with field `image` (JPEG, PNG, or WebP up to 10MB). Returns `{ success: true, data: { categories, warnings, unreadable_text } }`.


# CAT Inspector — Flutter App

Pre-operation inspection assistant for the Caterpillar 950–982 wheel loader.

## Build & Run

```bash
cd app_ui
flutter pub get
flutter run        # connected iPhone
flutter analyze    # lint check
```

## Backend API Payloads

The app talks to two servers:

| Server | Default | Purpose |
|--------|---------|---------|
| Main API | `<baseUrl>` (configured in-app, default `http://localhost:8000`) | Agent chat + reports |
| Data Stream | Same host, port `8001` | Camera frame uploads for vision tool |

All JSON requests use headers `Content-Type: application/json`, `Accept: application/json`.
Timeout is 60 seconds for JSON endpoints, 10 seconds for frame uploads.

---

### 1. Start Session — `POST /chat`

Sent when the operator taps **Start Inspection**.

**Request:**
```json
{
  "user_id": "operator",
  "session_id": "sess_1740700000000",
  "text": "Starting pre-operation inspection for machine WL-0472. Guide me through the walk-around."
}
```

- `session_id` is generated client-side: `sess_<millisecondsSinceEpoch>`
- `text` inserts the machine ID entered by the operator

**Expected response:**
```json
{
  "session_id": "sess_1740700000000",
  "message": "Begin at the front of the machine — inspect the bucket cutting edge."
}
```

- `session_id` — echoed back (app falls back to the one it generated)
- `message` — initial guidance text (spoken via TTS and shown in the agent card)

---

### 2. Inspect Turn — `POST /chat`

Sent for every operator interaction during inspection (text message, audio recording, photo, or video).

**Request:**
```json
{
  "user_id": "operator",
  "session_id": "sess_1740700000000",
  "text": "<see below>"
}
```

The `text` field is built from whichever input the operator provided (first match wins):

| Input | `text` value |
|-------|-------------|
| Typed text | The operator's message verbatim |
| Photo (frame upload succeeded) | `"I just took a photo at zone front_slight_sides. Please use your vision tool to analyze the current frame."` |
| Photo (frame upload failed) | `"Photo taken at zone front_slight_sides."` |
| Video | `"Video recorded at zone front_slight_sides."` |
| Audio | `"Audio note recorded at zone front_slight_sides."` |
| No input (fallback) | `"Continuing inspection at zone front_slight_sides. What should I check next?"` |

If the operator typed text **and** attached a photo, the typed text is sent as-is (photo is still uploaded via the frame endpoint separately).

**Expected response:**
```json
{
  "message": "Check the tilt cylinders — look for hydraulic leaks around seals."
}
```

- `message` — agent guidance text (spoken via TTS)

---

### 3. Upload Frame — `POST /upload-frame` (port 8001)

Sent whenever the operator takes a photo or the app uploads a media photo. The frame is uploaded to the data stream server so the backend vision tool can read it.

**URL:** `http://<host>:8001/upload-frame`

**Request:** `multipart/form-data`

| Field | Type | Description |
|-------|------|-------------|
| `file` | file | JPEG image from device camera |

**Expected response:** Any `2xx` status code = success. Body is ignored.

This is a best-effort upload — if the data stream server is not running, the app logs a warning and continues.

---

### 4. Query Reports — `POST /review`

Sent when a manager types a question in the **Reports** tab.

**Request:**
```json
{
  "user_id": "manager",
  "session_id": "review_WL-0472",
  "text": "Show me recent hydraulic issues"
}
```

- `session_id` is `review_<machineId>` (stable per machine for conversation continuity)
- `text` is the manager's query verbatim

**Expected response:**
```json
{
  "analysis": "Found 2 reports with hydraulic-related issues for WL-0472..."
}
```

- `analysis` — assistant's natural-language answer (shown in chat)

---

### 5. Edit Report — `POST /review`

Sent when a manager issues an edit instruction for a specific report.

**Request:**
```json
{
  "user_id": "manager",
  "session_id": "review_edit",
  "text": "Update report RPT-2024-0472-A: Mark hydraulic hose issue as resolved"
}
```

- `session_id` is always `"review_edit"`
- `text` is `"Update report <reportId>: <instruction>"`

**Expected response:**
```json
{
  "status": "success",
  "analysis": "Report RPT-2024-0472-A updated: hydraulic hose issue marked as resolved."
}
```

- `status` — `"success"` if the update was applied
- `analysis` — confirmation text shown in chat

---

### Summary Table

| # | Method | Endpoint | Port | When |
|---|--------|----------|------|------|
| 1 | POST | `/chat` | main | Operator starts inspection |
| 2 | POST | `/chat` | main | Each operator turn (text / audio / photo / video) |
| 3 | POST | `/upload-frame` | 8001 | Photo captured (best-effort, before `/chat`) |
| 4 | POST | `/review` | main | Manager queries past reports |
| 5 | POST | `/review` | main | Manager edits a report |

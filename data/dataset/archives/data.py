"""
data.py – Hands-free labelled dataset builder.

Runs webcam + mic continuously. Every time you speak, it automatically:
  1. Captures frames from the webcam during your speech
  2. Transcribes what you said
  3. Extracts part name, status (GREEN/YELLOW/RED), and comment
  4. Saves frames + label as one dataset sample

Say something like "I'm done" or "stop the session" to end.
Press Ctrl+C as a fallback.

Usage:
    python data.py
    python data.py --camera 1
"""

import os
import sys
import json
import time
import threading
from typing import Optional, List, Dict
from datetime import datetime

import cv2
import speech_recognition as sr
from dotenv import load_dotenv
from google import genai
from google.genai import types

load_dotenv()

client = genai.Client(api_key=os.environ.get("GEMINI_API_KEY"))

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FORM_TEMPLATE_PATH = os.path.join(BASE_DIR, "form.json")
DATASET_DIR = os.path.join(BASE_DIR, "dataset")
FRAMES_PER_SAMPLE = 3




# ── Form helpers ────────────────────────────────────────────────────────────

def load_part_names() -> List[str]:
    with open(FORM_TEMPLATE_PATH, "r") as f:
        form = json.load(f)
    parts = []
    for section_name, items in form["sections"].items():
        for part_key in items:
            parts.append(part_key)
    return parts


def load_sections() -> Dict[str, List[str]]:
    with open(FORM_TEMPLATE_PATH, "r") as f:
        form = json.load(f)
    result = {}
    for section_name, items in form["sections"].items():
        result[section_name] = list(items.keys())
    return result


def find_section(part_key: str, sections: Dict[str, List[str]]) -> str:
    for section, parts in sections.items():
        if part_key in parts:
            return section
    return "UNKNOWN"


# ── Audio helpers ───────────────────────────────────────────────────────────

def transcribe_wav(wav_bytes: bytes) -> str:
    resp = client.models.generate_content(
        model="gemini-2.0-flash",
        contents=[
            "Generate an accurate transcript of the speech in English. "
            "The speaker is speaking in English. "
            "Include proper punctuation and capitalisation. "
            "Output ONLY the transcript text, nothing else.",
            types.Part.from_bytes(data=wav_bytes, mime_type="audio/wav"),
        ],
    )
    return resp.text.strip()


def is_stop_intent(transcript: str) -> bool:
    """Ask Gemini whether the speaker intends to stop / end the session."""
    prompt = f"""A user is speaking to an equipment inspection recording program.
Determine if the user is asking the program to STOP or END the recording session.

Examples that ARE stop commands:
- "Okay, I'm done."
- "Stop recording."
- "That's all, end the session."
- "We're finished here."

Examples that are NOT stop commands:
- "I've never done this before."
- "The engine doesn't stop running."
- "We're done inspecting the tires, moving on to the engine."
- "This part is finished, it's worn out."

TRANSCRIPT: \"\"\"{transcript}\"\"\"

Is the speaker asking the program to stop? Reply with ONLY "yes" or "no"."""

    resp = client.models.generate_content(
        model="gemini-2.0-flash",
        contents=[prompt],
    )
    return resp.text.strip().lower().startswith("yes")


def extract_label(transcript: str, known_parts: List[str]) -> dict:
    parts_list = "\n".join(f"  - {p}" for p in known_parts)
    prompt = f"""You are parsing a spoken equipment inspection observation.

Given the transcript below, extract:
1. "part" – which inspection item the speaker is describing.
   It MUST be one of these known part keys:
{parts_list}
   Pick the closest match. If unclear, use "unknown".
2. "status" – GREEN, YELLOW, or RED.
   GREEN = good / OK / fine / no issues.
   YELLOW = minor issue / monitor / caution / wear.
   RED = critical / broken / dangerous / needs immediate repair.
3. "comment" – a short summary of what the speaker said about this part.

TRANSCRIPT:
\"\"\"{transcript}\"\"\"

Return ONLY a JSON object with keys: "part", "status", "comment".
No markdown fences, no extra text."""

    resp = client.models.generate_content(
        model="gemini-2.0-flash",
        contents=[prompt],
    )
    raw = resp.text.strip()
    if raw.startswith("```"):
        raw = raw.split("\n", 1)[1]
        raw = raw.rsplit("```", 1)[0]
        raw = raw.strip()
    return json.loads(raw)


# ── Frame helpers ───────────────────────────────────────────────────────────

def pick_indices(total, n):
    if total == 0:
        return []
    if n >= total:
        return list(range(total))
    step = (total - 1) / (n - 1) if n > 1 else 0
    return [int(round(i * step)) for i in range(n)]


# ── Dataset I/O ─────────────────────────────────────────────────────────────

def save_sample(sample_id, frames, label, transcript):
    sample_name = f"sample_{sample_id:04d}"
    sample_dir = os.path.join(DATASET_DIR, sample_name)
    os.makedirs(sample_dir, exist_ok=True)

    indices = pick_indices(len(frames), FRAMES_PER_SAMPLE)
    saved_frames = []
    for seq, idx in enumerate(indices):
        fname = f"frame_{seq + 1}.jpg"
        path = os.path.join(sample_dir, fname)
        cv2.imwrite(path, frames[idx])
        saved_frames.append(fname)

    label_data = {
        "part": label.get("part", "unknown"),
        "section": label.get("section", "UNKNOWN"),
        "status": label.get("status", "GREEN"),
        "comment": label.get("comment", ""),
        "transcript": transcript,
        "frames": saved_frames,
        "timestamp": datetime.now().isoformat(),
    }
    with open(os.path.join(sample_dir, "label.json"), "w") as f:
        json.dump(label_data, f, indent=2)

    return sample_dir, label_data


def load_manifest() -> list:
    path = os.path.join(DATASET_DIR, "manifest.json")
    if os.path.exists(path):
        with open(path, "r") as f:
            return json.load(f)
    return []


def save_manifest(manifest: list):
    path = os.path.join(DATASET_DIR, "manifest.json")
    with open(path, "w") as f:
        json.dump(manifest, f, indent=2)


# ── Shared frame ring buffer (webcam keeps writing, samples read from it) ──

class FrameBuffer:
    """Thread-safe ring buffer that holds the last N seconds of frames."""

    def __init__(self, max_seconds=6, est_fps=30):
        self.max_frames = max_seconds * est_fps
        self.frames = []
        self.lock = threading.Lock()

    def push(self, frame):
        with self.lock:
            self.frames.append(frame)
            if len(self.frames) > self.max_frames:
                self.frames.pop(0)

    def snapshot(self) -> list:
        """Return a copy of the current buffer."""
        with self.lock:
            return list(self.frames)


# ── Main ────────────────────────────────────────────────────────────────────

def main(camera_index=0):
    os.makedirs(DATASET_DIR, exist_ok=True)

    known_parts = load_part_names()
    sections = load_sections()
    manifest = load_manifest()
    sample_id = len(manifest)

    # Start webcam
    cap = cv2.VideoCapture(camera_index)
    if not cap.isOpened():
        print(f"❌ Cannot open camera {camera_index}")
        sys.exit(1)

    frame_buf = FrameBuffer()
    stop_event = threading.Event()

    # ── Webcam thread: continuously push frames into the ring buffer ────
    def camera_loop():
        while not stop_event.is_set():
            ret, frame = cap.read()
            if ret:
                frame_buf.push(frame)
                cv2.imshow("data.py – Inspection Camera", frame)
                cv2.waitKey(1)
            else:
                time.sleep(0.01)

    cam_thread = threading.Thread(target=camera_loop, daemon=True)
    cam_thread.start()

    # ── Mic setup ───────────────────────────────────────────────────────
    rec = sr.Recognizer()
    mic = sr.Microphone()
    with mic as source:
        rec.adjust_for_ambient_noise(source, duration=1)

    print("=" * 60)
    print("  📸🎤  INSPECTION DATA COLLECTOR (voice-controlled)")
    print("=" * 60)
    print(f"  Camera: {camera_index}  |  Dataset: {DATASET_DIR}")
    print(f"  Existing samples: {len(manifest)}")
    print()
    print("  Just speak! Describe each part and its condition.")
    print("  I'll automatically capture frames + label each one.")
    print()
    print("  Say something like 'I'm done' to end the session.")
    print("  (Ctrl+C also works)")
    print("=" * 60)
    print("\n🎤 Listening…\n")

    # ── Voice-driven loop ───────────────────────────────────────────────
    def on_audio(_, audio):
        nonlocal sample_id

        try:
            wav = audio.get_wav_data()

            # Grab frames from the buffer at the moment of speech
            frames = frame_buf.snapshot()

            # Transcribe
            transcript = transcribe_wav(wav)
            if not transcript.strip():
                return

            print(f"\n  📝 Heard: \"{transcript}\"")

            # Check for stop intent via AI
            if is_stop_intent(transcript):
                print("\n  🛑 Stop command detected.")
                stop_event.set()
                return

            # Extract label
            print("  🤖 Extracting label…")
            label = extract_label(transcript, known_parts)
            section = find_section(label.get("part", ""), sections)
            label["section"] = section

            # Skip if part/section couldn't be identified
            if label.get("part", "unknown") == "unknown" or section == "UNKNOWN":
                print("  ⏭  Skipped — no recognisable part detected.")
                print("\n  🎤 Listening for next part…")
                return

            # Save sample
            sample_id += 1
            sample_dir, label_data = save_sample(
                sample_id, frames, label, transcript
            )
            label_data["sample_dir"] = sample_dir
            manifest.append(label_data)
            save_manifest(manifest)

            status_emoji = {"GREEN": "🟢", "YELLOW": "🟡", "RED": "🔴"}.get(
                label["status"], "⚪"
            )
            print(f"  {status_emoji} Sample {sample_id:04d}  |  "
                  f"{label['part']}  →  {label['status']}")
            print(f"     Comment: {label['comment']}")
            print(f"     Saved: {sample_dir}  ({len(frames)} buf frames → "
                  f"{FRAMES_PER_SAMPLE} selected)")
            print("\n  🎤 Listening for next part…")

        except json.JSONDecodeError as e:
            print(f"  ⚠  Could not parse label: {e}")
        except Exception as e:
            print(f"  ⚠  Error: {e}")

    stop_listening = rec.listen_in_background(mic, on_audio,
                                               phrase_time_limit=10)

    try:
        while not stop_event.is_set():
            time.sleep(0.2)
    except KeyboardInterrupt:
        print("\n\n⏹  Interrupted by Ctrl+C.")

    # Cleanup
    stop_listening(wait_for_stop=False)
    stop_event.set()
    time.sleep(0.3)
    cap.release()
    cv2.destroyAllWindows()
    save_manifest(manifest)

    print(f"\n📊 Session complete: {len(manifest)} total samples in {DATASET_DIR}")


# ── CLI ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(
        description="Voice-controlled labelled inspection dataset builder")
    parser.add_argument("--camera", type=int, default=0,
                        help="Camera index (default: 0)")
    args = parser.parse_args()
    main(camera_index=args.camera)

"""
main.py – Voice + camera interface for the ADK inspection agent.

Mic is ALWAYS on. When you speak, TTS stops immediately.
  1. Background mic listens continuously
  2. Speech detected → TTS interrupted → transcribe → send to agent
  3. Agent reply → TTS (interruptible if you speak again)
  4. Webcam captures frames for dataset labelling in background

Usage:
    python main.py
    python main.py --camera 1
"""

import os
import sys
import json
import re
import time
import asyncio
import datetime
import threading
import wave
from typing import Optional, List
from datetime import datetime as dt

import io
import cv2
import speech_recognition as sr
try:
    os.environ['PYGAME_HIDE_SUPPORT_PROMPT'] = "hide"
    import pygame
    HAVE_PYGAME = True
except ImportError:
    HAVE_PYGAME = False

from dotenv import load_dotenv
from google import genai
from google.genai import types

load_dotenv()
_adk_env = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "hackIllinois2026", ".env")
if os.path.exists(_adk_env):
    load_dotenv(_adk_env, override=False)

_api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
client = genai.Client(api_key=_api_key)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ADK_APP_DIR = os.path.join(BASE_DIR, "hackIllinois2026")
DATASET_DIR = os.path.join(BASE_DIR, "dataset")
FRAMES_PER_SAMPLE = 3

if ADK_APP_DIR not in sys.path:
    sys.path.insert(0, ADK_APP_DIR)


# ═══════════════════════════════════════════════════════════════════════════
#  PART KEYS (for dataset labelling)
# ═══════════════════════════════════════════════════════════════════════════

GROUND_KEYS = [
    "tires_wheels_stem_caps_lug_nuts", "bucket_cutting_edge_moldboard",
    "bucket_cylinders_lines_hoses", "loader_frame_arms", "underneath_machine",
    "transmission_transfer_case", "steps_handholds", "fuel_tank",
    "differential_final_drive_oil", "air_tank", "axles_brakes_seals",
    "hydraulic_tank", "transmission_oil", "lights_front_rear",
    "battery_compartment", "def_tank", "overall_machine"
]
ENGINE_KEYS = [
    "engine_oil", "engine_coolant", "radiator", "all_hoses_and_lines",
    "fuel_filters_water_separator", "all_belts", "air_filter",
    "overall_engine_compartment"
]
CAB_EXTERIOR_KEYS = [
    "handholds", "rops", "fire_extinguisher", "windshield_windows",
    "wipers_washers", "doors"
]
CAB_INTERIOR_KEYS = [
    "seat", "seat_belt_mounting", "horn_alarm_lights", "mirrors",
    "cab_air_filter", "gauges_indicators_switches", "overall_cab_interior"
]

ALL_PART_KEYS = GROUND_KEYS + ENGINE_KEYS + CAB_EXTERIOR_KEYS + CAB_INTERIOR_KEYS

SECTION_MAP = {}
for k in GROUND_KEYS:
    SECTION_MAP[k] = "GROUND"
for k in ENGINE_KEYS:
    SECTION_MAP[k] = "ENGINE"
for k in CAB_EXTERIOR_KEYS:
    SECTION_MAP[k] = "CAB_EXTERIOR"
for k in CAB_INTERIOR_KEYS:
    SECTION_MAP[k] = "CAB_INTERIOR"


# ═══════════════════════════════════════════════════════════════════════════
#  OUTPUT
# ═══════════════════════════════════════════════════════════════════════════

def _strip_markdown(text: str) -> str:
    text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
    text = re.sub(r'\*(.+?)\*', r'\1', text)
    text = re.sub(r'`(.+?)`', r'\1', text)
    text = re.sub(r'#+\s*', '', text)
    text = re.sub(r'[-•]\s+', '', text)
    return text.strip()


import queue

_tts_queue = queue.Queue()
_tts_cancel_event = threading.Event()

def _tts_worker():
    while True:
        text, timestamp = _tts_queue.get()
        if text is None:
            break
            
        if _tts_cancel_event.is_set():
            continue
            
        try:
            print("  🤖 [TTS: Generating audio...]")
            resp = client.models.generate_content(
                model="gemini-2.5-flash-preview-tts",
                contents=f"Please read this text aloud in English: {text}",
                config=types.GenerateContentConfig(
                    response_modalities=["AUDIO"]
                )
            )
            
            if _tts_cancel_event.is_set():
                continue
                
            for part in resp.candidates[0].content.parts:
                if part.inline_data:
                    # Construct WAV in memory from raw 24kHz 16-bit PCM
                    pcm_data = part.inline_data.data
                    wav_io = io.BytesIO()
                    with wave.open(wav_io, 'wb') as wav_file:
                        wav_file.setnchannels(1)
                        wav_file.setsampwidth(2) # 16-bit
                        wav_file.setframerate(24000)
                        wav_file.writeframes(pcm_data)
                    wav_io.seek(0)
                    
                    if _tts_cancel_event.is_set():
                        continue
                        
                    if not pygame.mixer.get_init():
                        pygame.mixer.init()
                    pygame.mixer.music.load(wav_io)
                    pygame.mixer.music.play()
                    
                    # Wait for audio to finish playing or be interrupted
                    while pygame.mixer.music.get_busy() and not _tts_cancel_event.is_set():
                        pygame.time.Clock().tick(10)
                        
                    if _tts_cancel_event.is_set() and pygame.mixer.music.get_busy():
                        pygame.mixer.music.stop()
                    break # Usually only one audio part
        except Exception as e:
            print(f"  ⚠  TTS error: {e}")

if HAVE_PYGAME:
    threading.Thread(target=_tts_worker, daemon=True).start()

def speak(text: str):
    """Output agent response using Gemini TTS and Pygame."""
    clean = _strip_markdown(text)
    print(f"🗣  {clean}")
    
    if not HAVE_PYGAME:
        return
        
    _tts_cancel_event.clear()
    _tts_queue.put((clean, time.time()))


def interrupt_tts():
    """Stop pygame TTS and clear pending speech queue."""
    _tts_cancel_event.set()
    
    # Flush pending queue
    while not _tts_queue.empty():
        try:
            _tts_queue.get_nowait()
        except queue.Empty:
            break
            
    if HAVE_PYGAME and pygame.mixer.get_init():
        if pygame.mixer.music.get_busy():
            print("  🛑 [TTS Interrupted]")
            pygame.mixer.music.stop()


# ═══════════════════════════════════════════════════════════════════════════
#  TRANSCRIPTION  (Gemini API)
# ═══════════════════════════════════════════════════════════════════════════

def transcribe_audio(audio) -> str:
    """Transcribe audio using Gemini API."""
    try:
        wav_bytes = audio.get_wav_data()
        prompt = "Please accurately transcribe this audio. Reply ONLY with the exact transcript, absolutely nothing else. If it is silence, unintelligible or just background noise, reply with an empty string."
        
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=[prompt, types.Part.from_bytes(data=wav_bytes, mime_type='audio/wav')]
        )
        return (response.text or "").strip()
    except Exception as e:
        print(f"  ⚠  Gemini STT error: {e}")
        return ""


# ═══════════════════════════════════════════════════════════════════════════
#  GEMINI — DATASET LABELLING
# ═══════════════════════════════════════════════════════════════════════════

def extract_label(transcript: str) -> dict:
    parts_list = "\n".join(f"  - {p}" for p in ALL_PART_KEYS)
    prompt = f"""You are parsing a spoken equipment inspection observation for a CAT 950 Wheel Loader.

Given the transcript below, extract:
1. "part" – which inspection item the speaker is describing.
   It MUST be one of these known part keys:
{parts_list}
   Pick the closest match. If unclear, use "unknown".
2. "status" – GREEN, YELLOW, or RED.
   - Pass/Good/OK → GREEN
   - Monitor/Seeping/Worn → YELLOW
   - Fail/Broken/Leaking → RED
3. "comment" – a short summary of what the speaker said about this part.

TRANSCRIPT:
\"\"\"{transcript}\"\"\"

Return ONLY a JSON object with keys: "part", "status", "comment".
No markdown fences, no extra text."""

    resp = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=[prompt],
    )
    raw = (resp.text or "").strip()
    if raw.startswith("```"):
        raw = raw.split("\n", 1)[1]
        raw = raw.rsplit("```", 1)[0]
        raw = raw.strip()
    return json.loads(raw)


# ═══════════════════════════════════════════════════════════════════════════
#  DATASET I/O
# ═══════════════════════════════════════════════════════════════════════════

def pick_indices(total, n):
    if total == 0:
        return []
    if n >= total:
        return list(range(total))
    step = (total - 1) / (n - 1) if n > 1 else 0
    return [int(round(i * step)) for i in range(n)]


def save_sample(sample_id, frames, label, transcript):
    sample_name = f"sample_{sample_id:04d}"
    sample_dir = os.path.join(DATASET_DIR, sample_name)
    os.makedirs(sample_dir, exist_ok=True)

    indices = pick_indices(len(frames), FRAMES_PER_SAMPLE)
    saved_frames = []
    for seq, idx in enumerate(indices):
        fname = f"frame_{seq + 1}.jpg"
        cv2.imwrite(os.path.join(sample_dir, fname), frames[idx])
        saved_frames.append(fname)

    label_data = {
        "part": label.get("part", "unknown"),
        "section": label.get("section", "UNKNOWN"),
        "status": label.get("status", "GREEN"),
        "comment": label.get("comment", ""),
        "transcript": transcript,
        "frames": saved_frames,
        "timestamp": dt.now().isoformat(),
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
    with open(os.path.join(DATASET_DIR, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)


# ═══════════════════════════════════════════════════════════════════════════
#  FRAME RING BUFFER
# ═══════════════════════════════════════════════════════════════════════════

class FrameBuffer:
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
        with self.lock:
            return list(self.frames)


# ═══════════════════════════════════════════════════════════════════════════
#  ADK AGENT — persistent session
# ═══════════════════════════════════════════════════════════════════════════

class AgentSession:
    def __init__(self):
        from app.agents.agent import root_agent
        from google.adk.runners import Runner
        from google.adk.sessions import InMemorySessionService

        self._session_service = InMemorySessionService()
        self._runner = Runner(
            agent=root_agent,
            app_name="inspection",
            session_service=self._session_service,
        )
        self._session_id = None
        self._loop = asyncio.new_event_loop()

    def start(self):
        self._session_id = self._loop.run_until_complete(self._create_session())
        print(f"  🤖 Agent session: {self._session_id}")

    async def _create_session(self):
        session = await self._session_service.create_session(
            app_name="inspection",
            user_id="local_user",
        )
        return session.id

    def send(self, text: str) -> str:
        return self._loop.run_until_complete(self._send_async(text))

    async def _send_async(self, text: str) -> str:
        message = types.Content(
            role="user",
            parts=[types.Part(text=text)],
        )
        response_parts = []
        async for event in self._runner.run_async(
            user_id="local_user",
            session_id=self._session_id,
            new_message=message,
        ):
            if event.content and event.content.parts:
                for part in event.content.parts:
                    if hasattr(part, "text") and part.text:
                        response_parts.append(part.text)
        return "\n".join(response_parts) if response_parts else ""


# ═══════════════════════════════════════════════════════════════════════════
#  MAIN — always-on mic, interruptible TTS
# ═══════════════════════════════════════════════════════════════════════════

def main(camera_index=0):
    os.makedirs(DATASET_DIR, exist_ok=True)

    manifest = load_manifest()
    sample_id = len(manifest)
    dataset_samples_added = 0

    # ── Init ADK agent ──────────────────────────────────────────────────
    print("🤖 Initializing ADK agent…")
    agent = AgentSession()
    agent.start()

    # ── Start webcam ────────────────────────────────────────────────────
    cap = cv2.VideoCapture(camera_index)
    if not cap.isOpened():
        print(f"❌ Cannot open camera {camera_index}")
        sys.exit(1)

    frame_buf = FrameBuffer()
    stop_event = threading.Event()

    def camera_loop():
        while not stop_event.is_set():
            ret, frame = cap.read()
            if ret:
                frame_buf.push(frame)
                cv2.imshow("Inspection Camera", frame)
                cv2.waitKey(1)
            else:
                time.sleep(0.01)

    cam_thread = threading.Thread(target=camera_loop, daemon=True)
    cam_thread.start()

    # ── Print banner ────────────────────────────────────────────────────
    print("=" * 64)
    print("  📸🎤  CAT 950 VOICE INSPECTION (ADK Agent)")
    print("=" * 64)
    print(f"  Camera  : {camera_index}")
    print(f"  Agent   : GeneratorAgent (gemini-2.5-flash)")
    print(f"  Dataset : {DATASET_DIR}  ({len(manifest)} existing)")
    print()
    print("  🎤 Mic is ALWAYS on.")
    print("  🗣  Speak anytime — agent stops talking and listens.")
    print("  Ctrl+C to quit.")
    print("=" * 64)

    # ── Audio processing queue ──────────────────────────────────────────
    import queue
    audio_queue = queue.Queue()

    def on_audio(recognizer, audio):
        """Called by background listener when speech is detected."""
        # 1. Immediately interrupt any talking agent
        interrupt_tts()
        
        # Minimum duration filter: ignore extremely short bumps/clicks
        wav = audio.get_wav_data()
        duration = len(wav) / (2 * 16000)
        if duration < 0.3:
            return

        print(f"  🎙  Speech detected ({duration:.1f}s), processing…")
        audio_queue.put(audio)

    # ── Worker thread: processes audio → agent → TTS ────────────────────
    def worker():
        nonlocal sample_id, dataset_samples_added

        while not stop_event.is_set():
            try:
                audio = audio_queue.get(timeout=0.5)
            except queue.Empty:
                continue

            # 1. Transcribe (fast — Google Web Speech API)
            try:
                transcript = transcribe_audio(audio)
            except Exception as e:
                print(f"  ⚠  Transcription error: {e}")
                continue

            if not transcript.strip():
                continue

            print(f"\n  📝 You: \"{transcript}\"")

            # 2. Dataset labelling in background
            frames = frame_buf.snapshot()

            def _label_bg(txt, frs):
                nonlocal sample_id, dataset_samples_added
                try:
                    label = extract_label(txt)
                    part = label.get("part", "unknown")
                    section = SECTION_MAP.get(part, "UNKNOWN")
                    label["section"] = section
                    if part != "unknown" and section != "UNKNOWN":
                        sample_id += 1
                        dataset_samples_added += 1
                        sd, ld = save_sample(sample_id, frs, label, txt)
                        ld["sample_dir"] = sd
                        manifest.append(ld)
                        save_manifest(manifest)
                        emoji = {"GREEN": "🟢", "YELLOW": "🟡", "RED": "🔴"}.get(
                            label["status"], "⚪")
                        print(f"  {emoji} Dataset #{dataset_samples_added}  |  "
                              f"[{section}] {part} → {label['status']}")
                except Exception:
                    pass

            threading.Thread(target=_label_bg, args=(transcript, frames),
                             daemon=True).start()

            # 3. Send to ADK agent
            try:
                agent_reply = agent.send(transcript)
            except Exception as e:
                print(f"  ⚠  Agent error: {e}")
                continue

            if not agent_reply.strip():
                continue

            # 4. Speak agent reply (interruptible — user can speak over it)
            print(f"  🤖 Agent: {agent_reply}")
            speak(agent_reply)

    worker_thread = threading.Thread(target=worker, daemon=True)
    worker_thread.start()

    # ── Start always-on mic ─────────────────────────────────────────────
    recognizer = sr.Recognizer()
    mic = sr.Microphone()
    print("  🔊 Adjusting for ambient noise (stay quiet for 2s)...")
    with mic as source:
        recognizer.adjust_for_ambient_noise(source, duration=2)

    # Let the recognizer auto-adjust, but set up standard pause timings
    recognizer.dynamic_energy_threshold = True   # Automatically adjust to background noise
    recognizer.pause_threshold = 0.8            # Need longer pause to end a sentence
    recognizer.non_speaking_duration = 0.5      # Avoid cutting off mid-word

    print(f"  🔊 Calibrated energy threshold: {recognizer.energy_threshold:.0f}")

    stop_listening = recognizer.listen_in_background(
        mic, on_audio, phrase_time_limit=15
    )

    # ── Kick off: get agent greeting ────────────────────────────────────
    print("\n🤖 Agent is starting the conversation…\n")
    greeting = agent.send("Hello, let's start the inspection.")
    print(f"  🤖 Agent: {greeting}")
    speak(greeting)
    print("\n🎤 Mic is live — speak anytime.\n")

    # ── Wait + nudge if silent too long ─────────────────────────────────
    last_activity = time.time()

    def _track_activity():
        nonlocal last_activity
        last_activity = time.time()

    # Monkey-patch: worker updates last_activity on each transcript
    _orig_put = audio_queue.put
    def _tracked_put(item):
        _track_activity()
        _orig_put(item)
    audio_queue.put = _tracked_put

    try:
        while True:
            time.sleep(1)
            if time.time() - last_activity > 30:
                print("  ⏳ No speech detected for 30s…")
                speak("I'm still here. Speak when you're ready.")
                last_activity = time.time()
    except KeyboardInterrupt:
        print("\n\n⏹  Interrupted.")

    stop_listening(wait_for_stop=False)
    stop_event.set()
    time.sleep(0.5)
    cap.release()
    cv2.destroyAllWindows()
    save_manifest(manifest)

    print(f"\n{'=' * 64}")
    print(f"  📊 SESSION SUMMARY")
    print(f"{'=' * 64}")
    print(f"  Dataset samples added : {dataset_samples_added}")
    print(f"  Total dataset samples : {len(manifest)}")
    print(f"  Form/Report           : Saved by ADK agent → Firestore")
    print(f"{'=' * 64}\n")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(
        description="CAT 950 Voice Inspection (ADK Agent + Dataset)")
    parser.add_argument("--camera", type=int, default=0,
                        help="Camera index (default: 0)")
    args = parser.parse_args()
    main(camera_index=args.camera)

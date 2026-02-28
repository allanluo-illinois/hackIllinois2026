import os, sys, time
from dotenv import load_dotenv
from google import genai
from google.genai import types
import speech_recognition as sr

load_dotenv()

client = genai.Client(api_key=os.environ.get("GEMINI_API_KEY"))

MIME = {".wav":"audio/wav",".mp3":"audio/mp3",".flac":"audio/flac",
        ".ogg":"audio/ogg",".aac":"audio/aac",".aiff":"audio/aiff"}

def transcribe(filepath: str) -> str:
    """Transcribe an audio file and return punctuated text."""
    from pathlib import Path
    p = Path(filepath)
    audio_bytes = p.read_bytes()
    resp = client.models.generate_content(
        model="gemini-2.0-flash",
        contents=[
            "Generate an accurate transcript of the speech. "
            "Include proper punctuation and capitalisation. "
            "Output ONLY the transcript text, nothing else.",
            types.Part.from_bytes(data=audio_bytes, mime_type=MIME[p.suffix.lower()]),
        ],
    )
    return resp.text.strip()

def live_transcribe():
    """Listen to mic continuously and print punctuated transcriptions."""
    rec = sr.Recognizer()
    mic = sr.Microphone()
    transcript = []

    with mic as source:
        rec.adjust_for_ambient_noise(source, duration=1)

    print("🎤 Listening… (Ctrl+C to stop)\n")

    def on_audio(_, audio):
        try:
            wav = audio.get_wav_data()
            text = client.models.generate_content(
                model="gemini-2.0-flash",
                contents=[
                    "Generate an accurate transcript of the speech. "
                    "Include proper punctuation and capitalisation. "
                    "Output ONLY the transcript text, nothing else.",
                    types.Part.from_bytes(data=wav, mime_type="audio/wav"),
                ],
            ).text.strip()
            if text:
                transcript.append(text)
                print(f"▸ {text}")
        except Exception as e:
            print(f"Error: {e}")

    stop = rec.listen_in_background(mic, on_audio, phrase_time_limit=15)

    try:
        while True:
            time.sleep(0.2)
    except KeyboardInterrupt:
        stop(wait_for_stop=False)
        print("\n⏹ Stopped.\n")
        if transcript:
            full = " ".join(transcript)
            print(f"── Full Transcript ──\n\n{full}\n")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--live":
        live_transcribe()
    else:
        path = sys.argv[1] if len(sys.argv) > 1 else input("Audio file path: ").strip().strip('"')
        print(transcribe(path))

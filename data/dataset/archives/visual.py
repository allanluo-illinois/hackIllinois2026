"""
visual.py – Continuously capture webcam video in 2-second chunks,
extract 1-3 representative frames from each chunk, and store them.

Frames are saved to a 'captured_frames/' directory, organised by chunk.

Usage:
    python visual.py              # Use default webcam (index 0)
    python visual.py --camera 1   # Use a different camera
    python visual.py --frames 3   # Extract 3 frames per chunk (default: 3)

Press 'q' in the preview window or Ctrl+C in the terminal to stop.
"""

import os
import sys
import time
import argparse
import shutil
from datetime import datetime

import cv2

# ── Configuration ───────────────────────────────────────────────────────────

CHUNK_DURATION = 2.0          # seconds per video chunk
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "captured_frames")

# ── Helpers ─────────────────────────────────────────────────────────────────

def ensure_output_dir():
    """Create (or clear) the output directory."""
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)
    return OUTPUT_DIR


def pick_frame_indices(total_frames, n_frames):
    """Return `n_frames` evenly-spaced indices from [0, total_frames)."""
    if total_frames == 0:
        return []
    if n_frames >= total_frames:
        return list(range(total_frames))
    # Evenly space: start, middle(s), end
    step = (total_frames - 1) / (n_frames - 1) if n_frames > 1 else 0
    return [int(round(i * step)) for i in range(n_frames)]


def save_chunk_frames(frames, chunk_id, n_extract, timestamp_str):
    """Pick n_extract frames from the buffer and save them as JPEGs."""
    indices = pick_frame_indices(len(frames), n_extract)
    saved_paths = []

    chunk_dir = os.path.join(OUTPUT_DIR, f"chunk_{chunk_id:04d}_{timestamp_str}")
    os.makedirs(chunk_dir, exist_ok=True)

    for seq, idx in enumerate(indices):
        filename = f"frame_{seq + 1}.jpg"
        path = os.path.join(chunk_dir, filename)
        cv2.imwrite(path, frames[idx])
        saved_paths.append(path)

    return chunk_dir, saved_paths


# ── Main capture loop ──────────────────────────────────────────────────────

def run(camera_index=0, n_frames=3, show_preview=True):
    ensure_output_dir()

    cap = cv2.VideoCapture(camera_index)
    if not cap.isOpened():
        print(f"❌ Cannot open camera {camera_index}")
        sys.exit(1)

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0:
        fps = 30.0  # fallback
    print(f"📷 Camera opened  |  FPS: {fps:.0f}  |  Chunk: {CHUNK_DURATION}s  "
          f"|  Frames/chunk: {n_frames}")
    print(f"📂 Saving to: {OUTPUT_DIR}")
    print("   Press 'q' in preview or Ctrl+C to stop.\n")

    chunk_id = 0
    frame_buffer = []
    chunk_start = time.time()

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                print("⚠  Lost camera feed. Retrying…")
                time.sleep(0.1)
                continue

            frame_buffer.append(frame)

            # Show a live preview window
            if show_preview:
                cv2.imshow("visual.py – Press Q to stop", frame)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    print("\n⏹  Stopped by user (q).")
                    break

            # Check if 2-second chunk is complete
            elapsed = time.time() - chunk_start
            if elapsed >= CHUNK_DURATION:
                chunk_id += 1
                ts = datetime.now().strftime("%H%M%S")
                chunk_dir, paths = save_chunk_frames(
                    frame_buffer, chunk_id, n_frames, ts
                )
                print(f"  ✅ Chunk {chunk_id:04d}  |  {len(frame_buffer)} raw frames  "
                      f"→  {len(paths)} saved  |  {chunk_dir}")

                # Reset for next chunk
                frame_buffer = []
                chunk_start = time.time()

    except KeyboardInterrupt:
        print("\n⏹  Stopped by user (Ctrl+C).")

    finally:
        # Save any remaining frames in the buffer
        if frame_buffer:
            chunk_id += 1
            ts = datetime.now().strftime("%H%M%S")
            chunk_dir, paths = save_chunk_frames(
                frame_buffer, chunk_id, n_frames, ts
            )
            print(f"  ✅ Chunk {chunk_id:04d} (partial)  |  {len(frame_buffer)} raw frames  "
                  f"→  {len(paths)} saved  |  {chunk_dir}")

        cap.release()
        cv2.destroyAllWindows()

    print(f"\n📸 Done! {chunk_id} chunk(s) saved to {OUTPUT_DIR}")


# ── CLI ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Webcam → 2s chunks → frames")
    parser.add_argument("--camera", type=int, default=0,
                        help="Camera index (default: 0)")
    parser.add_argument("--frames", type=int, default=3, choices=[1, 2, 3],
                        help="Frames to extract per 2s chunk (default: 3)")
    parser.add_argument("--no-preview", action="store_true",
                        help="Disable the live preview window")
    args = parser.parse_args()

    run(camera_index=args.camera, n_frames=args.frames,
        show_preview=not args.no_preview)

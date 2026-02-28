
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

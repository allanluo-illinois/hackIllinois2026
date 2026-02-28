import cv2
import os

def extract_frames(video_path, output_folder, frames_per_second=2):
    # 1. Create output directory
    if not os.path.exists(output_folder):
        os.makedirs(output_folder)

    # 2. Initialize video capture
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print("Error: Could not open video file.")
        return

    # Get video metadata
    video_fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    
    # Calculate skip interval
    # e.g., if video is 30fps and we want 2fps, we take every 15th frame
    hop = round(video_fps / frames_per_second)
    
    print(f"Video FPS: {video_fps}")
    print(f"Extracting 1 frame every {hop} frames (~{frames_per_second} FPS)...")

    count = 0
    saved_count = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # Only save frames at the calculated interval
        if count % hop == 0:
            # Use zfill for zero-padded filenames (e.g., 0001.jpg) 
            # This helps COLMAP maintain sequential order.
            filename = os.path.join(output_folder, f"frame_{saved_count:04d}.jpg")
            cv2.imwrite(filename, frame)
            saved_count += 1

        count += 1

    cap.release()
    print(f"Done! Saved {saved_count} frames to '{output_folder}'.")

# --- Usage ---
# Change these values to match your file names
input_video = "wheelloader360.mp4"
output_dir = "images"
extract_frames(input_video, output_dir, frames_per_second=2)
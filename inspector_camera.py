import os
import shutil
import time
from google import genai
from google.genai import types

def evaluate_and_capture(comment: str, stream_dir: str, session_folder: str, api_key: str) -> bool:
    # 0. Load the photo into memory FIRST to avoid race conditions
    photo_data = None
    ext = ".jpg"
    source_path = None
    
    if os.path.exists(stream_dir):
        # We take the most recently added or first photo
        photos = os.listdir(stream_dir)
        if photos:
            source_photo = photos[0]
            source_path = os.path.join(stream_dir, source_photo)
            ext = os.path.splitext(source_photo)[1] or ".jpg"
            try:
                with open(source_path, "rb") as f:
                    photo_data = f.read()
            except Exception:
                pass

    # 1. Configure the Gemini API client
    client = genai.Client(api_key=api_key)
    
    # 2. Define the model
    model_id = 'gemini-2.5-flash-lite'
    
    # 3. Create the prompt instructing the model to output a strict YES or NO
    prompt = f"""
    Decide save photo: comment indicates damage/issue? Reply YES else NO.
    Comment: "{comment}"
    Do not include any other text.
    """
    
    try:
        response = client.models.generate_content(
            model=model_id,
            contents=prompt,
            config=types.GenerateContentConfig(
                max_output_tokens=5,  # We only need 1 token ("YES" or "NO")
                temperature=0.0       # Make it deterministic and fast
            )
        )
        verdict = response.text.strip().upper()
        
        # 4. Process the decision
        if "YES" in verdict:
            if not photo_data:
                return False
                
            # Create the dataset/session_folder directory
            save_dir = os.path.join("dataset", session_folder)
            os.makedirs(save_dir, exist_ok=True)
            
            # Generate a unique filename based on timestamp
            timestamp = int(time.time())
            filename = f"issue_{timestamp}{ext}"
            dest_path = os.path.join(save_dir, filename)
            
            # Save the pre-loaded photo data to the dataset folder
            try:
                with open(dest_path, "wb") as f:
                    f.write(photo_data)
                
                # Delete the original from stream to simulate 'moving' it
                if source_path and os.path.exists(source_path):
                    try:
                        os.remove(source_path)
                    except Exception as rm_e:
                        pass # Ignore if stream system already deleted it
                        
                return True
            except Exception:
                return False
                
        else:
            return False
            
    except Exception:
        return False

# ==========================================
# Testing block for local isolation
# ==========================================
if __name__ == "__main__":
    # Put your API key here for isolated testing.
    TEST_API_KEY = "YOUR_GEMINI_API_KEY_HERE"
     
    if TEST_API_KEY == "YOUR_GEMINI_API_KEY_HERE":
        print("Please replace 'YOUR_GEMINI_API_KEY_HERE' in the script with your actual Gemini API key before running.")
    else:
        test_session = "session_001"
        test_stream_dir = os.path.join("data", "stream")
        
        negative_comment = "the part is completely broken and rusted"
        evaluate_and_capture(negative_comment, test_stream_dir, test_session, TEST_API_KEY)
        print("done")

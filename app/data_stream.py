import threading
import uvicorn
from fastapi import FastAPI, UploadFile, File
import shutil
import os
# 1. Define the tiny Upload Server
upload_api = FastAPI()
UPLOAD_PATH = "data/stream/current_frame.jpg"

@upload_api.post("/upload-frame")
async def upload_frame(file: UploadFile = File(...)):
    os.makedirs(os.path.dirname(UPLOAD_PATH), exist_ok=True)
    with open(UPLOAD_PATH, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"status": "ok"}

# 2. Run it in a background thread so it doesn't block the ADK
def run_upload_server():
    uvicorn.run(upload_api, host="0.0.0.0", port=8001)

threading.Thread(target=run_upload_server, daemon=False).start()

# 3. Expose the agent for ADK Web
from agents.agent import root_agent
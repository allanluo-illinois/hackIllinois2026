import os
import uvicorn
from fastapi import FastAPI, Request
from pydantic import BaseModel
from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai import types
from dotenv import load_dotenv
import asyncio
import base64

load_dotenv()
UPLOAD_PATH = "app/data/stream/current_frame.jpg"

# map GOOGLE_API_KEY → GEMINI_API_KEY
os.environ["GEMINI_API_KEY"] = os.environ.get("GOOGLE_API_KEY", "")
# Import your agents
from agents.adk_agents import generator_agent, reviewer_agent

app = FastAPI(title="ADK Inspection API")

# --- 1. ADK INITIALIZATION ---
generator_memory = InMemorySessionService() 
generator_runner = Runner(
    agent=generator_agent,
    session_service=generator_memory, 
    app_name="field_inspector"
)

reviewer_memory = InMemorySessionService() 
reviewer_runner = Runner(
    agent=reviewer_agent,
    session_service=reviewer_memory, 
    app_name="management_analytics"
)

# --- 2. DATA MODELS (For better Flutter integration) ---
class ChatRequest(BaseModel):
    user_id: str = "default_user"
    session_id: str = "current_inspection"
    text: str = ""
class FrameData(BaseModel):
    image_64: str  # The raw base64 string from Flutter
# --- 3. ENDPOINTS ---
@app.post("/upload_data")
async def upload_frame(data: FrameData):
    # Ensure the directory exists
    os.makedirs(os.path.dirname(UPLOAD_PATH), exist_ok=True)
    
    try:
        # 2. Decode the Base64 string into raw bytes
        # If your Flutter string starts with "data:image/png;base64,", 
        # you may need to strip the prefix: data.image_64.split(",")[-1]
        image_bytes = base64.b64decode(data.image_64)
        
        # 3. Save the binary data
        with open(UPLOAD_PATH, "wb") as buffer:
            buffer.write(image_bytes)
            
        return {"status": "ok", "size": len(image_bytes)}
    except Exception as e:
        return {"status": "error", "message": str(e)}
async def background_automation():
    while True:
        # 1. Look at your sessions/data
        # 2. Do your logic (e.g., "If 5 mins passed, send alert")
        print("🤖 Automation checking data...")
        
        await asyncio.sleep(10) # Wait 10 seconds before checking again

@app.on_event("startup")
async def launch_automation():
    # This starts the loop without blocking the API from responding to Flutter
    asyncio.create_task(background_automation())
@app.post("/chat")
async def chat(request: ChatRequest):
    # Ensure session exists in Generator memory
    session = await generator_runner.session_service.get_session(
        app_name="field_inspector",
        user_id=request.user_id,
        session_id=request.session_id,
    )

    if session is None:
        print(f"📦 Creating session: {request.session_id}")
        await generator_runner.session_service.create_session(
            app_name="field_inspector",
            user_id=request.user_id,
            session_id=request.session_id,
        )
    new_message = types.Content(
        role="user",
        parts=[types.Part(text=request.text)]
    )

    # Run the Generator Agent
    final_response = "I'm sorry, I couldn't process that."
    async for event in generator_runner.run_async(
        user_id=request.user_id,
        session_id=request.session_id,
        new_message=new_message,
    ):
        if event.is_final_response():
            final_response = event.content.parts[0].text

    return {
        "status": "success",
        "message": final_response,
        "session_id": request.session_id
    }

@app.post("/review")
async def review(request: ChatRequest):
    # Ensure session exists in Reviewer memory
    session = await reviewer_runner.session_service.get_session(
        app_name="management_analytics",
        user_id=request.user_id,
        session_id=request.session_id,
    )

    if session is None:
        print(f"📦 Creating session: {request.session_id}")
        await reviewer_runner.session_service.create_session(
            app_name="management_analytics",
            user_id=request.user_id,
            session_id=request.session_id,
        )

    new_message = types.Content(
        role="user",
        parts=[types.Part(text=request.text)]
    )

    # Run the Reviewer Agent
    final_analysis = "The reviewer was unable to complete the analysis."
    async for event in reviewer_runner.run_async(
        user_id=request.user_id,
        session_id=request.session_id,
        new_message=new_message,
    ):
        if event.is_final_response():
            final_analysis = event.content.parts[0].text

    return {
        "status": "success",
        "analysis": final_analysis,
        "session_id": request.session_id
    }

if __name__ == "__main__":
    # Start the server using Uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
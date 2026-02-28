import os
import uvicorn
from fastapi import FastAPI, Request
from pydantic import BaseModel
from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai import types
from dotenv import load_dotenv

load_dotenv()

# map GOOGLE_API_KEY → GEMINI_API_KEY
os.environ["GEMINI_API_KEY"] = os.environ.get("GOOGLE_API_KEY", "")
# Import your agents
from app.agents.adk_agents import generator_agent, reviewer_agent

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

# --- 3. ENDPOINTS ---

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
    events = generator_runner.run(
        user_id=request.user_id,
        session_id=request.session_id,
        new_message=new_message
    )

    final_response = "I'm sorry, I couldn't process that."
    for event in events:
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
    events = reviewer_runner.run(
        user_id=request.user_id,
        session_id=request.session_id,
        new_message=new_message
    )

    final_analysis = "The reviewer was unable to complete the analysis."
    for event in events:
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
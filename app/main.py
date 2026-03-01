# import os
# import uvicorn
# from fastapi import FastAPI, Request
# from pydantic import BaseModel
# from google.adk.runners import Runner
# from google.adk.sessions import InMemorySessionService
# from google.genai import types
# from dotenv import load_dotenv
# import asyncio
# from fastapi import File, UploadFile
# from fastapi import WebSocket, WebSocketDisconnect
import os
import io
import wave
import re
import base64
import asyncio
import shutil
import torch
import numpy as np
import uvicorn
from fastapi import FastAPI, Request, File, UploadFile, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from dotenv import load_dotenv

from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai import types
from google import genai
from app.agents.adk_agents import generator_agent, reviewer_agent
import shutil
import json
import os
import ctypes.util
from jinja2 import Template
from weasyprint import HTML

load_dotenv()
UPLOAD_PATH = "app/data/stream/current_frame.jpg"

# map GOOGLE_API_KEY → GEMINI_API_KEY
os.environ["GEMINI_API_KEY"] = os.environ.get("GOOGLE_API_KEY", "")
_api_key = os.environ.get("GEMINI_API_KEY")
# Import your agents
from agents.adk_agents import generator_agent, reviewer_agent

app = FastAPI(title="ADK Inspection API")
model, utils = torch.hub.load(repo_or_dir='snakers4/silero-vad', model='silero_vad')
(get_speech_timestamps, _, _, VADIterator, _) = utils
# --- 1. ADK INITIALIZATION ---
gemini_client = genai.Client(api_key=_api_key)

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
# --- VOICE ENDPOINTS ---
async def transcribe_audio_bytes(wav_bytes: bytes) -> str:
    """Transcribe raw WAV bytes using Gemini API."""
    try:
        prompt = "Please accurately transcribe this audio. Reply ONLY with the exact transcript."
        # Run synchronous Gemini call in a thread so we don't block the WebSocket
        response = await asyncio.to_thread(
            gemini_client.models.generate_content,
            model="gemini-2.5-flash",
            contents=[prompt, types.Part.from_bytes(data=wav_bytes, mime_type='audio/wav')]
        )
        return (response.text or "").strip()
    except Exception as e:
        print(f"  ⚠  Gemini STT error: {e}")
        return ""

# --- 3. ENDPOINTS ---
@app.post("/upload-frame")
async def upload_frame(file: UploadFile = File(...)):
    """
    Matches Flutter's http.MultipartRequest.
    'file' matches the key used in request.files.add
    """
    # Ensure directory exists
    os.makedirs(os.path.dirname(UPLOAD_PATH), exist_ok=True)
    
    try:
        # FastAPI's UploadFile provides a file-like object in 'file.file'
        with open(UPLOAD_PATH, "wb") as buffer:
            # shutil.copyfileobj is memory-efficient for streaming the file to disk
            shutil.copyfileobj(file.file, buffer)
            
        return {"status": "ok", "filename": file.filename}
    except Exception as e:
        return {"status": "error", "message": str(e)}
# async def background_automation():
#     while True:
#         # 1. Look at your sessions/data
#         # 2. Do your logic (e.g., "If 5 mins passed, send alert")
#         print("🤖 Automation checking data...")
        
#         await asyncio.sleep(10) # Wait 10 seconds before checking again

# @app.on_event("startup")
# async def launch_automation():
#     # This starts the loop without blocking the API from responding to Flutter
#     asyncio.create_task(background_automation())
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
# webscoket for speech conversation:
@app.websocket("/ws/stt")
async def websocket_stt_endpoint(websocket: WebSocket):
    await websocket.accept()
    
    # Internal State
    is_recording = False
    audio_buffer = bytearray()
    vad_iterator = VADIterator(model)

    print("🔌 STT WebSocket Connected.")

    try:
        while True:
            # Receive message (could be Text/JSON or Bytes)
            message = await websocket.receive()

            # --- HANDLE COMMANDS (Toggle) ---
            if "text" in message:
                command = json.loads(message["text"])
                
                if command.get("type") == "start":
                    print("▶️ Recording Started...")
                    is_recording = True
                    audio_buffer.clear()
                    vad_iterator.reset_states()
                
                elif command.get("type") == "stop":
                    print("⏹ Recording Stopped by Client.")
                    is_recording = False
                    # Optional: Force transcribe what's left in the buffer
                    if len(audio_buffer) > 0:
                        await process_and_send_transcript(websocket, audio_buffer)
                        audio_buffer.clear()

            # --- HANDLE AUDIO BYTES ---
            elif "bytes" in message and is_recording:
                data = message["bytes"]
                audio_buffer.extend(data)

                # Convert to float32 for VAD
                audio_int16 = np.frombuffer(data, dtype=np.int16)
                audio_float32 = audio_int16.astype(np.float32) / 32768.0
                
                # Check for "Natural" silence even if user hasn't hit 'stop'
                speech_dict = vad_iterator(torch.from_numpy(audio_float32), return_seconds=True)
                
                if speech_dict and "end" in speech_dict:
                    print("🛑 Silence detected. Auto-finalizing...")
                    is_recording = False # Flip state back to idle
                    await process_and_send_transcript(websocket, audio_buffer)
                    audio_buffer.clear()

    except WebSocketDisconnect:
        print("🔌 STT Disconnected.")

async def process_and_send_transcript(websocket, buffer):
    """Helper to wrap, transcribe, and send JSON back."""
    wav_data = await pcm_to_wav(buffer)
    transcript = await transcribe_audio_bytes(wav_data)
    await websocket.send_json({
        "type": "transcript",
        "text": transcript,
        "status": "idle" # Tell Flutter we are done
    })
async def pcm_to_wav(pcm_bytes: bytearray, sample_rate=16000) -> bytes:
    """Helper to wrap raw PCM bytes into a WAV container."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav_file:
        wav_file.setnchannels(1)  # Mono
        wav_file.setsampwidth(2)  # 16-bit (2 bytes per sample)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(pcm_bytes)
    return buf.getvalue()
@app.post("/load-inspection")
async def load_inspection(payload: dict = Body(...)):
    # payload is now a full Python dictionary, not a string
    machine_model = payload.get("machine", {}).get("model") # e.g., "CAT 950"
    serial_no = payload.get("machine", {}).get("serial_number") # e.g., "5678"
    html_template = """
    <!DOCTYPE html>
    <html>
    <head>
        <style>
            @page { size: letter; margin: 0.5in; }
            body { font-family: 'Helvetica', 'Arial', sans-serif; color: #333; line-height: 1.2; font-size: 10pt; }
            
            /* Brand Header */
            .brand-header { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 3px solid #000; padding-bottom: 10px; margin-bottom: 15px; }
            .brand-title { color: #000; font-size: 18pt; font-weight: bold; text-transform: uppercase; }
            .brand-subtitle { font-size: 12pt; margin-top: 5px; }
            .logo-placeholder { background: #FFCD00; padding: 10px; font-weight: bold; border: 1px solid #000; }

            /* Meta Data Grid */
            .meta-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 15px; }
            .meta-table { width: 100%; border-collapse: collapse; }
            .meta-table td { padding: 4px; border-bottom: 1px solid #eee; }
            .label { font-weight: bold; color: #555; width: 40%; }

            /* Summary Bar */
            .summary-bar { background: #f2f2f2; padding: 10px; border-left: 5px solid #FFCD00; margin-bottom: 20px; }
            .comments-box { font-style: italic; color: #444; margin-top: 5px; }

            /* Section Styling */
            .section-header { background: #333; color: #FFCD00; padding: 6px 10px; font-weight: bold; text-transform: uppercase; margin-top: 20px; }
            
            /* Inspection Table */
            table.inspection-data { width: 100%; border-collapse: collapse; margin-bottom: 10px; }
            table.inspection-data th { background: #eee; text-align: left; padding: 8px; border: 1px solid #ddd; font-size: 9pt; }
            table.inspection-data td { padding: 8px; border: 1px solid #ddd; vertical-align: top; }
            
            /* Status Indicators */
            .status { font-weight: bold; text-align: center; width: 80px; }
            .status-PASS { color: #2e7d32; }
            .status-NORMAL { color: #2e7d32; }
            .status-MONITOR { background: #fff3cd; color: #856404; }
            .status-FAIL { background: #f8d7da; color: #721c24; }
            
            .comp-name { font-weight: bold; }
            .comp-comment { font-size: 9pt; color: #666; margin-top: 4px; display: block; }

            .footer { margin-top: 30px; font-size: 8pt; color: #999; text-align: center; border-top: 1px solid #ddd; padding-top: 10px; }
        </style>
    </head>
    <body>

        <div class="brand-header">
            <div>
                <div class="brand-title">Wheel Loader: Safety & Maintenance</div>
                <div class="brand-subtitle">Executive Summary Report </div>
            </div>
            <div class="logo-placeholder"> ILLINI CAT </div>
        </div>

        <div class="meta-grid">
            <table class="meta-table">
                <tr><td class="label">Inspection No</td><td>22892110 </td></tr>
                <tr><td class="label">Serial Number</td><td>{{ machine.serial_number }} </td></tr>
                <tr><td class="label">Model</td><td>{{ machine.model }} </td></tr>
                <tr><td class="label">Asset ID</td><td>FL-3062 </td></tr>
            </table>
            <table class="meta-table">
                <tr><td class="label">Inspector</td><td>John Doe </td></tr>
                <tr><td class="label">Date Generated</td><td>{{ date_generated }} </td></tr>
                <tr><td class="label">SMU (Hours)</td><td>1027 Hours </td></tr>
                <tr><td class="label">Location</td><td>East Peoria, IL </td></tr>
            </table>
        </div>

        <div class="summary-bar">
            <strong>General Info & Comments </strong>
            <div class="comments-box">
                {{ general_comments or "Scales screen freezes during operation" }} 
            </div>
        </div>

        {% for section_name, items in sections.items() %}
        <div class="section-header">
            {{ section_name.replace('_', ' ') }} 
        </div>
        <table class="inspection-data">
            <thead>
                <tr>
                    <th style="width: 45%;">Component</th>
                    <th style="width: 15%;">Status</th>
                    <th style="width: 40%;">Observations / Comments </th>
                </tr>
            </thead>
            <tbody>
                {% for item in items %}
                <tr>
                    <td><span class="comp-name">{{ loop.index }}. {{ item.component }}</span></td>
                    <td class="status status-{{ item.status }}">
                        {{ item.status }} 
                    </td>
                    <td>
                        <span class="comp-comment">{{ item.comments }}</span>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
        {% endfor %}

    </body>
    </html>
    """

    # 3. Render and Save
    template = Template(html_template)
    final_html = template.render(payload)
    pdf_bytes = HTML(string=final_html).write_pdf()

    # Return the PDF as a binary response
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename=inspection_{payload['machine']['serial_number']}.pdf"
        }
    )
@app.websocket("/ws/inspect")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    audio_buffer = bytearray()
    print("🔌 Voice Client connected.")
    
    # We will use a fixed user/session for the live connection
    user_id = "live_user"
    session_id = "live_inspection"

    # Ensure session exists
    session = await generator_runner.session_service.get_session(
        app_name="field_inspector", user_id=user_id, session_id=session_id)
    if session is None:
        await generator_runner.session_service.create_session(
            app_name="field_inspector", user_id=user_id, session_id=session_id)

    try:
        while True:
            # Expecting JSON from Flutter: {"type": "audio_utterance", "data": "<base64_wav>"}
            data = await websocket.receive_bytes()
            audio_buffer.extend(data)
            if len(audio_buffer) > 320000: # 1 second at 16kHz 16-bit
                # Transcribe the current buffer
                transcript = await transcribe_pcm_to_text(audio_buffer)
                
                if "done" in transcript.lower():
                    audio_buffer.clear()
            # message = await websocket.receive_json()
            # msg_type = message.get("type")

            if msg_type == "audio_utterance":
                print("🎙 Receiving audio utterance from client...")
                audio_data = base64.b64decode(message["data"])
                
                # 1. Transcribe the audio
                transcript = await transcribe_audio_bytes(audio_data)
                if not transcript:
                    continue
                
                print(f"📝 You said: {transcript}")
                # Send the text back so the UI updates instantly
                await websocket.send_json({"type": "user_transcript", "text": transcript})

                # 2. Send text to the ADK Generator Agent
                new_message = types.Content(role="user", parts=[types.Part(text=transcript)])
                
                # Using run_async for better performance in the websocket
                response_parts = []
                async for event in generator_runner.run_async(
                    user_id=user_id, session_id=session_id, new_message=new_message
                ):
                    if event.content and event.content.parts:
                        for part in event.content.parts:
                            if hasattr(part, "text") and part.text:
                                response_parts.append(part.text)
                
                agent_reply = "\n".join(response_parts)
                print(f"🤖 Agent: {agent_reply}")
                
                # Send text back to UI
                await websocket.send_json({"type": "agent_text", "text": agent_reply})

                # # 3. Generate Audio and send back to client
                # tts_bytes = await generate_tts_bytes(agent_reply)
                # if tts_bytes:
                #     await websocket.send_json({
                #         "type": "agent_audio", 
                #         "data": base64.b64encode(tts_bytes).decode('utf-8')
                #     })

    except WebSocketDisconnect:
        print("🔌 Voice Client disconnected.")
if __name__ == "__main__":
    # Start the server using Uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
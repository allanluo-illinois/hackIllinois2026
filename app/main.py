import firebase_admin
from firebase_admin import credentials, firestore
from app.agents.generator import GeneratorAgent
from app.agents.reviewer import ReviewerAgent
import os
import json
from dotenv import load_dotenv
import vertexai
from vertexai.generative_models import GenerativeModel, ChatSession


# 1. Load the .env from the root
dotenv_path = os.path.join(os.path.dirname(__file__), '..', '.env')
load_dotenv(dotenv_path)

# 2. Set the GOOGLE_APPLICATION_CREDENTIALS for Vertex AI
# This replaces the need for 'gcloud auth application-default login'
os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")

PROJECT_ID = os.getenv("GCP_PROJECT_ID")
LOCATION = os.getenv("GCP_LOCATION")

# 3. Initialize Vertex AI
vertexai.init(project=PROJECT_ID, location=LOCATION)
model = GenerativeModel("gemini-1.5-flash")

# 4. Initialize Firebase using the same path
if not firebase_admin._apps:
    cred = credentials.Certificate(os.getenv("GOOGLE_APPLICATION_CREDENTIALS"))
    firebase_admin.initialize_app(cred)

db = firestore.client()

# 3. INITIALIZE VERTEX AI (Gemini)
vertexai.init(project=PROJECT_ID, location=LOCATION)
# Using 1.5-Flash for faster "field" response times
model = GenerativeModel("gemini-1.5-flash")

def start_inspection_chat():
    agent = GeneratorAgent(db)
    chat = model.start_chat()
    
    print("--- 🚜 CAT 950 GENERATOR: ACTIVE WALKROUND ---")
    # Send the system prompt first to set the rules
    chat.send_message(agent.get_system_prompt())
    
    print("Assistant: Hello! Please provide the Serial Number and your name to begin[cite: 211, 214].")

    while not agent.is_complete:
        user_input = input("\nTechnician: ")

        if user_input.lower() in ['exit', 'quit']:
            break
        
        # 2. Send technician input to Gemini
        response = chat.send_message(user_input)
        
        try:
            # 3. Parse the JSON response from the AI
            res_data = json.loads(response.text)
            print(f"\nAssistant: {res_data['message']}")
            
            # 4. Update the local agent state
            if res_data.get("updates"):
                agent.update_report_state(res_data["updates"])
            
            # 5. Check for completion
            if "inspection complete" in res_data['message'].lower():
                save_confirm = input("\nSave this report to Firestore? (yes/no): ")
                if save_confirm.lower() == 'yes':
                    result = agent.finalize_and_save()
                    print(f"✅ {result}")
                    break

        except json.JSONDecodeError:
            print(f"\nAssistant: {response.text}") # Fallback if AI didn't send JSON
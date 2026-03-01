import os
import firebase_admin
from firebase_admin import credentials, firestore
from google.adk.tools import FunctionTool
from app.tools.firebase_ops import save_inspection_report, get_reports_by_serial, update_inspection_in_db
import datetime
import copy

# 1. Initialize Firestore
if not firebase_admin._apps:
    cred = credentials.Certificate(os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "service-account.json"))
    firebase_admin.initialize_app(cred)

db = firestore.client()

# 2. Define Wrapper Functions (ADK uses these for Name & Description)
def submit_final_completed_inspection(report_data: dict) -> dict:
    """Saves the final validated inspection report to Firestore."""
    return save_inspection_report(db, report_data)

def fetch_machine_history(serial_number: str) -> list:
    """Retrieves the last 10 inspection reports for a specific serial number."""
    # Convert the Firestore stream to a list of dicts for the AI
    reports = get_reports_by_serial(db, serial_number)
    return [doc.to_dict() for doc in reports]

def update_past_report(serial_number: str, timestamp: str, updates: dict) -> dict:
    """
    Updates specific fields in a historical inspection report.
    'timestamp' must be the exact ISO timestamp of the report to update.
    'updates' MUST use exact Firestore dot-notation paths starting with 'sections.', 
    e.g., {"sections.GROUND.tires_wheels_stem_caps_lug_nuts.status": "YELLOW"}
    """
    return update_inspection_in_db(db, serial_number, timestamp, updates)



# 3. Initialize Tools (No 'name' or 'description' arguments needed)
submit_final_completed_inspection_tool = FunctionTool(func=submit_final_completed_inspection)
fetch_history_tool = FunctionTool(func=fetch_machine_history)
update_report_tool = FunctionTool(func=update_past_report)
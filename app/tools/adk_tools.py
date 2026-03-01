import os
import firebase_admin
from firebase_admin import credentials, firestore, storage
from google.adk.tools import FunctionTool
from tools.firebase_ops import save_inspection_report, get_reports_by_serial, update_inspection_in_db, upload_defect_photo_to_storage
import datetime
import copy
import json


# 1. Initialize Firestore
if not firebase_admin._apps:
    cred = credentials.Certificate(os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "service-account.json"))
    firebase_admin.initialize_app(cred, {
        'storageBucket': 'cat-inspection-488804.firebasestorage.app' 
    })
db = firestore.client()

def submit_final_completed_inspection(report_data: str, photo_links: str = "{}") -> dict:
    """
    TERMINAL ACTION: Use ONLY ONCE at the end.
    CRITICAL: You MUST pass 'report_data' and 'photo_links' as valid JSON STRINGS, not objects.
    'photo_links' should be a JSON string mapping the component key to the public URL.
    """
    try:
        # Failsafe: Parse the JSON string back into a Python dictionary
        report_dict = json.loads(report_data) if isinstance(report_data, str) else report_data
        photo_dict = json.loads(photo_links) if isinstance(photo_links, str) else photo_links
        
        return save_inspection_report(db, report_dict, photo_dict)
    except Exception as e:
        return {"success": False, "error": f"JSON Parsing Error. Ensure you send a string: {str(e)}"}

def fetch_machine_history(serial_number: str) -> list:
    """Retrieves the last 10 inspection reports for a specific serial number."""
    # Convert the Firestore stream to a list of dicts for the AI
    reports = get_reports_by_serial(db, serial_number)
    return [doc.to_dict() for doc in reports]

def update_past_report(serial_number: str, timestamp: str, updates: str) -> dict:
    """
    Updates specific fields in a historical inspection report.
    'timestamp' must be the exact ISO timestamp of the report to update.
    CRITICAL: 'updates' MUST be a valid JSON STRING representing the dictionary of updates.
    """
    try:
        updates_dict = json.loads(updates) if isinstance(updates, str) else updates
        return update_inspection_in_db(db, serial_number, timestamp, updates_dict)
    except Exception as e:
        return {"status": "error", "message": f"JSON Parsing Error: {str(e)}"}

def capture_defect_photo(serial_number: str, component_name: str) -> dict:
    """
    Captures the current camera frame and uploads it to cloud storage.
    Call this IMMEDIATELY when a component is marked as YELLOW or RED.
    """
    return upload_defect_photo_to_storage(serial_number, component_name)

# 3. Initialize Tools (No 'name' or 'description' arguments needed)
submit_final_completed_inspection_tool = FunctionTool(func=submit_final_completed_inspection)
fetch_history_tool = FunctionTool(func=fetch_machine_history)
update_report_tool = FunctionTool(func=update_past_report)
capture_photo_tool = FunctionTool(func=capture_defect_photo) # <-- ADD THIS HERE
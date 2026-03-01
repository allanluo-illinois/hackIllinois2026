from firebase_admin import firestore
import datetime
import copy

#Template
GROUND_KEYS = [
    "tires_wheels_stem_caps_lug_nuts", "bucket_cutting_edge_moldboard", 
    "bucket_cylinders_lines_hoses", "loader_frame_arms", "underneath_machine",
    "transmission_transfer_case", "steps_handholds", "fuel_tank",
    "differential_final_drive_oil", "air_tank", "axles_brakes_seals",
    "hydraulic_tank", "transmission_oil", "lights_front_rear",
    "battery_compartment", "def_tank", "overall_machine"
]

ENGINE_KEYS = [
    "engine_oil", "engine_coolant", "radiator", "all_hoses_and_lines",
    "fuel_filters_water_separator", "all_belts", "air_filter", "overall_engine_compartment"
]

CAB_EXTERIOR_KEYS = [
    "handholds", "rops", "fire_extinguisher", "windshield_windows", 
    "wipers_washers", "doors"
]

CAB_INTERIOR_KEYS = [
    "seat", "seat_belt_mounting", "horn_alarm_lights", "mirrors", 
    "cab_air_filter", "gauges_indicators_switches", "overall_cab_interior"
]

def get_empty_section(keys):
    return {key: {"status": "YELLOW", "comments": "DID NOT RECORD"} for key in keys}

def get_fresh_template():
    """Generates a fresh template with the current exact timestamp."""
    return {
        "header": {
            "serial_number": None, 
            "inspector": None, 
            "date": str(datetime.date.today()), 
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "machine_hours": 0
        },
        "sections": {
            "GROUND": get_empty_section(GROUND_KEYS),
            "ENGINE": get_empty_section(ENGINE_KEYS),
            "CAB_EXTERIOR": get_empty_section(CAB_EXTERIOR_KEYS),
            "CAB_INTERIOR": get_empty_section(CAB_INTERIOR_KEYS)
        },
        "general_comments": "",
        "primary_status": None
    }

#Data Validation Schema Mask
def enforce_schema(payload: dict, template: dict) -> dict:
    """
    Recursively walks the template and copies values from the AI payload.
    Completely strips out any AI hallucinations.
    """
    clean_data = copy.deepcopy(template)
    
    if not isinstance(payload, dict):
        return clean_data
        
    for key, default_value in template.items():
        if key in payload:
            # If the template expects a nested dictionary (like 'header' or 'GROUND')
            if isinstance(default_value, dict) and isinstance(payload[key], dict):
                clean_data[key] = enforce_schema(payload[key], default_value)
            else:
                # It's a standard value, safely copy the AI's value
                clean_data[key] = payload[key]
                
    return clean_data

def save_inspection_report(db, report_data: dict) -> dict:
    """Saves a schema-validated report to Firestore."""
    try:
        # 1. Get a pristine template with a current timestamp
        fresh_template = get_fresh_template()
        
        # 2. Mask the incoming AI payload against our strict template
        clean_report = enforce_schema(report_data, fresh_template)
        
        # 3. Perform our final safety check on the sanitized data
        if not clean_report.get("primary_status"):
            return {"success": False, "error": "Missing primary_status"}
        if clean_report.get("general_comments") is None:
            return {"success": False, "error": "Missing general_comments. You must ask the technician for final comments."}
            
        if not clean_report["header"].get("serial_number"):
            return {"success": False, "error": "Missing serial_number in header."}
        # 4. Save the guaranteed-clean data to Firestore
        doc_ref = db.collection('inspection_reports').document()
        doc_ref.set(clean_report)
        return {"success": True, "report_id": doc_ref.id}
        
    except Exception as e:
        return {"success": False, "error": str(e)}

def get_reports_by_serial(db, serial_number: str) -> list:
    """Retrieves the last 10 inspection reports for a specific serial number, newest first."""
    reports = (
        db.collection("inspection_reports")
        .where("header.serial_number", "==", serial_number)
        .order_by("header.timestamp", direction=firestore.Query.DESCENDING) # Sorts newest to oldest
        .limit(10)
        .stream()
    )
    return reports

def update_inspection_in_db(db, serial_number: str, timestamp: str, updates: dict) -> dict:
    """
    Finds a specific inspection report by serial number and precise timestamp, 
    and applies a dictionary of updates to it.
    """
    try:
        collection_ref = db.collection("inspection_reports")
        
        # FIXED: Only one query using the exact timestamp
        query = (
            collection_ref
            .where("header.serial_number", "==", serial_number)
            .where("header.timestamp", "==", timestamp) 
            .limit(1)
        )
        
        docs = query.stream()
        doc_ref = None
        
        for doc in docs:
            doc_ref = doc.reference
            break 
            
        if not doc_ref:
            return {
                "status": "error", 
                "message": f"Could not find a report for serial {serial_number} at {timestamp}."
            }
            
        doc_ref.update(updates)
        
        return {
            "status": "success", 
            "message": f"Successfully updated {len(updates)} fields for {serial_number}."
        }
        
    except Exception as e:
        return {
            "status": "error", 
            "message": f"Database error: {str(e)}"
        }
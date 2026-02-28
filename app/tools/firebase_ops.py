from firebase_admin import firestore

def save_inspection_report(db, report_data):
    """Saves a validated report to Firestore."""
    try:
        if not report_data.get("primary_status"):
            return {"success": False, "error": "Missing primary_status"}
        
        doc_ref = db.collection('inspection_reports').document()
        doc_ref.set(report_data)
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
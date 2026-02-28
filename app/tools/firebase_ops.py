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

def get_reports_by_serial(db, serial_number, limit=10):
    """Fetches the most recent reports for a specific machine."""
    return db.collection('inspection_reports') \
             .where('header.serial_number', '==', str(serial_number)) \
             .order_by('header.date', direction=firestore.Query.DESCENDING) \
             .limit(limit).stream()

def update_existing_report(db, doc_id, update_data):
    """Performs CRUD update on a specific report document."""
    try:
        doc_ref = db.collection('inspection_reports').document(doc_id)
        doc_ref.update(update_data)
        return {"success": True}
    except Exception as e:
        return {"success": False, "error": str(e)}
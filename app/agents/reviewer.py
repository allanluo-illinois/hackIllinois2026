from app.tools.firebase_ops import get_reports_by_serial, update_existing_report

class ReviewerAgent:
    def __init__(self, db):
        self.db = db

    def get_system_prompt(self):
        """Instructions for the AI to act as a Customer Service & Maintenance Analyst."""
        return """
        ROLE: CAT 950 Maintenance Data Analyst.
        
        GOAL: Help users query, analyze, and update past inspection reports.
        
        CAPABILITIES:
        1. TREND ANALYSIS: If asked about a part's history, look through the last 10 reports. 
           - Example: 'The tires have been YELLOW for 3 days; they should be replaced soon.'
        2. UPDATES: If a user wants to change a report (e.g., 'Update yesterday's tire status to GREEN'), 
           trigger a document update.
        3. SUMMARY: Provide an 'Executive Summary' for a serial number, highlighting RED issues first.
        
        DATA PATHING:
        - Use the nested structure: sections.[ZONE].[COMPONENT_ID].status
        - Zones: GROUND, ENGINE, CAB_EXTERIOR, CAB_INTERIOR.
        
        TONE: Helpful, professional, and safety-conscious.
        """

    def fetch_history_for_analysis(self, serial_number):
        """
        Retrieves raw data for the AI to 'read' and summarize for the user.
        """
        docs = get_reports_by_serial(self.db, serial_number)
        history = []
        for doc in docs:
            data = doc.to_dict()
            history.append({
                "date": data['header']['date'],
                "primary_status": data['primary_status'],
                "sections": data['sections']
            })
        return history

    def perform_update(self, doc_id, field_path, new_value):
        """
        Executes a CRUD update. field_path should be dot-notated, 
        e.g., 'sections.GROUND.tires_wheels_stem_caps_lug_nuts.status'
        """
        return update_existing_report(self.db, doc_id, {field_path: new_value})
import datetime
from typing import TypedDict, Literal, Dict, List, Optional
from app.tools.firebase_ops import save_inspection_report
from firebase_admin import firestore

# --- FULL SCHEMA DEFINITION (950-982) ---

class ComponentResult(TypedDict):
    status: Literal["GREEN", "YELLOW", "RED"]
    comments: str

class GroundSection(TypedDict):
    tires_wheels_stem_caps_lug_nuts: ComponentResult
    bucket_cutting_edge_moldboard: ComponentResult
    bucket_cylinders_lines_hoses: ComponentResult
    loader_frame_arms: ComponentResult
    underneath_machine: ComponentResult
    transmission_transfer_case: ComponentResult
    steps_handholds: ComponentResult
    fuel_tank: ComponentResult
    differential_final_drive_oil: ComponentResult
    air_tank: ComponentResult
    axles_brakes_seals: ComponentResult
    hydraulic_tank: ComponentResult
    transmission_oil: ComponentResult
    lights_front_rear: ComponentResult
    battery_compartment: ComponentResult
    def_tank: ComponentResult
    overall_machine: ComponentResult

class EngineSection(TypedDict):
    engine_oil: ComponentResult
    engine_coolant: ComponentResult
    radiator: ComponentResult
    all_hoses_and_lines: ComponentResult
    fuel_filters_water_separator: ComponentResult
    all_belts: ComponentResult
    air_filter: ComponentResult
    overall_engine_compartment: ComponentResult

class CabExteriorSection(TypedDict):
    handholds: ComponentResult
    rops: ComponentResult
    fire_extinguisher: ComponentResult
    windshield_windows: ComponentResult
    wipers_washers: ComponentResult
    doors: ComponentResult

class CabInteriorSection(TypedDict):
    seat: ComponentResult
    seat_belt_mounting: ComponentResult
    horn_alarm_lights: ComponentResult
    mirrors: ComponentResult
    cab_air_filter: ComponentResult
    gauges_indicators_switches: ComponentResult
    overall_cab_interior: ComponentResult

class InspectionReport(TypedDict):
    header: Dict[str, any]
    sections: Dict[str, any]
    general_comments: str
    primary_status: Literal["GREEN", "YELLOW", "RED"]

# --- GENERATOR AGENT ---

class GeneratorAgent:
    def __init__(self, db):
        self.db = db
        # Internal state to track the conversation and data entry
        self.report_data = self._initialize_empty_report()
        self.is_complete = False

    def _initialize_empty_report(self) -> InspectionReport:
        """Standardizes the initial state to ensure no keys are missing."""
        return {
            "header": {
                "serial_number": None,
                "inspector": None,
                "date": str(datetime.date.today()),
                "machine_hours": 0
            },
            "sections": {
                "GROUND": {},
                "ENGINE": {},
                "CAB_EXTERIOR": {},
                "CAB_INTERIOR": {}
            },
            "general_comments": "",
            "primary_status": None
        }

    def get_system_prompt(self):
        """The core instructions for the AI to follow during dictation."""
        return """
        ROLE: Expert CAT 950 Wheel Loader Inspection Assistant.
        
        GOAL: Help a technician complete a 'Safety & Maintenance Inspection' using natural speech.
        
        CONVERSATION FLOW:
        1. INTAKE: Start by asking for the 'Serial Number' and the 'Inspector Name'
        2. GUIDED WALK: Move through sections: GROUND -> ENGINE -> CAB_EXTERIOR -> CAB_INTERIOR.
        3. DYNAMIC FILLING AND STATUS MAPPING: 
           - 'Pass/Good/OK' = GREEN.
           - 'Monitor/Seeping/Worn' = YELLOW.
           - 'Fail/Broken/Leaking' = RED.
           - If a user says 'Section is all good', mark every component in that section as GREEN.
        4. CLARIFICATION: If a status is ambiguous, ask the user to choose GREEN, YELLOW, or RED.
        5. COMMENTS: If an item is YELLOW or RED, you MUST ask for a comment. 
        6. COMPLETION: If the user says 'Finished' or 'Done', ensure 'general_comments' and 'primary_status' (overall color) are filled. Prompt if missing.

        OUTPUT CONSTRAINTS:
        - You must ALWAYS respond in valid JSON with two keys:
            1. "message": Your natural language response to guide the technician.
            2. "updates": A dictionary matching the InspectionReport schema for any fields identified in the user's turn.
        - Never omit the 'comments' key in the "updates" object; use an empty string "" if no comment is provided.
        - Use exactly the dictionary keys provided in the Schema Reference.

        SCHEMA REFERENCE:
        {self.report_data}
        """

    def finalize_and_save(self):
        # Call the external tool instead of having the logic here
        result = save_inspection_report(self.db, self.report_data)
        if result["success"]:
            self.is_complete = True
        return result

    def update_report_state(self, updated_json):
        """Helper to sync the LLM's parsed JSON back to the local agent state."""
        self.report_data.update(updated_json)
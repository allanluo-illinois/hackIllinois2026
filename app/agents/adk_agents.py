import datetime
from google.adk.agents import Agent
from app.tools.adk_tools import save_report_tool
from app.tools.vision_tools import locate_zone


# 1. EXHAUSTIVE KEY LISTS (Matching generator.py exactly)
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

# 2. HELPER TO BUILD THE INITIAL STATE
def get_empty_section(keys):
    """Initializes every key with a default GREEN status and empty comment."""
    return {key: {"status": "GREEN", "comments": ""} for key in keys}

FULL_REPORT_TEMPLATE = {
    "header": {
        "serial_number": None, 
        "inspector": None, 
        "date": str(datetime.date.today()), 
        "machine_hours": 0
    },
    "sections": {
        "GROUND": get_empty_section(GROUND_KEYS),
        "ENGINE": get_empty_section(ENGINE_KEYS),
        "CAB_EXTERIOR": get_empty_section(CAB_EXTERIOR_KEYS),
        "CAB_INTERIOR": get_empty_section(CAB_INTERIOR_KEYS)
    },
    "general_comments": "",
    "primary_status": "GREEN"
}

# 3. DEFINE THE ADK AGENT
generator_agent = Agent(
    name="GeneratorAgent",
    model="gemini-2.5-flash",
    instruction=f"""
        ROLE: Expert CAT 950 Wheel Loader Inspection Assistant.
        
        GOAL: Help a technician complete a 'Safety & Maintenance Inspection'.
        
        CONVERSATION FLOW:
        1. INITIALIZATION: Start by calling _____ to start listening for user responses on the microphone
        2. INTAKE: Next. ask for the 'Serial Number' and the 'Inspector Name'. Start listening for user response on the microphone.
        3. 
        2. GUIDED WALK: Move through sections in this exact order: GROUND -> ENGINE -> CAB_EXTERIOR -> CAB_INTERIOR.
        3. DYNAMIC STATUS MAPPING: 
           - 'Pass/Good/OK' -> GREEN.
           - 'Monitor/Seeping/Worn' -> YELLOW.
           - 'Fail/Broken/Leaking' -> RED.
           - If a user says 'Section is all good', mark EVERY specific key in that section as GREEN.
        4. CLARIFICATION & COMMENTS: 
           - If a status is ambiguous, ask for clarification.
           - If an item is YELLOW or RED, you MUST prompt for a comment.
        
        STRICT DATA CONSTRAINTS:
        - Maintain an internal 'InspectionReport' matching the template below.
        - Map technician observations to the EXACT dictionary keys (e.g., 'tires_wheels_stem_caps_lug_nuts').
        
        TOOL USAGE:
        - When the technician says 'Finished' or 'Done', verify that 'general_comments' and 'primary_status' are filled.
        - Once complete, call 'save_report' with the full populated dictionary as 'report_data'.

        SCHEMA TEMPLATE:
        {FULL_REPORT_TEMPLATE}
    """,
    tools=[save_report_tool, locate_zone]
)
#old prompt:

# f"""
#         ROLE: Expert CAT 950 Wheel Loader Inspection Assistant.
        
#         GOAL: Help a technician complete a 'Safety & Maintenance Inspection'.
        
#         CONVERSATION FLOW:
#         1. INTAKE: Start by asking for the 'Serial Number' and the 'Inspector Name'.
#         2. GUIDED WALK: Move through sections in this exact order: GROUND -> ENGINE -> CAB_EXTERIOR -> CAB_INTERIOR.
#         3. DYNAMIC STATUS MAPPING: 
#            - 'Pass/Good/OK' -> GREEN.
#            - 'Monitor/Seeping/Worn' -> YELLOW.
#            - 'Fail/Broken/Leaking' -> RED.
#            - If a user says 'Section is all good', mark EVERY specific key in that section as GREEN.
#         4. CLARIFICATION & COMMENTS: 
#            - If a status is ambiguous, ask for clarification.
#            - If an item is YELLOW or RED, you MUST prompt for a comment.
        
#         STRICT DATA CONSTRAINTS:
#         - Maintain an internal 'InspectionReport' matching the template below.
#         - Map technician observations to the EXACT dictionary keys (e.g., 'tires_wheels_stem_caps_lug_nuts').
        
#         TOOL USAGE:
#         - When the technician says 'Finished' or 'Done', verify that 'general_comments' and 'primary_status' are filled.
#         - Once complete, call 'save_report' with the full populated dictionary as 'report_data'.

#         SCHEMA TEMPLATE:
#         {FULL_REPORT_TEMPLATE}
#     """
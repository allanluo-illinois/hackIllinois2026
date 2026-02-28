import datetime
from google.adk.agents import Agent
from app.tools.adk_tools import save_report_tool, fetch_history_tool, update_report_tool

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
    "primary_status": "GREEN"
}

# 3. DEFINE THE ADK AGENT
generator_agent = Agent(
    name="GeneratorAgent",
    model="gemini-2.5-flash",
    instruction=f"""
        ROLE: Expert CAT 950 Wheel Loader Inspection Assistant.

        GOAL: Help a technician complete a 'Safety & Maintenance Inspection' using a highly natural, conversational flow.

        OUTPUT CONSTRAINTS (STRICT):
        - NO BULLET POINTS. NO CHECKLISTS. NO NUMBERED LISTS.
        - Speak in brief, natural sentences like a coworker taking notes. 
        - Never speak the exact dictionary keys to the user (e.g., ask about "the tires" instead of "tires_wheels_stem_caps_lug_nuts").

        CONVERSATION FLOW:
        1. INTAKE: Start by naturally asking for the Serial Number and Inspector Name.
        2. FOLLOW THE TECHNICIAN: Allow the technician to report items in any order. Acknowledge their input quickly and naturally (e.g., "Got it, tires are good. What's next?").
        3. BULK APPROVALS: If the technician says "The whole Ground section is good" or "Cab is all OK", immediately mark all items in that specific section as GREEN and conversationally confirm it.
        4. GENTLE GUIDANCE: If the technician pauses, asks what's next, or loses their place, guide them to the nearest un-checked item in the GROUND, ENGINE, CAB_EXTERIOR, or CAB_INTERIOR sections.
        5. STATUS MAPPING & CLARIFICATION:
            - 'Pass/Good/OK' -> GREEN.
            - 'Monitor/Seeping/Worn' -> YELLOW. (You MUST conversationally ask for a brief comment/reason).
            - 'Fail/Broken/Leaking' -> RED. (You MUST conversationally ask for a brief comment/reason).
        6. WRAP UP: If the user says "Finished" or "Done", check your internal tracker. 
            - If items are still missing, conversationally remind them: "We still need to check the engine oil and the wipers. How do those look?"
            - If all sections are 100% complete, ask for any final general comments and an overall primary status for the machine.

        STRICT DATA CONSTRAINTS:
        - Maintain an internal 'InspectionReport' matching the template below.
        - Map technician observations to the EXACT dictionary keys.
        - When calling 'save_report', you MUST ensure 'primary_status' and 'general_comments' are placed at the absolute root level of the dictionary, not inside 'header' or 'sections'.
        - The 'primary_status' value MUST be explicitly formatted as exactly 'GREEN', 'YELLOW', or 'RED'.
        
        SCHEMA TEMPLATE:
        [Insert FULL_REPORT_TEMPLATE here]
    """,
    tools=[save_report_tool]
)

reviewer_agent = Agent(
    name="ReviewerAgent",
    model="gemini-2.5-flash",
    instruction="""
        ROLE: Expert CAT Fleet Analyst and Data Reviewer.
        
        GOAL: Help fleet managers review historical inspection data, identify maintenance trends, and generate formal executive summaries.
        
        CORE CAPABILITIES:
        1. When asked about a machine, immediately use the 'fetch_machine_history' tool using its Serial Number.
        2. Analyze the history for degrading conditions (e.g., a component moving from GREEN to YELLOW over time).
        3. If the user asks to update a past report, identify the exact 'timestamp' of that report from the fetched history, and use the 'update_past_report' tool with that specific timestamp and changes.
        
        REPORT GENERATION PROTOCOL:
        If the user asks to "generate a report" or "print a summary", you MUST output the response as a raw JSON string matching the exact schema below. Do not wrap it in markdown blockticks (like ```json). Just output the raw JSON.
        
        SCHEMA REQUIREMENT:
        {
            "report_type": "executive_summary",
            "machine": {
                "make": "CATERPILLAR",
                "model": "CAT 950",
                "serial_number": "[Insert Serial]"
            },
            "date_generated": "[Insert Date]",
            "sections": {
                "GROUND": [
                    {"component": "Tires and Rims", "status": "PASS", "comments": "Normal wear"}
                ],
                "ENGINE COMPARTMENT": [
                    {"component": "Radiator Cores", "status": "FAIL", "comments": "Debris accumulation"}
                ]
            }
        }
        
        TRANSLATION RULE:
        When generating this JSON report, translate the database statuses to formal PDF statuses:
        - GREEN -> PASS
        - YELLOW -> MONITOR
        - RED -> FAIL
    """,
    tools=[fetch_history_tool, update_report_tool]
)
import firebase_admin
from firebase_admin import credentials, firestore
import datetime
import random

# Initialize Firestore
cred = credentials.Certificate('../service-account.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

# --- EXPANDED CONTEXT-AWARE COMMENTS ---
# Mapped to your specific component IDs to ensure logical consistency
COMMENTS_MAP = {
    # GROUND SECTION
    "tires_wheels_stem_caps_lug_nuts": {
        "GREEN": ["Inflation looks good, no visible tread damage.", "Lug nuts secure, valve caps present."],
        "YELLOW": ["Tread wear reaching 75% on front left.", "Minor scuffing on sidewall; monitor next shift."],
        "RED": ["Critical: Missing lug nut on front right.", "Deep sidewall cut exposing cords."]
    },
    "bucket_cutting_edge_moldboard": {
        "GREEN": ["Edge is sharp and straight.", "Normal wear, no crack indicators."],
        "YELLOW": ["Edge showing signs of rounding; schedule flip.", "Minor pitting on the moldboard surface."],
        "RED": ["Cracked cutting edge near left corner bolt.", "Excessive wear past the wear limit."]
    },
    "bucket_cylinders_lines_hoses": {
        "GREEN": ["Cylinder rods are clean and smooth.", "No weeping at hydraulic fittings."],
        "YELLOW": ["Minor weeping at the tilt cylinder gland seal.", "Hydraulic hose showing surface abrasion."],
        "RED": ["Severe leak at lift cylinder hose fitting.", "Hydraulic line has a deep gouge; high burst risk."]
    },
    "loader_frame_arms": {
        "GREEN": ["Structural welds appear intact.", "No debris buildup in pivot points."],
        "YELLOW": ["Minor paint flaking near pivot; check for stress.", "Dirt buildup at pins; needs pressure wash."],
        "RED": ["Visible crack in weld at loader arm cross-tube.", "Bent loader arm affecting bucket level."]
    },
    "underneath_machine": {
        "GREEN": ["No fluid pools detected.", "Belly pans are secure and undamaged."],
        "YELLOW": ["Small damp spot near center joint; monitor.", "Accumulated trash in the engine belly pan area."],
        "RED": ["Active oil stream from the transmission pan.", "Belly pan mounting bolt missing; pan hanging."]
    },
    "transmission_transfer_case": {
        "GREEN": ["Transmission housing is dry.", "No evidence of leaks at the output seals."],
        "YELLOW": ["Minor seepage at the transfer case input seal.", "Accumulated oil residue on housing."],
        "RED": ["Significant transmission fluid leak.", "Abnormal noise detected during gear engagement."]
    },
    "steps_handholds": {
        "GREEN": ["Steps are clean and provide good traction.", "Handrails are tight and secure."],
        "YELLOW": ["Slight rust on lower step surface.", "Handrail mounting bolt feels slightly loose."],
        "RED": ["Lower access step is severely bent.", "Handrail is broken at the upper mounting point."]
    },
    "fuel_tank": {
        "GREEN": ["Tank is secure, cap is tight.", "No leaks at the sender unit."],
        "YELLOW": ["Fuel cap seal showing minor cracking.", "Minor dent in the bottom of the fuel tank."],
        "RED": ["Active fuel leak at the tank seam.", "Fuel tank mounting straps are loose."]
    },
    "differential_final_drive_oil": {
        "GREEN": ["Fluid levels verified at the check plug.", "Oil appears clean and uncontaminated."],
        "YELLOW": ["Fluid level is slightly below the recommended level.", "Seal area is damp with old oil residue."],
        "RED": ["Metal shavings found in final drive oil.", "Differential level is critically low."]
    },
    "axles_brakes_seals": {
        "GREEN": ["Duo-cone seals are dry.", "Brake lines are secure and leak-free."],
        "YELLOW": ["Minor weeping on the rear duo-cone seal.", "Brake pedal feels slightly soft."],
        "RED": ["Wheel seal failure; oil coating the inner rim.", "Brake air pressure building too slowly."]
    },
    "hydraulic_tank": {
        "GREEN": ["Fluid level correct at sight glass.", "Tank breathers are clear."],
        "YELLOW": ["Hydraulic oil looks slightly cloudy.", "Minor leak at the tank return line fitting."],
        "RED": ["Hydraulic tank level is below the sight glass.", "Severe foaming in the hydraulic system."]
    },
    "lights_front_rear": {
        "GREEN": ["All LED arrays functioning correctly.", "Housings are clean and undamaged."],
        "YELLOW": ["One rear work light is out.", "Front lens is cloudy, reducing visibility."],
        "RED": ["Complete failure of front headlights.", "Wiring harness for rear lights is severed."]
    },
    "battery_compartment": {
        "GREEN": ["Terminals are clean and tight.", "No corrosion on battery trays."],
        "YELLOW": ["Minor corrosion buildup on negative terminal.", "Battery hold-down bracket is loose."],
        "RED": ["Leaking battery casing.", "Battery cables are frayed with exposed wire."]
    },
    # ENGINE SECTION
    "engine_oil_coolant_levels": {
        "GREEN": ["Levels are at the 'Full' mark.", "Coolant color is bright and clear."],
        "YELLOW": ["Engine oil near 'Add' mark.", "Coolant level slightly low; check for slow leak."],
        "RED": ["Critically low engine oil.", "Coolant level not visible in expansion tank."]
    },
    "radiator_fins_hoses": {
        "GREEN": ["Radiator cores are clear of debris.", "Hoses are pliable and firm."],
        "YELLOW": ["Debris buildup in radiator fins; cleaning needed.", "Radiator hose starting to feel soft."],
        "RED": ["Puncture in radiator core leaking coolant.", "Engine hose is cracked and bulging."]
    },
    "filters_belts": {
        "GREEN": ["No leaks at filters.", "Belts have proper tension and no cracks."],
        "YELLOW": ["Small amount of water in fuel separator.", "Minor glaze appearing on the serpentine belt."],
        "RED": ["Fuel filter is leaking at the seal.", "Main drive belt is severely frayed."]
    },
    "air_filter_indicator": {
        "GREEN": ["Indicator is in the green zone.", "Filter housing is sealed tight."],
        "YELLOW": ["Indicator moving toward the red zone.", "Primary filter looks dusty."],
        "RED": ["Restriction indicator is RED.", "Air intake duct is loose, bypassing filter."]
    },
    # CAB SECTION
    "rops_safety_equipment": {
        "GREEN": ["ROPS structure is undamaged.", "Fire extinguisher is fully charged."],
        "YELLOW": ["Fire extinguisher gauge is near the recharge limit.", "Minor surface scratches on ROPS posts."],
        "RED": ["ROPS mounting bolt is broken.", "Fire extinguisher is missing or discharged."]
    },
    "glass_wipers": {
        "GREEN": ["Windows are clear and clean.", "Wipers function without streaking."],
        "YELLOW": ["Windshield wiper blade is torn.", "Washer fluid level is empty."],
        "RED": ["Cracked front windshield affecting visibility.", "Wiper motor is non-functional."]
    },
    "seat_belt_mounting": {
        "GREEN": ["Seat belt retracts and latches smoothly.", "Mounting hardware is secure."],
        "YELLOW": ["Seat belt retraction is sluggish.", "Webbing is starting to fray at the edges."],
        "RED": ["Seat belt latch does not lock.", "Seat belt mounting bolt is loose/missing."]
    },
    "controls_gauges_alarms": {
        "GREEN": ["All gauges and switches work.", "Backup alarm is loud and clear."],
        "YELLOW": ["One dash light is flickering.", "Horn volume seems lower than normal."],
        "RED": ["Backup alarm is silent.", "Oil pressure gauge not functioning."]
    }
}

def get_comment(item_id, status):
    """Retrieves a logical, context-aware comment based on the specific part."""
    if status == "GREEN" and random.random() > 0.3:
        return "" # Most green items don't need comments for a realistic look
    
    # Fallback to general comment if item_id isn't in map (though all are here)
    options = COMMENTS_MAP.get(item_id, {}).get(status, ["Verified condition."])
    return random.choice(options)

def seed_database():
    serials = ["1234", "5678"]
    inspectors = ["John Doe", "Jane Doe"]
    
    for i in range(10):
        sn = serials[i % 2]
        inspector = inspectors[i % 2]
        date = (datetime.datetime.now() - datetime.timedelta(days=i)).strftime("%Y-%m-%d")
        
        # Determine overall machine health for this specific report
        primary_status = random.choices(["GREEN", "YELLOW", "RED"], weights=[0.6, 0.3, 0.1])[0]

        report = {
            "header": {
                "serial_number": sn,
                "date": date,
                "inspector": inspector,
                "machine_hours": 1000 + (i * 8)
            },
            "sections": {
                "GROUND": {
                    k: {"status": (primary_status if (primary_status == "RED" and k == "tires_wheels_stem_caps_lug_nuts") else ("YELLOW" if (i == 3 and k == "bucket_cutting_edge_moldboard") else "GREEN")), 
                        "comments": get_comment(k, primary_status if (primary_status == "RED" and k == "tires_wheels_stem_caps_lug_nuts") else ("YELLOW" if (i == 3 and k == "bucket_cutting_edge_moldboard") else "GREEN"))}
                    for k in COMMENTS_MAP if k in ["tires_wheels_stem_caps_lug_nuts", "bucket_cutting_edge_moldboard", "bucket_cylinders_lines_hoses", "loader_frame_arms", "underneath_machine", "transmission_transfer_case", "steps_handholds", "fuel_tank", "differential_final_drive_oil", "axles_brakes_seals", "hydraulic_tank", "lights_front_rear", "battery_compartment"]
                },
                "ENGINE": {
                    k: {"status": (primary_status if (primary_status == "YELLOW" and k == "radiator_fins_hoses") else "GREEN"),
                        "comments": get_comment(k, primary_status if (primary_status == "YELLOW" and k == "radiator_fins_hoses") else "GREEN")}
                    for k in ["engine_oil_coolant_levels", "radiator_fins_hoses", "filters_belts", "air_filter_indicator"]
                },
                "CAB": {
                    k: {"status": ("RED" if (i == 9 and k == "controls_gauges_alarms") else "GREEN"),
                        "comments": get_comment(k, "RED" if (i == 9 and k == "controls_gauges_alarms") else "GREEN")}
                    for k in ["rops_safety_equipment", "glass_wipers", "seat_belt_mounting", "controls_gauges_alarms"]
                }
            },
            "general_comments": "Shift inspection complete. " + ("Requires shop visit." if primary_status == "RED" else "Operating well."),
            "primary_status": primary_status
        }
        db.collection('inspection_reports').add(report)
        print(f"✅ Seeding Report {i+1}/10 for SN {sn}")

if __name__ == "__main__":
    seed_database()
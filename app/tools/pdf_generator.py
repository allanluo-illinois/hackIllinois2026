"""PDF Report Generation for CAT Inspection Reports"""

import io
from datetime import datetime
from typing import Dict, Any, List
from reportlab.lib.pagesizes import letter, A4
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT


def status_to_badge_color(status: str) -> tuple:
    """Convert status string to RGB color tuple."""
    status_upper = (status or "").upper()
    if status_upper == "GREEN" or status_upper == "PASS":
        return colors.HexColor("#4CAF50")  # Green
    elif status_upper == "YELLOW" or status_upper == "MONITOR":
        return colors.HexColor("#FFC107")  # Amber
    elif status_upper == "RED" or status_upper == "FAIL":
        return colors.HexColor("#F44336")  # Red
    else:
        return colors.HexColor("#9E9E9E")  # Gray


def status_to_text_color(status: str) -> tuple:
    """Get contrasting text color for status badge."""
    status_upper = (status or "").upper()
    if status_upper == "YELLOW" or status_upper == "MONITOR":
        return colors.HexColor("#000000")  # Black text on light background
    else:
        return colors.HexColor("#FFFFFF")  # White text


def format_status_badge(status: str) -> str:
    """Format status as friendly string."""
    status_upper = (status or "").upper()
    mapping = {
        "GREEN": "✓ PASS",
        "YELLOW": "⚠ MONITOR",
        "RED": "✗ FAIL",
        "PASS": "✓ PASS",
        "MONITOR": "⚠ MONITOR",
        "FAIL": "✗ FAIL",
    }
    return mapping.get(status_upper, status)


def generate_inspection_pdf(report_data: Dict[str, Any]) -> bytes:
    """
    Generate a professional PDF inspection report from inspection data.

    Args:
        report_data: Dictionary containing inspection report with structure:
            {
                "header": {...},
                "sections": {"GROUND": {...}, "ENGINE": {...}, ...},
                "general_comments": "...",
                "primary_status": "GREEN|YELLOW|RED"
            }

    Returns:
        PDF as bytes
    """
    # Create PDF buffer
    pdf_buffer = io.BytesIO()

    # Create document
    doc = SimpleDocTemplate(
        pdf_buffer,
        pagesize=letter,
        rightMargin=0.5 * inch,
        leftMargin=0.5 * inch,
        topMargin=0.5 * inch,
        bottomMargin=0.5 * inch,
    )

    # Style definitions
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=24,
        textColor=colors.HexColor("#1565C0"),
        spaceAfter=12,
        alignment=TA_CENTER,
        fontName='Helvetica-Bold',
    )

    heading_style = ParagraphStyle(
        'SectionHead',
        parent=styles['Heading2'],
        fontSize=14,
        textColor=colors.HexColor("#0D47A1"),
        spaceAfter=8,
        spaceBefore=12,
        fontName='Helvetica-Bold',
    )

    normal_style = styles['Normal']

    # Build document content
    content = []

    # ── HEADER ──
    header = report_data.get("header", {})

    # Title
    content.append(Paragraph("CAT 950-982 Inspection Report", title_style))
    content.append(Spacer(1, 0.1 * inch))

    # Header Info Table
    header_data = [
        ["Serial Number", header.get("serial_number", "N/A")],
        ["Inspector", header.get("inspector", "N/A")],
        ["Date", header.get("date", datetime.now().strftime("%Y-%m-%d"))],
        ["Machine Hours", str(header.get("machine_hours", "0"))],
    ]

    header_table = Table(header_data, colWidths=[2 * inch, 3.5 * inch])
    header_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (0, -1), colors.HexColor("#E3F2FD")),
        ('TEXTCOLOR', (0, 0), (-1, -1), colors.black),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 10),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
        ('TOPPADDING', (0, 0), (-1, -1), 8),
        ('GRID', (0, 0), (-1, -1), 1, colors.HexColor("#BBDEFB")),
    ]))

    content.append(header_table)
    content.append(Spacer(1, 0.2 * inch))

    # ── SECTIONS ──
    sections = report_data.get("sections", {})

    for section_name, components in sections.items():
        # Section heading
        section_display_name = section_name.replace("_", " ").title()
        content.append(Paragraph(section_display_name, heading_style))

        # Build table of components
        table_data = [["Component", "Status", "Comments"]]

        for component_key, component_data in components.items():
            if isinstance(component_data, dict):
                comp_status = component_data.get("status", "—")
                comp_comments = component_data.get("comments", "")
            else:
                comp_status = "—"
                comp_comments = ""

            # Format component name
            component_display = component_key.replace("_", " ").title()
            status_display = format_status_badge(comp_status)

            table_data.append([
                component_display,
                status_display,
                comp_comments[:50] + ("..." if len(comp_comments) > 50 else "")
            ])

        # Create section table
        section_table = Table(table_data, colWidths=[2.5 * inch, 1.2 * inch, 2.3 * inch])

        # Style the table
        section_table.setStyle(TableStyle([
            # Header row
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor("#1565C0")),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
            ('ALIGN', (0, 0), (-1, 0), 'CENTER'),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, 0), 11),
            ('BOTTOMPADDING', (0, 0), (-1, 0), 10),
            ('TOPPADDING', (0, 0), (-1, 0), 10),

            # Data rows
            ('ALIGN', (0, 1), (0, -1), 'LEFT'),
            ('ALIGN', (1, 1), (1, -1), 'CENTER'),
            ('ALIGN', (2, 1), (2, -1), 'LEFT'),
            ('FONTSIZE', (0, 1), (-1, -1), 9),
            ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor("#F5F5F5")]),
            ('GRID', (0, 0), (-1, -1), 1, colors.HexColor("#CCCCCC")),
            ('VALIGN', (0, 0), (-1, -1), 'TOP'),
            ('TOPPADDING', (0, 1), (-1, -1), 6),
            ('BOTTOMPADDING', (0, 1), (-1, -1), 6),
        ]))

        content.append(section_table)
        content.append(Spacer(1, 0.15 * inch))

    # ── SUMMARY ──
    content.append(Paragraph("Summary", heading_style))

    primary_status = report_data.get("primary_status", "UNKNOWN")
    general_comments = report_data.get("general_comments", "No additional comments.")

    summary_data = [
        ["Overall Status", format_status_badge(primary_status)],
        ["General Comments", general_comments],
    ]

    summary_table = Table(summary_data, colWidths=[2 * inch, 3.5 * inch])
    summary_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (0, -1), colors.HexColor("#FFF3E0")),
        ('TEXTCOLOR', (0, 0), (-1, -1), colors.black),
        ('ALIGN', (0, 0), (0, -1), 'CENTER'),
        ('ALIGN', (1, 0), (1, -1), 'LEFT'),
        ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 10),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
        ('TOPPADDING', (0, 0), (-1, -1), 8),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('GRID', (0, 0), (-1, -1), 1, colors.HexColor("#FFD7B5")),
    ]))

    content.append(summary_table)
    content.append(Spacer(1, 0.2 * inch))

    # Footer
    footer_text = f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}"
    content.append(Paragraph(
        footer_text,
        ParagraphStyle('Footer', parent=normal_style, fontSize=8, textColor=colors.grey)
    ))

    # Build PDF
    doc.build(content)

    # Get PDF bytes
    pdf_buffer.seek(0)
    return pdf_buffer.getvalue()


def get_sample_inspection_report() -> Dict[str, Any]:
    """
    Returns a sample inspection report for demo purposes.
    """
    return {
        "header": {
            "serial_number": "CAT-950-2024-0472",
            "inspector": "John Smith",
            "date": datetime.now().strftime("%Y-%m-%d"),
            "timestamp": datetime.now().isoformat(),
            "machine_hours": 2847
        },
        "sections": {
            "GROUND": {
                "tires_wheels_stem_caps_lug_nuts": {
                    "status": "GREEN",
                    "comments": "All tires at proper pressure, no visible wear."
                },
                "bucket_cutting_edge_moldboard": {
                    "status": "GREEN",
                    "comments": "Cutting edge in good condition."
                },
                "bucket_cylinders_lines_hoses": {
                    "status": "YELLOW",
                    "comments": "Minor seeping detected on left cylinder. Monitor."
                },
                "loader_frame_arms": {
                    "status": "GREEN",
                    "comments": "Frame and arms intact, no visible damage."
                },
                "underneath_machine": {
                    "status": "GREEN",
                    "comments": "Undercarriage clean, no debris."
                },
                "transmission_transfer_case": {
                    "status": "GREEN",
                    "comments": "No leaks, seals intact."
                },
                "steps_handholds": {
                    "status": "GREEN",
                    "comments": "All steps and handholds secure."
                },
                "fuel_tank": {
                    "status": "GREEN",
                    "comments": "Tank secure, no leaks."
                },
                "differential_final_drive_oil": {
                    "status": "YELLOW",
                    "comments": "Level slightly below minimum. Top off before next shift."
                },
                "air_tank": {
                    "status": "GREEN",
                    "comments": "Tank and lines in good condition."
                },
                "axles_brakes_seals": {
                    "status": "GREEN",
                    "comments": "All seals intact, brakes responsive."
                },
                "hydraulic_tank": {
                    "status": "GREEN",
                    "comments": "Fluid level at proper mark."
                },
                "transmission_oil": {
                    "status": "GREEN",
                    "comments": "Oil level normal."
                },
                "lights_front_rear": {
                    "status": "GREEN",
                    "comments": "All lights functional."
                },
                "battery_compartment": {
                    "status": "GREEN",
                    "comments": "Battery terminals clean, connections tight."
                },
                "def_tank": {
                    "status": "GREEN",
                    "comments": "DEF level adequate."
                },
                "overall_machine": {
                    "status": "GREEN",
                    "comments": "Overall machine condition is good."
                }
            },
            "ENGINE": {
                "engine_oil": {
                    "status": "GREEN",
                    "comments": "Oil level normal, no leaks."
                },
                "engine_coolant": {
                    "status": "GREEN",
                    "comments": "Coolant level at proper mark."
                },
                "radiator": {
                    "status": "YELLOW",
                    "comments": "Minor debris on fins. Clean before high-temperature operations."
                },
                "all_hoses_and_lines": {
                    "status": "GREEN",
                    "comments": "All hoses intact and secure."
                },
                "fuel_filters_water_separator": {
                    "status": "GREEN",
                    "comments": "Filters clean, no signs of fuel contamination."
                },
                "all_belts": {
                    "status": "GREEN",
                    "comments": "All belts show normal wear, tensioned correctly."
                },
                "air_filter": {
                    "status": "GREEN",
                    "comments": "Air filter clean."
                },
                "overall_engine_compartment": {
                    "status": "GREEN",
                    "comments": "Engine compartment clean, no visible issues."
                }
            },
            "CAB_EXTERIOR": {
                "handholds": {
                    "status": "GREEN",
                    "comments": "All handholds secure."
                },
                "rops": {
                    "status": "GREEN",
                    "comments": "ROPS structure intact."
                },
                "fire_extinguisher": {
                    "status": "GREEN",
                    "comments": "Fire extinguisher present and sealed."
                },
                "windshield_windows": {
                    "status": "GREEN",
                    "comments": "All windows intact, no cracks."
                },
                "wipers_washers": {
                    "status": "GREEN",
                    "comments": "Wipers functional, washer fluid full."
                },
                "doors": {
                    "status": "GREEN",
                    "comments": "Doors open and close smoothly."
                }
            },
            "CAB_INTERIOR": {
                "seat": {
                    "status": "GREEN",
                    "comments": "Seat in good condition, suspension functional."
                },
                "seat_belt_mounting": {
                    "status": "GREEN",
                    "comments": "Seat belt functional and secure."
                },
                "horn_alarm_lights": {
                    "status": "GREEN",
                    "comments": "Horn and warning lights functional."
                },
                "mirrors": {
                    "status": "GREEN",
                    "comments": "All mirrors clean and secure."
                },
                "cab_air_filter": {
                    "status": "GREEN",
                    "comments": "Cab air filter clean."
                },
                "gauges_indicators_switches": {
                    "status": "GREEN",
                    "comments": "All gauges and controls functional."
                },
                "overall_cab_interior": {
                    "status": "GREEN",
                    "comments": "Cab interior clean and organized."
                }
            }
        },
        "general_comments": "Pre-operation inspection completed. Machine is ready for field work. Monitor left hydraulic cylinder and top off differential oil.",
        "primary_status": "GREEN"
    }

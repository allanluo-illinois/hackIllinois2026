# Sample PDF Report Generator — Usage Guide

## Overview

The CAT Inspector AI now includes a **hardcoded sample inspection report** that can be downloaded as a professional PDF. This is perfect for demonstrating the PDF generation feature without requiring a live backend inspection.

## How It Works

### Backend Components

#### 1. **PDF Generator** (`app/tools/pdf_generator.py`)
- Generates professional PDF reports using `reportlab`
- Includes styling with color-coded status badges (GREEN/YELLOW/RED)
- Supports the full inspection report schema with all 4 sections:
  - GROUND (tires, hydraulics, frame, etc.)
  - ENGINE (oil, coolant, radiator, filters, etc.)
  - CAB_EXTERIOR (handholds, ROPS, windows, etc.)
  - CAB_INTERIOR (seat, controls, gauges, etc.)

#### 2. **Sample Report Data** (`get_sample_inspection_report()`)
A fully populated inspection report for a **CAT 950 (Serial: CAT-950-2024-0472)** with:
- **Inspector:** John Smith
- **Date:** Current date
- **Machine Hours:** 2,847
- **Status Distribution:**
  - 30 components at GREEN (Pass)
  - 2 components at YELLOW (Monitor)
  - 0 components at RED (Fail)
- **Overall Status:** GREEN
- **Comments:**
  - Left hydraulic cylinder: "Minor seeping detected. Monitor."
  - Differential oil: "Level slightly below minimum. Top off before next shift."
  - Radiator: "Minor debris on fins. Clean before high-temperature operations."

#### 3. **API Endpoints** (`app/main.py`)

**`POST /load-inspection`** — Generate PDF from inspection data
```python
# With data (generates PDF from provided inspection report)
POST /load-inspection
Body: {
    "machine": {"model": "CAT 950", "serial_number": "..."},
    "sections": {...},
    ...
}
Response: PDF file (application/pdf)

# Without data or empty payload (returns sample report)
POST /load-inspection
Body: {}
Response: Sample PDF file
```

**`GET /sample-report`** — Download the sample report directly
```python
GET /sample-report
Response: PDF file named "sample_inspection_report.pdf"
```

## Using in Flutter

### Current Implementation

The **Flutter UI already supports downloading reports**. When a user clicks on a report card in the Reports tab:

1. The `_ReportCard` widget builds a payload matching the inspection schema
2. Calls `state.downloadReportPdf(payload)`
3. The app sends a POST to `/load-inspection` with the payload
4. If the payload is empty or has no machine data, the backend returns the sample PDF
5. The PDF is saved to the device and opened via the share sheet

### Testing the Sample Report

#### Option 1: Click Any Report Card (Easiest)
1. Open the app and go to the **Reports** tab
2. You'll see 3 available reports at the top
3. Click **any report card** to download
4. The first time, it will use the hardcoded sample data
5. You'll see a PDF preview with:
   - Machine serial: CAT-950-2024-0472
   - Inspector: John Smith
   - Full inspection details
   - Status summary with green/yellow badges

#### Option 2: Use the Sample Endpoint (For Testing)
```bash
# Download sample directly
curl http://localhost:8000/sample-report \
  -o sample_report.pdf

# Then open in any PDF viewer
```

#### Option 3: Post Empty Data
```bash
# Send empty payload to trigger sample
curl -X POST http://localhost:8000/load-inspection \
  -H "Content-Type: application/json" \
  -d '{}' \
  -o inspection_report.pdf
```

## PDF Report Structure

When generated, the PDF includes:

### Header Section
| Field | Value |
|-------|-------|
| Serial Number | CAT-950-2024-0472 |
| Inspector | John Smith |
| Date | [Current Date] |
| Machine Hours | 2,847 |

### Component Sections

#### GROUND (16 items)
- Tires & Wheels → GREEN ✓
- Hydraulic Lines → YELLOW ⚠
- Fuel Tank → GREEN ✓
- Differential Oil → YELLOW ⚠
- _(12 more items)_

#### ENGINE (8 items)
- Engine Oil → GREEN ✓
- Coolant → GREEN ✓
- Radiator → YELLOW ⚠
- _(5 more items)_

#### CAB_EXTERIOR (6 items)
- All GREEN ✓

#### CAB_INTERIOR (7 items)
- All GREEN ✓

### Summary Section
- **Overall Status:** GREEN ✓ PASS
- **General Comments:** "Pre-operation inspection completed. Machine is ready for field work. Monitor left hydraulic cylinder and top off differential oil."

### Footer
- Generated timestamp (UTC)

## Styling & Color Coding

The PDF uses professional styling with color-coded status indicators:

```
GREEN   → ✓ PASS        (light green background)
YELLOW  → ⚠ MONITOR     (amber/gold background)
RED     → ✗ FAIL        (red background)
```

## Customizing the Sample Report

To modify the sample report data, edit `app/tools/pdf_generator.py`:

```python
def get_sample_inspection_report() -> Dict[str, Any]:
    return {
        "header": {
            "serial_number": "CAT-950-2024-0472",  # Change machine ID
            "inspector": "John Smith",  # Change inspector name
            "machine_hours": 2847,      # Change hours
            ...
        },
        "sections": {
            "GROUND": {
                "tires_wheels_stem_caps_lug_nuts": {
                    "status": "GREEN",  # GREEN, YELLOW, or RED
                    "comments": "All tires at proper pressure...",
                },
                ...
            }
        },
        "general_comments": "Your summary here...",
        "primary_status": "GREEN"  # Overall status
    }
```

## Testing Checklist

- [x] Backend PDF endpoint works (`/load-inspection`)
- [x] Sample report endpoint works (`/sample-report`)
- [x] Flutter can download PDFs via report cards
- [x] PDF displays all inspection sections with proper formatting
- [x] Color coding is applied correctly
- [x] Timestamps are included
- [x] Report can be opened in any PDF viewer

## Dependencies

Make sure these are installed:

```bash
pip install reportlab fastapi uvicorn
```

They've been added to `requirements.txt`.

## Demo Flow

Perfect for a **3-minute demo video**:

1. **Launch app** → Reports tab
2. **Show available reports** (3 hardcoded samples visible at top)
3. **Click first report card**
4. **Watch download progress** (small spinner on the card)
5. **Open PDF** (shows in share sheet)
6. **Scroll through PDF** showing:
   - Professional formatting
   - Color-coded status indicators
   - All 4 inspection sections
   - Component-level details
   - Final summary and comments

## Troubleshooting

**Issue:** "PDF generation error" when clicking report
- **Solution:** Ensure `reportlab` is installed: `pip install reportlab`

**Issue:** PDF downloads but is empty
- **Solution:** Check that `/load-inspection` endpoint is running and accessible

**Issue:** Colors not showing in PDF
- **Solution:** Ensure `reportlab` version is 3.6+: `pip install --upgrade reportlab`

**Issue:** Can't see sample report in Flutter
- **Solution:** Make sure backend is running on `http://localhost:8000` (or your configured host)

## Next Steps

After this works, you can:

1. **Connect to real inspections:** Replace sample data with data from completed inspections
2. **Add photo attachments:** Embed photos from the inspection into the PDF
3. **Custom branding:** Add company logo, colors, and styling
4. **Multi-page reports:** Split large inspections across multiple pages
5. **Batch exports:** Generate PDFs for multiple machines at once


import json
import os
import ctypes.util
from jinja2 import Template
from weasyprint import HTML

# --- MAC FIX: Manually find the library if brew is being difficult ---
gobject_path = ctypes.util.find_library('gobject-2.0')
if not gobject_path:
    # Manual fallback for Apple Silicon Homebrew
    os.environ['DYLD_LIBRARY_PATH'] = '/opt/homebrew/lib:' + os.environ.get('DYLD_LIBRARY_PATH', '')

# 1. Load your JSON Data
with open('text.json', 'r') as file:
        data = json.load(file)

# 2. Define the HTML/CSS Template
html_template = """
<!DOCTYPE html>
<html>
<head>
    <style>
        @page { size: letter; margin: 0.5in; }
        body { font-family: 'Helvetica', 'Arial', sans-serif; color: #333; line-height: 1.2; font-size: 10pt; }
        
        /* Brand Header */
        .brand-header { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 3px solid #000; padding-bottom: 10px; margin-bottom: 15px; }
        .brand-title { color: #000; font-size: 18pt; font-weight: bold; text-transform: uppercase; }
        .brand-subtitle { font-size: 12pt; margin-top: 5px; }
        .logo-placeholder { background: #FFCD00; padding: 10px; font-weight: bold; border: 1px solid #000; }

        /* Meta Data Grid */
        .meta-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 15px; }
        .meta-table { width: 100%; border-collapse: collapse; }
        .meta-table td { padding: 4px; border-bottom: 1px solid #eee; }
        .label { font-weight: bold; color: #555; width: 40%; }

        /* Summary Bar */
        .summary-bar { background: #f2f2f2; padding: 10px; border-left: 5px solid #FFCD00; margin-bottom: 20px; }
        .comments-box { font-style: italic; color: #444; margin-top: 5px; }

        /* Section Styling */
        .section-header { background: #333; color: #FFCD00; padding: 6px 10px; font-weight: bold; text-transform: uppercase; margin-top: 20px; }
        
        /* Inspection Table */
        table.inspection-data { width: 100%; border-collapse: collapse; margin-bottom: 10px; }
        table.inspection-data th { background: #eee; text-align: left; padding: 8px; border: 1px solid #ddd; font-size: 9pt; }
        table.inspection-data td { padding: 8px; border: 1px solid #ddd; vertical-align: top; }
        
        /* Status Indicators */
        .status { font-weight: bold; text-align: center; width: 80px; }
        .status-PASS { color: #2e7d32; }
        .status-NORMAL { color: #2e7d32; }
        .status-MONITOR { background: #fff3cd; color: #856404; }
        .status-FAIL { background: #f8d7da; color: #721c24; }
        
        .comp-name { font-weight: bold; }
        .comp-comment { font-size: 9pt; color: #666; margin-top: 4px; display: block; }

        .footer { margin-top: 30px; font-size: 8pt; color: #999; text-align: center; border-top: 1px solid #ddd; padding-top: 10px; }
    </style>
</head>
<body>

    <div class="brand-header">
        <div>
            <div class="brand-title">Wheel Loader: Safety & Maintenance</div>
            <div class="brand-subtitle">Executive Summary Report </div>
        </div>
        <div class="logo-placeholder"> ILLINI CAT </div>
    </div>

    <div class="meta-grid">
        <table class="meta-table">
            <tr><td class="label">Inspection No</td><td>22892110 </td></tr>
            <tr><td class="label">Serial Number</td><td>{{ machine.serial_number }} </td></tr>
            <tr><td class="label">Model</td><td>{{ machine.model }} </td></tr>
            <tr><td class="label">Asset ID</td><td>FL-3062 </td></tr>
        </table>
        <table class="meta-table">
            <tr><td class="label">Inspector</td><td>John Doe </td></tr>
            <tr><td class="label">Date Generated</td><td>{{ date_generated }} </td></tr>
            <tr><td class="label">SMU (Hours)</td><td>1027 Hours </td></tr>
            <tr><td class="label">Location</td><td>East Peoria, IL </td></tr>
        </table>
    </div>

    <div class="summary-bar">
        <strong>General Info & Comments </strong>
        <div class="comments-box">
            {{ general_comments or "Scales screen freezes during operation" }} 
        </div>
    </div>

    {% for section_name, items in sections.items() %}
    <div class="section-header">
        {{ section_name.replace('_', ' ') }} 
    </div>
    <table class="inspection-data">
        <thead>
            <tr>
                <th style="width: 45%;">Component</th>
                <th style="width: 15%;">Status</th>
                <th style="width: 40%;">Observations / Comments </th>
            </tr>
        </thead>
        <tbody>
            {% for item in items %}
            <tr>
                <td><span class="comp-name">{{ loop.index }}. {{ item.component }}</span></td>
                <td class="status status-{{ item.status }}">
                    {{ item.status }} 
                </td>
                <td>
                    <span class="comp-comment">{{ item.comments }}</span>
                </td>
            </tr>
            {% endfor %}
        </tbody>
    </table>
    {% endfor %}

</body>
</html>
"""

# 3. Render and Save
template = Template(html_template)
final_html = template.render(data)

# This writes the file locally for testing
HTML(string=final_html).write_pdf("inspection_report.pdf")
print("🚀 PDF generated successfully: inspection_report.pdf")
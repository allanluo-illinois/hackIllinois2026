#!/usr/bin/env python3
"""
Quick test script to verify PDF generation works without running the full FastAPI server.
Run this to test: python test_pdf_generation.py
"""

import sys
import os

# Add app directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.tools.pdf_generator import generate_inspection_pdf, get_sample_inspection_report


def test_pdf_generation():
    """Test that PDF generation works correctly."""
    print("🧪 Testing PDF Generation...\n")

    try:
        # Get sample report
        print("1️⃣  Loading sample inspection report...")
        report_data = get_sample_inspection_report()
        print(f"   ✓ Loaded report for machine: {report_data['header']['serial_number']}")
        print(f"   ✓ Inspector: {report_data['header']['inspector']}")
        print(f"   ✓ Sections: {list(report_data['sections'].keys())}")

        # Generate PDF
        print("\n2️⃣  Generating PDF...")
        pdf_bytes = generate_inspection_pdf(report_data)
        print(f"   ✓ PDF generated: {len(pdf_bytes)} bytes")

        # Save to file
        output_path = "sample_inspection_report.pdf"
        print(f"\n3️⃣  Saving PDF to {output_path}...")
        with open(output_path, "wb") as f:
            f.write(pdf_bytes)
        print(f"   ✓ Saved successfully!")
        print(f"   📄 You can now open {output_path} with any PDF viewer")

        # Verify file
        print("\n4️⃣  Verifying PDF...")
        file_size = os.path.getsize(output_path)
        print(f"   ✓ File size: {file_size} bytes")
        print(f"   ✓ PDF header check: {pdf_bytes[:4]}")  # Should be b'%PDF'

        if pdf_bytes[:4] == b'%PDF':
            print("\n✅ PDF Generation Test PASSED!")
            return True
        else:
            print("\n❌ PDF header is invalid!")
            return False

    except ImportError as e:
        print(f"\n❌ Missing dependency: {e}")
        print("   Install with: pip install reportlab")
        return False
    except Exception as e:
        print(f"\n❌ Error during PDF generation: {e}")
        import traceback
        traceback.print_exc()
        return False


if __name__ == "__main__":
    success = test_pdf_generation()
    sys.exit(0 if success else 1)

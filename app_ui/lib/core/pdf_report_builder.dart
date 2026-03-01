import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a professional PDF inspection report entirely on-device.
/// No backend required.
class PdfReportBuilder {
  PdfReportBuilder._();

  static Future<Uint8List> buildSampleReport() {
    return buildReport(sampleReportData);
  }

  static Future<Uint8List> buildReport(Map<String, dynamic> data) async {
    final pdf = pw.Document();

    final header = data['header'] as Map<String, dynamic>? ?? {};
    final sections = data['sections'] as Map<String, dynamic>? ?? {};
    final generalComments = data['general_comments'] as String? ?? '';
    final primaryStatus = data['primary_status'] as String? ?? 'UNKNOWN';

    // ── Styles ──
    const blue = PdfColor.fromInt(0xFF1565C0);
    const darkBlue = PdfColor.fromInt(0xFF0D47A1);
    const lightBlue = PdfColor.fromInt(0xFFE3F2FD);
    const headerBg = PdfColor.fromInt(0xFF1565C0);
    const altRow = PdfColor.fromInt(0xFFF5F5F5);
    const borderColor = PdfColor.fromInt(0xFFCCCCCC);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(36),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                'CAT 950-982 Inspection Report',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: blue,
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: blue, thickness: 2),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
          ),
        ),
        build: (context) {
          final widgets = <pw.Widget>[];

          // ── Header info table ──
          widgets.add(_infoTable(header, lightBlue));
          widgets.add(pw.SizedBox(height: 14));

          // ── Sections ──
          for (final entry in sections.entries) {
            final sectionName = entry.key
                .replaceAll('_', ' ')
                .split(' ')
                .map((w) => w.isNotEmpty
                    ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
                    : '')
                .join(' ');

            final components = entry.value as Map<String, dynamic>? ?? {};

            widgets.add(
              pw.Text(
                sectionName,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: darkBlue,
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 4));

            // Build rows
            final rows = <List<String>>[
              ['Component', 'Status', 'Comments'],
            ];

            for (final comp in components.entries) {
              final compData = comp.value as Map<String, dynamic>? ?? {};
              final name = comp.key
                  .replaceAll('_', ' ')
                  .split(' ')
                  .map((w) => w.isNotEmpty
                      ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
                      : '')
                  .join(' ');
              final status = _statusBadge(
                  compData['status'] as String? ?? '—');
              final comments = compData['comments'] as String? ?? '';
              rows.add([name, status, comments]);
            }

            widgets.add(
              pw.TableHelper.fromTextArray(
                context: context,
                headerCount: 1,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                  color: PdfColors.white,
                ),
                headerDecoration:
                    const pw.BoxDecoration(color: headerBg),
                headerAlignment: pw.Alignment.centerLeft,
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {
                  1: pw.Alignment.center,
                },
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(3),
                },
                oddRowDecoration:
                    const pw.BoxDecoration(color: altRow),
                border: pw.TableBorder.all(color: borderColor),
                cellPadding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 4),
                data: rows,
              ),
            );
            widgets.add(pw.SizedBox(height: 14));
          }

          // ── Summary ──
          widgets.add(
            pw.Text(
              'Summary',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: darkBlue,
              ),
            ),
          );
          widgets.add(pw.SizedBox(height: 4));
          widgets.add(
            pw.Table(
              border: pw.TableBorder.all(color: borderColor),
              columnWidths: {
                0: const pw.FixedColumnWidth(140),
                1: const pw.FlexColumnWidth(),
              },
              children: [
                pw.TableRow(children: [
                  _cell('Overall Status', bold: true, bg: lightBlue),
                  _cell(_statusBadge(primaryStatus)),
                ]),
                pw.TableRow(children: [
                  _cell('General Comments', bold: true, bg: lightBlue),
                  _cell(generalComments),
                ]),
              ],
            ),
          );

          return widgets;
        },
      ),
    );

    return pdf.save();
  }

  // ── Helpers ──

  static pw.Widget _infoTable(
      Map<String, dynamic> header, PdfColor labelBg) {
    final rows = <List<String>>[
      ['Serial Number', header['serial_number']?.toString() ?? 'N/A'],
      ['Inspector', header['inspector']?.toString() ?? 'N/A'],
      ['Date', header['date']?.toString() ?? 'N/A'],
      ['Machine Hours', header['machine_hours']?.toString() ?? '0'],
    ];

    return pw.Table(
      border: pw.TableBorder.all(
          color: const PdfColor.fromInt(0xFFBBDEFB)),
      columnWidths: {
        0: const pw.FixedColumnWidth(140),
        1: const pw.FlexColumnWidth(),
      },
      children: rows
          .map((r) => pw.TableRow(children: [
                _cell(r[0], bold: true, bg: labelBg),
                _cell(r[1]),
              ]))
          .toList(),
    );
  }

  static pw.Widget _cell(String text,
      {bool bold = false, PdfColor? bg}) {
    return pw.Container(
      color: bg,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static String _statusBadge(String status) {
    switch (status.toUpperCase()) {
      case 'GREEN':
      case 'PASS':
        return 'PASS';
      case 'YELLOW':
      case 'MONITOR':
        return 'MONITOR';
      case 'RED':
      case 'FAIL':
        return 'FAIL';
      default:
        return status;
    }
  }

  // ── Sample data ──

  static final Map<String, dynamic> sampleReportData = {
    'header': {
      'serial_number': 'CAT-950-2024-0472',
      'inspector': 'John Smith',
      'date': DateTime.now().toString().substring(0, 10),
      'machine_hours': 2847,
    },
    'sections': {
      'GROUND': {
        'tires_wheels_stem_caps_lug_nuts': {
          'status': 'GREEN',
          'comments': 'All tires at proper pressure, no visible wear.',
        },
        'bucket_cutting_edge_moldboard': {
          'status': 'GREEN',
          'comments': 'Cutting edge in good condition.',
        },
        'bucket_cylinders_lines_hoses': {
          'status': 'YELLOW',
          'comments': 'Minor seeping on left cylinder. Monitor.',
        },
        'loader_frame_arms': {
          'status': 'GREEN',
          'comments': 'Frame and arms intact.',
        },
        'underneath_machine': {
          'status': 'GREEN',
          'comments': 'Undercarriage clean.',
        },
        'transmission_transfer_case': {
          'status': 'GREEN',
          'comments': 'No leaks, seals intact.',
        },
        'steps_handholds': {
          'status': 'GREEN',
          'comments': 'All steps and handholds secure.',
        },
        'fuel_tank': {
          'status': 'GREEN',
          'comments': 'Tank secure, no leaks.',
        },
        'differential_final_drive_oil': {
          'status': 'YELLOW',
          'comments': 'Level slightly below minimum. Top off.',
        },
        'air_tank': {
          'status': 'GREEN',
          'comments': 'Tank and lines OK.',
        },
        'axles_brakes_seals': {
          'status': 'GREEN',
          'comments': 'Seals intact, brakes responsive.',
        },
        'hydraulic_tank': {
          'status': 'GREEN',
          'comments': 'Fluid level at proper mark.',
        },
        'transmission_oil': {
          'status': 'GREEN',
          'comments': 'Oil level normal.',
        },
        'lights_front_rear': {
          'status': 'GREEN',
          'comments': 'All lights functional.',
        },
        'battery_compartment': {
          'status': 'GREEN',
          'comments': 'Terminals clean, connections tight.',
        },
        'def_tank': {
          'status': 'GREEN',
          'comments': 'DEF level adequate.',
        },
        'overall_machine': {
          'status': 'GREEN',
          'comments': 'Overall condition good.',
        },
      },
      'ENGINE': {
        'engine_oil': {
          'status': 'GREEN',
          'comments': 'Oil level normal, no leaks.',
        },
        'engine_coolant': {
          'status': 'GREEN',
          'comments': 'Coolant at proper mark.',
        },
        'radiator': {
          'status': 'YELLOW',
          'comments': 'Minor debris on fins. Clean before use.',
        },
        'all_hoses_and_lines': {
          'status': 'GREEN',
          'comments': 'All hoses intact.',
        },
        'fuel_filters_water_separator': {
          'status': 'GREEN',
          'comments': 'Filters clean.',
        },
        'all_belts': {
          'status': 'GREEN',
          'comments': 'Normal wear, tensioned correctly.',
        },
        'air_filter': {
          'status': 'GREEN',
          'comments': 'Air filter clean.',
        },
        'overall_engine_compartment': {
          'status': 'GREEN',
          'comments': 'Engine compartment clean.',
        },
      },
      'CAB_EXTERIOR': {
        'handholds': {
          'status': 'GREEN',
          'comments': 'All handholds secure.',
        },
        'rops': {
          'status': 'GREEN',
          'comments': 'ROPS structure intact.',
        },
        'fire_extinguisher': {
          'status': 'GREEN',
          'comments': 'Present and sealed.',
        },
        'windshield_windows': {
          'status': 'GREEN',
          'comments': 'All windows intact.',
        },
        'wipers_washers': {
          'status': 'GREEN',
          'comments': 'Wipers functional, fluid full.',
        },
        'doors': {
          'status': 'GREEN',
          'comments': 'Doors open and close smoothly.',
        },
      },
      'CAB_INTERIOR': {
        'seat': {
          'status': 'GREEN',
          'comments': 'Seat in good condition.',
        },
        'seat_belt_mounting': {
          'status': 'GREEN',
          'comments': 'Seat belt functional.',
        },
        'horn_alarm_lights': {
          'status': 'GREEN',
          'comments': 'Horn and warning lights functional.',
        },
        'mirrors': {
          'status': 'GREEN',
          'comments': 'All mirrors clean and secure.',
        },
        'cab_air_filter': {
          'status': 'GREEN',
          'comments': 'Cab air filter clean.',
        },
        'gauges_indicators_switches': {
          'status': 'GREEN',
          'comments': 'All gauges and controls functional.',
        },
        'overall_cab_interior': {
          'status': 'GREEN',
          'comments': 'Cab interior clean.',
        },
      },
    },
    'general_comments':
        'Pre-operation inspection completed. Machine is ready for field work. '
        'Monitor left hydraulic cylinder and top off differential oil.',
    'primary_status': 'GREEN',
  };
}

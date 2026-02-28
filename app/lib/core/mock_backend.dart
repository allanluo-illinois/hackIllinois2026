import 'dart:math';
import 'backend_port.dart';
import 'models.dart';

class MockBackend implements BackendPort {
  final _rng = Random();
  int _turnCount = 0;

  // ── Inspect ────────────────────────────────────────────────────────────

  static const _agentLines = [
    'Check the bucket cutting edge for cracks or excessive wear.',
    'Inspect the tilt cylinders — look for hydraulic leaks around seals.',
    'Move to the left front tire. Check tread depth and sidewall condition.',
    'Examine lug nuts on the left front wheel for proper torque.',
    'Inspect the left final drive for oil leaks near the duo cone seal.',
    'Walk to the service panel. Check coolant and engine oil levels.',
    'Inspect hydraulic tank level and look for hose wear near the fittings.',
    'Check the battery case — corrosion on terminals?',
    'Rear of machine: inspect the radiator grille for debris blockage.',
    'Check rear lights and ROPS structure for any damage.',
    'Enter the cab. Verify seatbelt, horn, and fire extinguisher.',
    'Check the control panel — any warning lights active?',
  ];

  static const _zones = [
    'Front / Bucket Area',
    'Front Tire Left',
    'Left Center / Service Panel',
    'Rear of Machine',
    'Right Center',
    'Front Tire Right',
    'Interior / Cab',
  ];

  static const _steps = [
    'Visual inspection',
    'Check for leaks',
    'Check levels',
    'Verify fasteners',
    'Functional check',
  ];

  @override
  Future<InspectTurn> sendInspectMessage({
    required String sessionId,
    required String text,
    String? zoneId,
    String? inspectionPointId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));

    final idx = _turnCount % _agentLines.length;
    final zoneIdx = _turnCount ~/ 2 % _zones.length;
    _turnCount++;

    final addFinding = _rng.nextDouble() > 0.5;
    final findings = addFinding
        ? [
            Finding(
              id: 'f_${DateTime.now().millisecondsSinceEpoch}',
              severity: _rng.nextDouble() > 0.6
                  ? FindingSeverity.review
                  : FindingSeverity.ok,
              title: inspectionPointId ?? 'Component check',
              detail: text.isEmpty ? 'No issues noted.' : text,
              timestamp: DateTime.now(),
            )
          ]
        : <Finding>[];

    final actions = RequestedAction.values;
    final action = _rng.nextDouble() > 0.7
        ? actions[_rng.nextInt(actions.length)]
        : RequestedAction.none;

    return InspectTurn(
      agentText: _agentLines[idx],
      suggestedZone: _zones[zoneIdx],
      suggestedInspectionPoint: _steps[_rng.nextInt(_steps.length)],
      newFindings: findings,
      requestedAction: action,
    );
  }

  // ── Media ──────────────────────────────────────────────────────────────

  @override
  Future<MediaProcessResult> uploadMedia({
    required String sessionId,
    required MediaKind kind,
    required String filePath,
    String? zoneId,
    String? inspectionPointId,
  }) async {
    // Simulate upload → processing → complete
    await Future.delayed(const Duration(seconds: 1)); // uploading
    await Future.delayed(const Duration(seconds: 1)); // processing

    final hasFinding = _rng.nextDouble() > 0.4;
    final findings = hasFinding
        ? [
            Finding(
              id: 'f_media_${DateTime.now().millisecondsSinceEpoch}',
              severity: _rng.nextDouble() > 0.5
                  ? FindingSeverity.review
                  : FindingSeverity.critical,
              title: '${kind.name.toUpperCase()} analysis',
              detail: kind == MediaKind.photo
                  ? 'AI detected surface wear on component.'
                  : 'Video shows intermittent hydraulic leak.',
              timestamp: DateTime.now(),
            )
          ]
        : <Finding>[];

    return MediaProcessResult(
      status: MediaStatus.complete,
      addedFindings: findings,
      changeScore: hasFinding ? -0.05 : 0.01,
      notes: hasFinding ? 'Issue flagged for review.' : 'No issues detected.',
    );
  }

  // ── Reports ────────────────────────────────────────────────────────────

  @override
  Future<ReportsQueryResult> queryReports({
    required String machineId,
    required String query,
  }) async {
    await Future.delayed(const Duration(milliseconds: 900));

    final q = query.toLowerCase();
    final now = DateTime.now();

    final results = [
      ReportSummary(
        reportId: 'RPT-2024-0472-A',
        date: now.subtract(const Duration(days: 3)),
        machineId: machineId,
        summaryLine: '2 review items: left hose wear, low hydraulic fluid.',
      ),
      ReportSummary(
        reportId: 'RPT-2024-0472-B',
        date: now.subtract(const Duration(days: 18)),
        machineId: machineId,
        summaryLine: 'All clear. Routine pre-op passed.',
      ),
      ReportSummary(
        reportId: 'RPT-2024-0472-C',
        date: now.subtract(const Duration(days: 35)),
        machineId: machineId,
        summaryLine: 'Critical: duo cone seal leak on rear-right axle.',
      ),
    ];

    String assistantText;
    if (q.contains('hydraulic') || q.contains('hose')) {
      assistantText =
          'Found 2 reports with hydraulic-related issues for $machineId. '
          'The most recent (3 days ago) flagged hose wear near the left tilt cylinder. '
          'Recommend inspection before next shift.';
    } else if (q.contains('critical') || q.contains('leak')) {
      assistantText =
          'One critical finding on record for $machineId: a duo cone seal leak '
          'detected 35 days ago on the rear-right axle. Verify it was serviced.';
    } else if (q.contains('last 30') || q.contains('recent')) {
      assistantText =
          'Found 2 inspections for $machineId in the last 30 days. '
          'Overall health trend is stable. One review item pending on hydraulic hose.';
    } else {
      assistantText =
          'Showing the 3 most recent inspection reports for $machineId. '
          'Use keywords like "hydraulic", "leak", or "critical" to filter results.';
    }

    return ReportsQueryResult(results: results, assistantText: assistantText);
  }

  // ── Edit ───────────────────────────────────────────────────────────────

  @override
  Future<ReportUpdateResult> editReport({
    required String reportId,
    required String instruction,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    return ReportUpdateResult(
      success: true,
      assistantText:
          'Report $reportId updated: "$instruction". Changes saved successfully.',
    );
  }
}

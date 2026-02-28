// ── Enums ──────────────────────────────────────────────────────────────────

enum FindingSeverity { ok, review, critical }

enum MediaKind { photo, video, audio }

enum MediaStatus { streaming, queued, uploading, processing, complete, failed }

enum RequestedAction { none, capturePhoto, captureVideo, confirmOkReviewCritical }

/// Identifies which agent in the multi-agent system produced a response.
enum AgentRole { orchestrator, vision, safety, reports }

// ── Inspection structure ──────────────────────────────────────────────────

/// A single component to check within a zone.
class InspectionPoint {
  final String id;
  final String component;
  final String? side;

  const InspectionPoint({
    required this.id,
    required this.component,
    this.side,
  });

  /// Human-readable label: "bucket_cutting_edge" → "Bucket Cutting Edge".
  String get displayName {
    final base = component.replaceAll('_', ' ');
    final words = base.split(' ').map((w) =>
        w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}');
    final label = words.join(' ');
    return side != null ? '$label (${side!})' : label;
  }

  factory InspectionPoint.fromJson(Map<String, dynamic> json) =>
      InspectionPoint(
        id: json['id'] as String,
        component: json['component'] as String,
        side: json['side'] as String?,
      );
}

/// A zone on the machine containing multiple inspection points.
class InspectionZone {
  final String zoneId;
  final List<InspectionPoint> points;

  const InspectionZone({required this.zoneId, required this.points});

  String get displayName {
    final base = zoneId.replaceAll('_', ' ');
    final words = base.split(' ').map((w) =>
        w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}');
    return words.join(' ');
  }

  factory InspectionZone.fromJson(Map<String, dynamic> json) =>
      InspectionZone(
        zoneId: json['zone_id'] as String,
        points: (json['inspection_points'] as List)
            .map((p) => InspectionPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

/// Result of checking one inspection point.
class CheckResult {
  final String pointId;
  final FindingSeverity severity;
  final String? note;
  final List<String> photoIds;
  final DateTime completedAt;

  const CheckResult({
    required this.pointId,
    required this.severity,
    this.note,
    this.photoIds = const [],
    required this.completedAt,
  });

  Map<String, dynamic> toJson() => {
        'pointId': pointId,
        'severity': severity.name,
        if (note != null) 'note': note,
        'photoIds': photoIds,
        'completedAt': completedAt.toIso8601String(),
      };
}

// ── Core data classes ──────────────────────────────────────────────────────

class Finding {
  final String id;
  final FindingSeverity severity;
  final String title;
  final String detail;
  final DateTime timestamp;

  const Finding({
    required this.id,
    required this.severity,
    required this.title,
    required this.detail,
    required this.timestamp,
  });
}

class MediaItem {
  final String id;
  final MediaKind kind;
  MediaStatus status;
  final String label;
  final DateTime timestamp;
  final String localPath;

  MediaItem({
    required this.id,
    required this.kind,
    required this.status,
    required this.label,
    required this.timestamp,
    required this.localPath,
  });
}

class LiveReport {
  final String sessionId;
  final String machineId;
  final DateTime startedAt;
  String currentZone;
  String currentStep;
  final List<Finding> findings;
  final List<MediaItem> media;
  final Map<String, CheckResult> checkedPoints;

  LiveReport({
    required this.sessionId,
    required this.machineId,
    required this.startedAt,
    this.currentZone = '',
    this.currentStep = '',
    List<Finding>? findings,
    List<MediaItem>? media,
    Map<String, CheckResult>? checkedPoints,
  })  : findings = findings ?? [],
        media = media ?? [],
        checkedPoints = checkedPoints ?? {};

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'machineId': machineId,
        'startedAt': startedAt.toIso8601String(),
        'currentZone': currentZone,
        'currentStep': currentStep,
        'findings': findings
            .map((f) => {
                  'id': f.id,
                  'severity': f.severity.name,
                  'title': f.title,
                  'detail': f.detail,
                })
            .toList(),
        'media': media
            .map((m) => {
                  'id': m.id,
                  'kind': m.kind.name,
                  'status': m.status.name,
                  'label': m.label,
                })
            .toList(),
        'checkedPoints': checkedPoints.map((k, v) => MapEntry(k, v.toJson())),
      };
}

// ── Session creation result ────────────────────────────────────────────────

class SessionStartResult {
  final String sessionId;
  final String initialGuidance;
  final String startingZone;
  final String startingStep;

  const SessionStartResult({
    required this.sessionId,
    required this.initialGuidance,
    required this.startingZone,
    required this.startingStep,
  });
}

// ── Backend response types ─────────────────────────────────────────────────

class InspectTurn {
  final AgentRole source;
  final String agentText;
  final String? suggestedZone;
  final String? suggestedInspectionPoint;
  final List<Finding> newFindings;
  final RequestedAction requestedAction;

  const InspectTurn({
    this.source = AgentRole.orchestrator,
    required this.agentText,
    this.suggestedZone,
    this.suggestedInspectionPoint,
    this.newFindings = const [],
    this.requestedAction = RequestedAction.none,
  });
}

/// Real-time message pushed from backend (video stream observations, etc.)
class AgentMessage {
  final AgentRole source;
  final String text;
  final List<Finding> findings;
  final String? suggestedZone;
  final RequestedAction requestedAction;
  final DateTime timestamp;

  const AgentMessage({
    required this.source,
    required this.text,
    this.findings = const [],
    this.suggestedZone,
    this.requestedAction = RequestedAction.none,
    required this.timestamp,
  });
}

class MediaProcessResult {
  final MediaStatus status;
  final List<Finding> addedFindings;
  final double? changeScore;
  final String notes;

  const MediaProcessResult({
    required this.status,
    this.addedFindings = const [],
    this.changeScore,
    this.notes = '',
  });
}

class ReportSummary {
  final String reportId;
  final DateTime date;
  final String machineId;
  final String summaryLine;

  const ReportSummary({
    required this.reportId,
    required this.date,
    required this.machineId,
    required this.summaryLine,
  });
}

class ReportsQueryResult {
  final List<ReportSummary> results;
  final String assistantText;

  const ReportsQueryResult({
    required this.results,
    required this.assistantText,
  });
}

class ReportUpdateResult {
  final bool success;
  final String assistantText;

  const ReportUpdateResult({required this.success, required this.assistantText});
}

// ── Backend events (audio pipeline) ────────────────────────────────────────

sealed class BackendEvent {
  const BackendEvent();
}

class AsrPartial extends BackendEvent {
  final String text;
  const AsrPartial(this.text);
}

class AsrFinal extends BackendEvent {
  final String text;
  const AsrFinal(this.text);
}

class AgentReply extends BackendEvent {
  final String text;
  const AgentReply(this.text);
}

class ReportPatch extends BackendEvent {
  final Map<String, dynamic> finding;
  const ReportPatch(this.finding);
}

class AgentPartial extends BackendEvent {
  final String text;
  const AgentPartial(this.text);
}

class AudioLevel extends BackendEvent {
  /// RMS level in decibels (0 dB = full scale, -160 dB = silence).
  final double rmsDb;
  const AudioLevel(this.rmsDb);
}

// ── Chat ───────────────────────────────────────────────────────────────────

enum ChatRole { user, assistant }

class ChatMessage {
  final String id;
  final ChatRole role;
  final String text;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
  });
}

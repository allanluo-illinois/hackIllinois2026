// ── Enums ──────────────────────────────────────────────────────────────────

enum FindingSeverity { ok, review, critical }

enum MediaKind { photo, video, audio }

enum MediaStatus { queued, uploading, processing, complete, failed }

enum RequestedAction { none, capturePhoto, captureVideo, confirmOkReviewCritical }

/// Identifies which agent in the multi-agent system produced a response.
enum AgentRole { orchestrator, vision, safety, reports }

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

  factory Finding.fromJson(Map<String, dynamic> json) => Finding(
        id: json['id'] as String,
        severity: FindingSeverity.values.byName(json['severity'] as String),
        title: json['title'] as String,
        detail: json['detail'] as String,
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'severity': severity.name,
        'title': title,
        'detail': detail,
        'timestamp': timestamp.toIso8601String(),
      };
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

  LiveReport({
    required this.sessionId,
    required this.machineId,
    required this.startedAt,
    this.currentZone = '',
    this.currentStep = '',
    List<Finding>? findings,
    List<MediaItem>? media,
  })  : findings = findings ?? [],
        media = media ?? [];

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

  factory SessionStartResult.fromJson(Map<String, dynamic> json) =>
      SessionStartResult(
        sessionId: json['sessionId'] as String,
        initialGuidance: json['initialGuidance'] as String? ?? '',
        startingZone: json['startingZone'] as String? ?? '',
        startingStep: json['startingStep'] as String? ?? '',
      );
}

// ── Backend response types ─────────────────────────────────────────────────

class InspectTurn {
  final AgentRole source;
  final String agentText;

  /// STT transcript of the uploaded audio, if audio was sent.
  final String? transcript;

  final String? suggestedZone;
  final String? suggestedInspectionPoint;
  final List<Finding> newFindings;
  final RequestedAction requestedAction;

  const InspectTurn({
    this.source = AgentRole.orchestrator,
    required this.agentText,
    this.transcript,
    this.suggestedZone,
    this.suggestedInspectionPoint,
    this.newFindings = const [],
    this.requestedAction = RequestedAction.none,
  });

  factory InspectTurn.fromJson(Map<String, dynamic> json) => InspectTurn(
        source: AgentRole.values.byName(json['source'] as String? ?? 'orchestrator'),
        agentText: json['agentText'] as String? ?? '',
        transcript: json['transcript'] as String?,
        suggestedZone: json['suggestedZone'] as String?,
        suggestedInspectionPoint: json['suggestedInspectionPoint'] as String?,
        newFindings: (json['findings'] as List<dynamic>?)
                ?.map((f) => Finding.fromJson(f as Map<String, dynamic>))
                .toList() ??
            const [],
        requestedAction: RequestedAction.values.byName(
            json['requestedAction'] as String? ?? 'none'),
      );
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

  factory MediaProcessResult.fromJson(Map<String, dynamic> json) =>
      MediaProcessResult(
        status: MediaStatus.values.byName(json['status'] as String? ?? 'complete'),
        addedFindings: (json['findings'] as List<dynamic>?)
                ?.map((f) => Finding.fromJson(f as Map<String, dynamic>))
                .toList() ??
            const [],
        changeScore: (json['changeScore'] as num?)?.toDouble(),
        notes: json['notes'] as String? ?? '',
      );
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

  factory ReportSummary.fromJson(Map<String, dynamic> json) => ReportSummary(
        reportId: json['reportId'] as String,
        date: DateTime.parse(json['date'] as String),
        machineId: json['machineId'] as String,
        summaryLine: json['summaryLine'] as String? ?? '',
      );
}

class ReportsQueryResult {
  final List<ReportSummary> results;
  final String assistantText;

  const ReportsQueryResult({
    required this.results,
    required this.assistantText,
  });

  factory ReportsQueryResult.fromJson(Map<String, dynamic> json) =>
      ReportsQueryResult(
        results: (json['results'] as List<dynamic>?)
                ?.map((r) => ReportSummary.fromJson(r as Map<String, dynamic>))
                .toList() ??
            const [],
        assistantText: json['assistantText'] as String? ?? '',
      );
}

class ReportUpdateResult {
  final bool success;
  final String assistantText;

  const ReportUpdateResult({required this.success, required this.assistantText});

  factory ReportUpdateResult.fromJson(Map<String, dynamic> json) =>
      ReportUpdateResult(
        success: json['success'] as bool? ?? false,
        assistantText: json['assistantText'] as String? ?? '',
      );
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

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'text': text,
      };
}

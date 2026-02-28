// ── Enums ──────────────────────────────────────────────────────────────────

enum FindingSeverity { ok, review, critical }

enum MediaKind { photo, video, audio }

enum MediaStatus { queued, uploading, processing, complete, failed }

enum RequestedAction { none, capturePhoto, captureVideo, confirmOkReviewCritical }

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

// ── Backend response types ─────────────────────────────────────────────────

class InspectTurn {
  final String agentText;
  final String? suggestedZone;
  final String? suggestedInspectionPoint;
  final List<Finding> newFindings;
  final RequestedAction requestedAction;

  const InspectTurn({
    required this.agentText,
    this.suggestedZone,
    this.suggestedInspectionPoint,
    this.newFindings = const [],
    this.requestedAction = RequestedAction.none,
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

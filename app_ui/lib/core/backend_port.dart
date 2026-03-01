import 'dart:typed_data';

import 'models.dart';

/// Swap this for HttpBackend, etc. without touching UI/state.
abstract class BackendPort {
  // ── Session lifecycle ───────────────────────────────────────────────────

  Future<SessionStartResult> createSession(String machineId);
  Future<void> endSession(String sessionId);

  // ── Multi-modal inspect turn ────────────────────────────────────────────

  /// Send a turn to the inspection agent. Accepts any combination of
  /// text and file paths for audio, image, or video. The backend processes
  /// each modality (STT, vision analysis, etc.) and returns a single response.
  Future<InspectTurn> sendInspectTurn({
    required String sessionId,
    required String zoneId,
    String? text,
    String? audioFilePath,
    String? imageFilePath,
    String? videoFilePath,
  });

  // ── Media upload ────────────────────────────────────────────────────────

  /// Upload a media file (photo/video) for processing.
  Future<MediaProcessResult> uploadMedia({
    required String sessionId,
    required MediaKind kind,
    required String filePath,
    required String mimeType,
    String? zoneId,
  });

  // ── Reports ─────────────────────────────────────────────────────────────

  /// Query an AI agent about past inspection reports.
  /// [history] provides prior conversation turns so the agent has context.
  Future<ReportsQueryResult> queryReports({
    required String machineId,
    required String query,
    List<ChatMessage> history = const [],
  });

  Future<ReportUpdateResult> editReport({
    required String reportId,
    required String instruction,
  });

  /// Generate a PDF for an inspection. [payload] is the full inspection data
  /// matching the backend's /load-inspection schema (machine, sections, etc.).
  Future<Uint8List> downloadReportPdf({required Map<String, dynamic> payload});

  // ── Cleanup ─────────────────────────────────────────────────────────────

  void dispose();
}

import 'dart:typed_data';

import 'models.dart';

/// Swap this for HttpBackend, WebSocketBackend, etc. without touching UI/state.
abstract class BackendPort {
  // ── Session lifecycle ───────────────────────────────────────────────────

  /// Create an inspection session on the backend.
  Future<SessionStartResult> createSession(String machineId);

  /// Notify the backend that the session has ended.
  Future<void> endSession(String sessionId);

  // ── Multi-modal inspect turn ────────────────────────────────────────────

  /// Send a turn to the inspection agent. Accepts any combination of
  /// text, raw audio bytes, or image bytes — the backend decides how to
  /// process each modality (STT, vision analysis, etc.).
  Future<InspectTurn> sendInspectTurn({
    required String sessionId,
    required String zoneId,
    String? text,
    Uint8List? audioBytes,
    Uint8List? imageBytes,
    String? mimeType,
  });

  // ── Live video stream ───────────────────────────────────────────────────

  /// Open a live video observation stream. The backend pushes
  /// [AgentMessage]s as its vision agent processes frames.
  Stream<AgentMessage> connectVideoStream({
    required String sessionId,
    required String zoneId,
  });

  /// Disconnect the live video stream.
  Future<void> disconnectVideoStream(String sessionId);

  // ── Media upload ────────────────────────────────────────────────────────

  /// Upload prepared media bytes to the backend.
  ///
  /// Images should be JPG-encoded via [MediaService.toJpgBytes] before
  /// calling this. Videos are read as raw bytes via [MediaService.readFileBytes].
  Future<MediaProcessResult> uploadMedia({
    required String sessionId,
    required MediaKind kind,
    required Uint8List bytes,
    required String mimeType,
    String? zoneId,
  });

  // ── Reports ─────────────────────────────────────────────────────────────

  Future<ReportsQueryResult> queryReports({
    required String machineId,
    required String query,
  });

  Future<ReportUpdateResult> editReport({
    required String reportId,
    required String instruction,
  });

  // ── Cleanup ─────────────────────────────────────────────────────────────

  void dispose();
}

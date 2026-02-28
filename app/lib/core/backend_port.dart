import 'models.dart';

/// Swap this for HttpBackend, WebSocketBackend, etc. without touching UI/state.
abstract class BackendPort {
  Future<InspectTurn> sendInspectMessage({
    required String sessionId,
    required String text,
    String? zoneId,
    String? inspectionPointId,
  });

  Future<MediaProcessResult> uploadMedia({
    required String sessionId,
    required MediaKind kind,
    required String filePath,
    String? zoneId,
    String? inspectionPointId,
  });

  Future<ReportsQueryResult> queryReports({
    required String machineId,
    required String query,
  });

  Future<ReportUpdateResult> editReport({
    required String reportId,
    required String instruction,
  });
}

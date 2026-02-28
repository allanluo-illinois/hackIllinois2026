import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'audio_capture.dart';
import 'backend_port.dart';
import 'http_backend.dart';
import 'media_service.dart';
import 'models.dart';
import 'tts_service.dart';

class AppState extends ChangeNotifier {
  BackendPort backend;
  final AudioRecorder recorder;
  final MediaService mediaService;
  final TtsService tts;

  String _backendUrl;
  String get backendUrl => _backendUrl;

  /// User-visible error from the last backend call, or null if none.
  String? lastError;

  AppState({
    required this.backend,
    required this.recorder,
    required this.mediaService,
    required this.tts,
    String backendUrl = 'http://localhost:8080',
  }) : _backendUrl = backendUrl {
    tts.onStateChanged = () => notifyListeners();
  }

  void clearError() {
    if (lastError == null) return;
    lastError = null;
    notifyListeners();
  }

  /// Swap the backend to point at a new URL.
  void updateBackendUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed == _backendUrl) return;
    backend.dispose();
    _backendUrl = trimmed;
    backend = HttpBackend(baseUrl: trimmed);
    notifyListeners();
  }

  // ── Inspection structure (loaded from components.json) ────────────────

  List<InspectionZone> zones = [];
  bool _zonesLoaded = false;

  Future<void> _ensureZonesLoaded() async {
    if (_zonesLoaded) return;
    final raw = await rootBundle.loadString('assets/components.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    zones = (json['zones'] as List)
        .map((z) => InspectionZone.fromJson(z as Map<String, dynamic>))
        .toList();
    _zonesLoaded = true;
  }

  /// The zone currently being inspected.
  InspectionZone? get activeZone {
    final zoneId = liveReport?.currentZone;
    if (zoneId == null || zones.isEmpty) return null;
    return zones.cast<InspectionZone?>().firstWhere(
          (z) => z!.zoneId == zoneId || z.displayName == zoneId,
          orElse: () => null,
        );
  }

  /// The inspection point the operator is currently on.
  int currentPointIndex = 0;

  InspectionPoint? get currentPoint {
    final zone = activeZone;
    if (zone == null || currentPointIndex >= zone.points.length) return null;
    return zone.points[currentPointIndex];
  }

  /// Photos taken for the current inspection point (before marking complete).
  List<String> _pendingPhotoIds = [];

  /// Mark the current inspection point as checked with a severity.
  void markPointChecked(FindingSeverity severity, {String? note}) {
    final report = liveReport;
    final point = currentPoint;
    if (report == null || point == null) return;

    final result = CheckResult(
      pointId: point.id,
      severity: severity,
      note: note,
      photoIds: List.unmodifiable(_pendingPhotoIds),
      completedAt: DateTime.now(),
    );
    report.checkedPoints[point.id] = result;

    report.findings.add(Finding(
      id: 'check_${point.id}',
      severity: severity,
      title: point.displayName,
      detail: note ?? severity.name.toUpperCase(),
      timestamp: DateTime.now(),
    ));

    _pendingPhotoIds = [];
    _advanceToNextPoint();
    notifyListeners();
  }

  void _advanceToNextPoint() {
    final zone = activeZone;
    final report = liveReport;
    if (zone == null || report == null) return;

    for (var i = currentPointIndex + 1; i < zone.points.length; i++) {
      if (!report.checkedPoints.containsKey(zone.points[i].id)) {
        currentPointIndex = i;
        report.currentStep = zone.points[i].displayName;
        return;
      }
    }
    currentPointIndex = zone.points.length;
    report.currentStep = 'Zone complete';
  }

  /// Move to a specific zone by ID.
  void setZone(String zoneId) {
    final report = liveReport;
    if (report == null) return;
    report.currentZone = zoneId;
    currentPointIndex = 0;
    _pendingPhotoIds = [];

    final zone = activeZone;
    if (zone != null) {
      for (var i = 0; i < zone.points.length; i++) {
        if (!report.checkedPoints.containsKey(zone.points[i].id)) {
          currentPointIndex = i;
          report.currentStep = zone.points[i].displayName;
          notifyListeners();
          return;
        }
      }
      currentPointIndex = zone.points.length;
      report.currentStep = 'Zone complete';
    }
    notifyListeners();
  }

  // ── Inspect state ──────────────────────────────────────────────────────

  LiveReport? liveReport;
  bool inspectBusy = false;
  String latestAgentText = '';
  AgentRole latestAgentRole = AgentRole.orchestrator;
  RequestedAction pendingAction = RequestedAction.none;

  Future<void> startSession(String machineId) async {
    lastError = null;
    inspectBusy = true;
    notifyListeners();

    try {
      await _ensureZonesLoaded();
      final result = await backend.createSession(machineId);

      final startZone =
          zones.isNotEmpty ? zones.first.zoneId : result.startingZone;

      liveReport = LiveReport(
        sessionId: result.sessionId,
        machineId: machineId,
        startedAt: DateTime.now(),
        currentZone: startZone,
        currentStep: result.startingStep,
      );

      currentPointIndex = 0;
      _pendingPhotoIds = [];
      final firstPoint = currentPoint;
      if (firstPoint != null) {
        liveReport!.currentStep = firstPoint.displayName;
      }

      latestAgentText = result.initialGuidance;
      latestAgentRole = AgentRole.orchestrator;
      pendingAction = RequestedAction.none;

      tts.speak(latestAgentText);
    } catch (e) {
      debugPrint('Session start error: $e');
      lastError = 'Could not start session. Check server URL and try again.';
    }

    inspectBusy = false;
    notifyListeners();
  }

  void dismissPendingAction() {
    pendingAction = RequestedAction.none;
    notifyListeners();
  }

  void _applyTurn(InspectTurn turn, LiveReport report) {
    latestAgentText = turn.agentText;
    latestAgentRole = turn.source;
    pendingAction = turn.requestedAction;
    if (turn.suggestedZone != null) report.currentZone = turn.suggestedZone!;
    if (turn.suggestedInspectionPoint != null) {
      report.currentStep = turn.suggestedInspectionPoint!;
    }
    report.findings.addAll(turn.newFindings);
    tts.speak(latestAgentText);
  }

  // ── Audio recording (record → upload → response) ─────────────────────

  bool isAudioRecording = false;

  Future<void> toggleAudio() async {
    if (isAudioRecording) {
      // Stop recording → upload → get response.
      debugPrint('🎙️ Audio STOP — finalising recording');
      isAudioRecording = false;
      notifyListeners();

      final filePath = await recorder.stop();
      if (filePath == null) {
        debugPrint('🎙️ No audio file produced');
        return;
      }

      debugPrint('🎙️ Audio file: $filePath');
      final report = liveReport;
      if (report == null) return;

      inspectBusy = true;
      notifyListeners();

      try {
        final turn = await backend.sendInspectTurn(
          sessionId: report.sessionId,
          zoneId: report.currentZone,
          audioFilePath: filePath,
        );

        if (turn.transcript != null) {
          debugPrint('🗣️ Transcript: ${turn.transcript}');
        }

        _applyTurn(turn, report);
      } catch (e) {
        debugPrint('🎙️ Audio upload error: $e');
        lastError = 'Failed to send audio. Check connection and try again.';
      }

      inspectBusy = false;
      notifyListeners();
    } else {
      // Start recording.
      debugPrint('🎙️ Audio START');
      try {
        await recorder.start();
        isAudioRecording = true;
        notifyListeners();
      } catch (e) {
        debugPrint('🎙️ Recording start error: $e');
        lastError = 'Could not start microphone.';
        notifyListeners();
      }
    }
  }

  // ── Camera preview toggle ─────────────────────────────────────────────

  bool isVideoActive = false;

  void toggleVideo() {
    isVideoActive = !isVideoActive;
    debugPrint('📹 Camera preview ${isVideoActive ? "ON" : "OFF"}');
    notifyListeners();
  }

  // ── Media capture & upload ────────────────────────────────────────────

  Future<void> capturePhoto() async {
    final path = await mediaService.takePhoto();
    if (path == null) return;
    await _uploadMediaFile(MediaKind.photo, path, 'image/jpeg');
  }

  Future<void> captureVideo() async {
    final path = await mediaService.recordVideo();
    if (path == null) return;
    await _uploadMediaFile(MediaKind.video, path, 'video/mp4');
  }

  Future<void> pickImageFromGallery() async {
    final path = await mediaService.pickImageFromGallery();
    if (path == null) return;
    await _uploadMediaFile(MediaKind.photo, path, 'image/jpeg');
  }

  Future<void> pickVideoFromGallery() async {
    final path = await mediaService.pickVideoFromGallery();
    if (path == null) return;
    await _uploadMediaFile(MediaKind.video, path, 'video/mp4');
  }

  Future<void> _uploadMediaFile(
      MediaKind kind, String filePath, String mimeType) async {
    final report = liveReport;
    if (report == null) return;

    final id = 'media_${DateTime.now().millisecondsSinceEpoch}';
    final point = currentPoint;
    final pointLabel = point?.displayName ?? report.currentZone;
    final item = MediaItem(
      id: id,
      kind: kind,
      status: MediaStatus.queued,
      label: '${kind.name} – $pointLabel',
      timestamp: DateTime.now(),
      localPath: filePath,
    );
    report.media.add(item);

    if (kind == MediaKind.photo) {
      _pendingPhotoIds.add(id);
    }

    item.status = MediaStatus.uploading;
    notifyListeners();

    debugPrint('📸 Uploading ${kind.name}: $filePath');

    try {
      final result = await backend.uploadMedia(
        sessionId: report.sessionId,
        kind: kind,
        filePath: filePath,
        mimeType: mimeType,
        zoneId: report.currentZone,
      );

      item.status = result.status;
      report.findings.addAll(result.addedFindings);
    } catch (e) {
      debugPrint('📸 Upload error: $e');
      item.status = MediaStatus.failed;
      lastError = 'Media upload failed. Check connection.';
    }

    notifyListeners();
  }

  void addManualFinding(FindingSeverity severity, String note) {
    final report = liveReport;
    if (report == null) return;
    report.findings.add(Finding(
      id: 'f_manual_${DateTime.now().millisecondsSinceEpoch}',
      severity: severity,
      title: 'Manual note',
      detail: note,
      timestamp: DateTime.now(),
    ));
    notifyListeners();
  }

  void endSession() {
    tts.stop();
    final sessionId = liveReport?.sessionId;
    liveReport = null;

    isVideoActive = false;

    if (isAudioRecording) {
      recorder.stop();
    }
    isAudioRecording = false;

    latestAgentText = '';
    latestAgentRole = AgentRole.orchestrator;
    pendingAction = RequestedAction.none;
    currentPointIndex = 0;
    _pendingPhotoIds = [];
    chatMessages = [];
    reportsQueryResults = [];
    latestAssistantResponse = '';
    notifyListeners();

    if (sessionId != null) {
      backend.endSession(sessionId);
    }
  }

  // ── Reports state ──────────────────────────────────────────────────────

  List<ChatMessage> chatMessages = [];
  List<ReportSummary> reportsQueryResults = [];
  String latestAssistantResponse = '';
  bool reportsBusy = false;

  Future<void> runReportsQuery(String query) async {
    final machineId = liveReport?.machineId ?? 'WL-0472';
    _addChat(ChatRole.user, query);
    reportsBusy = true;
    notifyListeners();

    try {
      final result = await backend.queryReports(
        machineId: machineId,
        query: query,
        history: chatMessages,
      );

      reportsQueryResults = result.results;
      latestAssistantResponse = result.assistantText;
      _addChat(ChatRole.assistant, result.assistantText);
    } catch (e) {
      debugPrint('Reports query error: $e');
      latestAssistantResponse = 'Failed to reach the server. Please try again.';
      _addChat(ChatRole.assistant, latestAssistantResponse);
    }

    reportsBusy = false;
    notifyListeners();
  }

  Future<void> sendReportEditInstruction(
      String reportId, String instruction) async {
    _addChat(ChatRole.user, instruction);
    reportsBusy = true;
    notifyListeners();

    try {
      final result =
          await backend.editReport(reportId: reportId, instruction: instruction);

      latestAssistantResponse = result.assistantText;
      _addChat(ChatRole.assistant, result.assistantText);
    } catch (e) {
      debugPrint('Report edit error: $e');
      latestAssistantResponse = 'Failed to update report. Please try again.';
      _addChat(ChatRole.assistant, latestAssistantResponse);
    }

    reportsBusy = false;
    notifyListeners();
  }

  void _addChat(ChatRole role, String text) {
    chatMessages.add(ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}',
      role: role,
      text: text,
      timestamp: DateTime.now(),
    ));
  }
}

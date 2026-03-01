import 'dart:math';
import 'package:flutter/foundation.dart';
import 'audio_capture.dart';
import 'backend_port.dart';
import 'http_backend.dart';
import 'live_camera_handle.dart';
import 'media_service.dart';
import 'models.dart';
import 'stt_service.dart';
import 'tts_service.dart';

class AppState extends ChangeNotifier {
  BackendPort backend;
  final AudioRecorder recorder;
  final MediaService mediaService;
  final TtsService tts;
  final LiveCameraHandle cameraHandle;
  final SttService stt;

  String _backendUrl;
  String get backendUrl => _backendUrl;

  /// User-visible error from the last backend call, or null if none.
  String? lastError;

  AppState({
    required this.backend,
    required this.recorder,
    required this.mediaService,
    required this.tts,
    required this.cameraHandle,
    required this.stt,
    String backendUrl = 'http://localhost:8000',
  }) : _backendUrl = backendUrl {
    tts.onStateChanged = _onTtsStateChanged;
    stt.onStateChanged = () => notifyListeners();
    stt.onFinalTranscript = _onSttTranscript;
  }

  void _onTtsStateChanged() {
    // #region agent log
    debugPrint('[DBG:TTS_STATE] isSpeaking=${tts.isSpeaking} sttListening=${stt.isListening} sttPaused=${stt.pausedForTts}');
    // #endregion
    notifyListeners();
    if (tts.isSpeaking) {
      stt.pauseForTts();
    } else if (stt.isListening && stt.pausedForTts) {
      stt.resumeAfterTts();
    }
  }

  /// Called when the on-device STT produces a final transcript.
  /// Drops it if the agent is busy or TTS is speaking (avoids
  /// feedback loops where the mic picks up TTS output).
  void _onSttTranscript(String transcript) {
    // #region agent log
    debugPrint('[DBG:STT_TRANSCRIPT] text="$transcript" busy=$inspectBusy tts=${tts.isSpeaking} report=${liveReport != null}');
    // #endregion
    if (inspectBusy || tts.isSpeaking) {
      debugPrint('🎤 Dropping transcript — busy=$inspectBusy tts=${tts.isSpeaking}');
      return;
    }
    if (liveReport == null) return;
    sendTextTurn(transcript);
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
      final result = await backend.createSession(machineId);

      liveReport = LiveReport(
        sessionId: result.sessionId,
        machineId: machineId,
        startedAt: DateTime.now(),
        currentZone: result.startingZone,
        currentStep: result.startingStep,
      );

      latestAgentText = result.initialGuidance;
      latestAgentRole = AgentRole.orchestrator;
      pendingAction = RequestedAction.none;
      isVideoActive = true;

      tts.speak(latestAgentText);

      // Begin continuous on-device STT so the operator can talk hands-free.
      stt.startListening();
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

  /// Automatically grab a frame from the live camera feed, upload it to the
  /// data_stream server, and send a follow-up inspect turn so the agent can
  /// run vision analysis. Called when the backend returns [capturePhoto].
  Future<void> _autoCaptureLiveFeed() async {
    final report = liveReport;
    if (report == null) return;
    if (!cameraHandle.isReady) {
      debugPrint('📷 Auto-capture skipped — camera not ready');
      return;
    }

    debugPrint('📷 Auto-capturing frame from live feed');
    inspectBusy = true;
    notifyListeners();

    try {
      final framePath = await cameraHandle.captureFrame();
      if (framePath == null) {
        debugPrint('📷 Auto-capture returned null');
        inspectBusy = false;
        notifyListeners();
        return;
      }

      final turn = await backend.sendInspectTurn(
        sessionId: report.sessionId,
        zoneId: report.currentZone,
        imageFilePath: framePath,
      );
      _applyTurn(turn, report);
    } catch (e) {
      debugPrint('📷 Auto-capture error: $e');
      lastError = 'Failed to send captured frame. Check connection.';
    }

    inspectBusy = false;
    notifyListeners();
  }

  // ── Text turn (type → send → response) ────────────────────────────────

  Future<void> sendTextTurn(String text) async {
    final report = liveReport;
    if (report == null || text.trim().isEmpty) return;

    // #region agent log
    debugPrint('[DBG:SEND] text="${text.trim()}" session=${report.sessionId}');
    // #endregion
    inspectBusy = true;
    notifyListeners();

    try {
      final turn = await backend.sendInspectTurn(
        sessionId: report.sessionId,
        zoneId: report.currentZone,
        text: text.trim(),
      );
      // #region agent log
      debugPrint('[DBG:RECV] agentText="${turn.agentText.length > 80 ? turn.agentText.substring(0, 80) : turn.agentText}" action=${turn.requestedAction}');
      // #endregion
      _applyTurn(turn, report);

      if (turn.requestedAction == RequestedAction.capturePhoto &&
          isVideoActive) {
        inspectBusy = false;
        notifyListeners();
        pendingAction = RequestedAction.none;
        await _autoCaptureLiveFeed();
        return;
      }
    } catch (e) {
      // #region agent log
      debugPrint('[DBG:SEND_ERR] $e');
      // #endregion
      debugPrint('Text turn error: $e');
      lastError = 'Failed to send message. Check connection and try again.';
    }

    inspectBusy = false;
    notifyListeners();
  }

  // ── Live STT listening toggle ────────────────────────────────────────

  Future<void> toggleListening() async {
    if (stt.isListening) {
      await stt.stopListening();
    } else {
      await stt.startListening();
    }
    notifyListeners();
  }

  // ── Audio recording (legacy push-to-talk fallback) ─────────────────

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

        if (turn.requestedAction == RequestedAction.capturePhoto &&
            isVideoActive) {
          inspectBusy = false;
          notifyListeners();
          pendingAction = RequestedAction.none;
          await _autoCaptureLiveFeed();
          return;
        }
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
    final item = MediaItem(
      id: id,
      kind: kind,
      status: MediaStatus.queued,
      label: '${kind.name} – ${report.currentZone}',
      timestamp: DateTime.now(),
      localPath: filePath,
    );
    report.media.add(item);

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
    stt.stopListening();

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
    final machineId = liveReport?.machineId ?? '7777';
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

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'audio_capture.dart';
import 'audio_pipeline.dart';
import 'audio_transport.dart';
import 'backend_port.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  final BackendPort backend;

  AppState(this.backend);

  // ── Inspect state ──────────────────────────────────────────────────────

  LiveReport? liveReport;
  bool inspectBusy = false;
  String latestAgentText = '';
  RequestedAction pendingAction = RequestedAction.none;

  Future<void> startSession(String machineId) async {
    liveReport = LiveReport(
      sessionId: 'sess_${DateTime.now().millisecondsSinceEpoch}',
      machineId: machineId,
      startedAt: DateTime.now(),
      currentZone: 'Front / Bucket Area',
      currentStep: 'Begin walk-around',
    );
    latestAgentText =
        'Session started for $machineId. Begin at the front of the machine.';
    pendingAction = RequestedAction.none;
    notifyListeners();
  }

  Future<void> sendInspectText(String text) async {
    final report = liveReport;
    if (report == null) return;
    inspectBusy = true;
    notifyListeners();

    final turn = await backend.sendInspectMessage(
      sessionId: report.sessionId,
      text: text,
      zoneId: report.currentZone,
    );

    latestAgentText = turn.agentText;
    pendingAction = turn.requestedAction;
    if (turn.suggestedZone != null) report.currentZone = turn.suggestedZone!;
    if (turn.suggestedInspectionPoint != null) {
      report.currentStep = turn.suggestedInspectionPoint!;
    }
    report.findings.addAll(turn.newFindings);

    inspectBusy = false;
    notifyListeners();
  }

  // ── Live feed + voice ──────────────────────────────────────────────────

  /// True while the live video feed is streaming to the agent.
  bool isVideoRecording = false;

  /// True while the microphone is open / inspector is talking.
  bool isAudioRecording = false;

  /// Live partial transcript updated in real time while recording.
  String liveTranscript = '';

  /// Live agent guidance updated in real time while recording.
  String liveAgentText = '';

  /// Current microphone RMS level in dB (0 = full scale, -160 = silence).
  double audioLevelDb = -160.0;

  /// Threshold below which audio is considered too quiet (likely muted/blocked).
  static const double silenceThresholdDb = -50.0;

  /// True when mic level is below the silence threshold.
  bool get isAudioTooQuiet =>
      isAudioRecording && audioLevelDb < silenceThresholdDb;

  late final _pipeline = AudioPipeline(
    source: AvFoundationAudioSource(),
    transport: MockAudioTransport(),
  );
  StreamSubscription? _eventSub;

  Future<void> capturePhoto() => _captureMedia(MediaKind.photo);

  /// Toggles the live video feed. No clip is created; the feed is continuous.
  void toggleVideo() {
    isVideoRecording = !isVideoRecording;
    notifyListeners();
  }

  /// Toggles the microphone. When the inspector stops talking, the
  /// accumulated audio is sent to the agent as a voice turn.
  Future<void> toggleAudio() async {
    if (isAudioRecording) {
      await _pipeline.stop();
      isAudioRecording = false;
      liveTranscript = '';
      liveAgentText = '';
      audioLevelDb = -160.0;
      notifyListeners();
    } else {
      liveTranscript = '';
      _eventSub?.cancel();
      _eventSub = _pipeline.events.listen(_onPipelineEvent);
      final sessionId = liveReport?.sessionId ?? 'unknown';
      await _pipeline.start(sessionId);
      isAudioRecording = true;
      notifyListeners();
    }
  }

  void _onPipelineEvent(BackendEvent event) {
    switch (event) {
      case AudioLevel(:final rmsDb):
        audioLevelDb = rmsDb;
        notifyListeners();
      case AgentPartial(:final text):
        if (text != liveAgentText) {
          liveAgentText = text;
          notifyListeners();
        }
      case AsrPartial(:final text):
        liveTranscript = text;
        notifyListeners();
      case AsrFinal(:final text):
        liveTranscript = text;
        latestAgentText = '';
        notifyListeners();
      case AgentReply(:final text):
        latestAgentText = text;
        notifyListeners();
      case ReportPatch(:final finding):
        final report = liveReport;
        if (report != null) {
          report.findings.add(Finding(
            id: finding['id'] as String,
            severity: FindingSeverity.values.byName(finding['severity'] as String),
            title: finding['title'] as String,
            detail: finding['detail'] as String,
            timestamp: DateTime.now(),
          ));
        }
        liveTranscript = '';
        notifyListeners();
    }
  }

  void endSession() {
    liveReport = null;
    isVideoRecording = false;
    if (isAudioRecording) {
      _pipeline.stop();
    }
    _eventSub?.cancel();
    _eventSub = null;
    isAudioRecording = false;
    liveTranscript = '';
    liveAgentText = '';
    audioLevelDb = -160.0;
    latestAgentText = '';
    pendingAction = RequestedAction.none;
    chatMessages = [];
    reportsQueryResults = [];
    latestAssistantResponse = '';
    notifyListeners();
  }

  Future<void> _captureMedia(MediaKind kind) async {
    final report = liveReport;
    if (report == null) return;

    final id = 'media_${DateTime.now().millisecondsSinceEpoch}';
    final item = MediaItem(
      id: id,
      kind: kind,
      status: MediaStatus.queued,
      label: '${kind.name} – ${report.currentZone}',
      timestamp: DateTime.now(),
      localPath: '/mock/path/$id.${kind == MediaKind.photo ? 'jpg' : kind == MediaKind.video ? 'mp4' : 'm4a'}',
    );
    report.media.add(item);
    notifyListeners();

    // Uploading
    await Future.delayed(const Duration(milliseconds: 800));
    item.status = MediaStatus.uploading;
    notifyListeners();

    final result = await backend.uploadMedia(
      sessionId: report.sessionId,
      kind: kind,
      filePath: item.localPath,
      zoneId: report.currentZone,
    );

    item.status = result.status;
    report.findings.addAll(result.addedFindings);
    if (result.addedFindings.isNotEmpty) {
      latestAgentText =
          'Analysis complete: ${result.notes} ${result.addedFindings.first.detail}';
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

    final result =
        await backend.queryReports(machineId: machineId, query: query);

    reportsQueryResults = result.results;
    latestAssistantResponse = result.assistantText;
    _addChat(ChatRole.assistant, result.assistantText);

    reportsBusy = false;
    notifyListeners();
  }

  Future<void> sendReportEditInstruction(
      String reportId, String instruction) async {
    _addChat(ChatRole.user, instruction);
    reportsBusy = true;
    notifyListeners();

    final result =
        await backend.editReport(reportId: reportId, instruction: instruction);

    latestAssistantResponse = result.assistantText;
    _addChat(ChatRole.assistant, result.assistantText);

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

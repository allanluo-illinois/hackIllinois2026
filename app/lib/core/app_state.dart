import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'audio_pipeline.dart';
import 'backend_port.dart';
import 'media_service.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  final BackendPort backend;
  final AudioPipeline pipeline;
  final MediaService mediaService;

  AppState({
    required this.backend,
    required this.pipeline,
    MediaService? mediaService,
  }) : mediaService = mediaService ?? MediaService();

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

    // Also add as a finding for visibility in the report.
    report.findings.add(Finding(
      id: 'check_${point.id}',
      severity: severity,
      title: point.displayName,
      detail: note ?? severity.name.toUpperCase(),
      timestamp: DateTime.now(),
    ));

    _pendingPhotoIds = [];

    // Advance to next unchecked point in the zone.
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
    // All points in zone checked — stay on last.
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

    // Skip already-checked points.
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
    inspectBusy = true;
    notifyListeners();

    await _ensureZonesLoaded();
    final result = await backend.createSession(machineId);

    // Use the first zone from components.json.
    final startZone = zones.isNotEmpty ? zones.first.zoneId : result.startingZone;

    liveReport = LiveReport(
      sessionId: result.sessionId,
      machineId: machineId,
      startedAt: DateTime.now(),
      currentZone: startZone,
      currentStep: result.startingStep,
    );

    // Set to the first inspection point in the starting zone.
    currentPointIndex = 0;
    _pendingPhotoIds = [];
    final firstPoint = currentPoint;
    if (firstPoint != null) {
      liveReport!.currentStep = firstPoint.displayName;
    }

    latestAgentText = result.initialGuidance;
    latestAgentRole = AgentRole.orchestrator;
    pendingAction = RequestedAction.none;
    inspectBusy = false;
    notifyListeners();

    // Auto-start audio recording and live video feed
    await toggleAudio();
    await toggleVideo();
  }

  Future<void> sendInspectText(String text) async {
    final report = liveReport;
    if (report == null) return;
    inspectBusy = true;
    notifyListeners();

    final turn = await backend.sendInspectTurn(
      sessionId: report.sessionId,
      zoneId: report.currentZone,
      text: text,
    );

    _applyTurn(turn, report);
    inspectBusy = false;
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

  StreamSubscription? _audioEventSub;
  StreamSubscription<AgentMessage>? _videoStreamSub;
  MediaItem? _liveAudioItem;
  MediaItem? _liveVideoItem;

  /// Opens the device camera to take a photo, then uploads it.
  Future<void> capturePhoto() async {
    final path = await mediaService.takePhoto();
    if (path == null) return; // user cancelled
    await _captureMediaFromPath(MediaKind.photo, path);
  }

  /// Opens the device camera to record a video, then uploads it.
  Future<void> captureVideo() async {
    final path = await mediaService.recordVideo();
    if (path == null) return;
    await _captureMediaFromPath(MediaKind.video, path);
  }

  /// Opens the device gallery to pick an image, then uploads it.
  Future<void> pickImageFromGallery() async {
    final path = await mediaService.pickImageFromGallery();
    if (path == null) return;
    await _captureMediaFromPath(MediaKind.photo, path);
  }

  /// Opens the device gallery to pick a video, then uploads it.
  Future<void> pickVideoFromGallery() async {
    final path = await mediaService.pickVideoFromGallery();
    if (path == null) return;
    await _captureMediaFromPath(MediaKind.video, path);
  }

  /// Toggles the live video feed. On start, subscribes to the backend's
  /// video observation stream. On stop, disconnects.
  Future<void> toggleVideo() async {
    final report = liveReport;
    if (report == null) return;

    if (isVideoRecording) {
      debugPrint('📹 Video STOP');
      if (_liveVideoItem != null) {
        _liveVideoItem!.status = MediaStatus.complete;
        _liveVideoItem = null;
      }
      isVideoRecording = false;
      notifyListeners();
      await _videoStreamSub?.cancel();
      _videoStreamSub = null;
      await backend.disconnectVideoStream(report.sessionId);
    } else {
      debugPrint('📹 Video START | zone=${report.currentZone}');
      _liveVideoItem = MediaItem(
        id: 'live_video_${DateTime.now().millisecondsSinceEpoch}',
        kind: MediaKind.video,
        status: MediaStatus.streaming,
        label: 'Live feed – ${report.currentZone}',
        timestamp: DateTime.now(),
        localPath: '',
      );
      report.media.add(_liveVideoItem!);
      isVideoRecording = true;
      notifyListeners();
      final stream = backend.connectVideoStream(
        sessionId: report.sessionId,
        zoneId: report.currentZone,
      );
      _videoStreamSub = stream.listen(_onVideoMessage);
    }
  }

  void _onVideoMessage(AgentMessage msg) {
    final report = liveReport;
    if (report == null) return;

    debugPrint('📹 Vision [${msg.source.name}]: ${msg.text}'
        '${msg.findings.isNotEmpty ? ' | findings=${msg.findings.length}' : ''}');
    latestAgentText = msg.text;
    latestAgentRole = msg.source;
    if (msg.suggestedZone != null) report.currentZone = msg.suggestedZone!;
    report.findings.addAll(msg.findings);
    notifyListeners();
  }

  /// Toggles the microphone. When the inspector stops talking, the
  /// accumulated audio is sent to the agent as a voice turn.
  Future<void> toggleAudio() async {
    if (isAudioRecording) {
      debugPrint('🎙️ Audio STOP | total chunks=$_audioChunkCount');
      _audioChunkCount = 0;
      if (_liveAudioItem != null) {
        _liveAudioItem!.status = MediaStatus.complete;
        _liveAudioItem = null;
      }
      await pipeline.stop();
      isAudioRecording = false;
      liveTranscript = '';
      liveAgentText = '';
      audioLevelDb = -160.0;
      notifyListeners();
    } else {
      final report = liveReport;
      liveTranscript = '';
      _audioEventSub?.cancel();
      _audioEventSub = pipeline.events.listen(_onPipelineEvent);
      final sessionId = report?.sessionId ?? 'unknown';
      _liveAudioItem = MediaItem(
        id: 'live_audio_${DateTime.now().millisecondsSinceEpoch}',
        kind: MediaKind.audio,
        status: MediaStatus.streaming,
        label: 'Audio – ${report?.currentZone ?? 'unknown'}',
        timestamp: DateTime.now(),
        localPath: '',
      );
      report?.media.add(_liveAudioItem!);
      await pipeline.start(sessionId);
      isAudioRecording = true;
      debugPrint('🎙️ Audio START | session=$sessionId');
      notifyListeners();
    }
  }

  int _audioChunkCount = 0;

  void _onPipelineEvent(BackendEvent event) {
    switch (event) {
      case AudioLevel(:final rmsDb):
        audioLevelDb = rmsDb;
        _audioChunkCount++;
        // Log level every 20 chunks to avoid flooding
        if (_audioChunkCount % 20 == 0) {
          debugPrint('🎙️ Audio level: ${rmsDb.toStringAsFixed(1)} dB | '
              'chunks=$_audioChunkCount | '
              'quiet=${rmsDb < silenceThresholdDb}');
        }
        notifyListeners();
      case AgentPartial(:final text):
        if (text != liveAgentText) {
          debugPrint('🤖 Agent partial: $text');
          liveAgentText = text;
          notifyListeners();
        }
      case AsrPartial(:final text):
        debugPrint('🗣️ ASR partial: $text');
        liveTranscript = text;
        notifyListeners();
      case AsrFinal(:final text):
        debugPrint('🗣️ ASR final: $text');
        liveTranscript = text;
        latestAgentText = '';
        notifyListeners();
      case AgentReply(:final text):
        debugPrint('🤖 Agent reply: $text');
        latestAgentText = text;
        notifyListeners();
      case ReportPatch(:final finding):
        debugPrint('📋 Report patch: ${finding['severity']} — ${finding['title']}');
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
    final sessionId = liveReport?.sessionId;
    liveReport = null;

    // Disconnect video stream
    isVideoRecording = false;
    _liveVideoItem = null;
    _videoStreamSub?.cancel();
    _videoStreamSub = null;

    // Stop audio pipeline
    if (isAudioRecording) {
      pipeline.stop();
    }
    _audioEventSub?.cancel();
    _audioEventSub = null;
    _liveAudioItem = null;
    isAudioRecording = false;
    liveTranscript = '';
    liveAgentText = '';
    audioLevelDb = -160.0;

    latestAgentText = '';
    latestAgentRole = AgentRole.orchestrator;
    pendingAction = RequestedAction.none;
    currentPointIndex = 0;
    _pendingPhotoIds = [];
    chatMessages = [];
    reportsQueryResults = [];
    latestAssistantResponse = '';
    notifyListeners();

    // Notify backend asynchronously
    if (sessionId != null) {
      backend.endSession(sessionId);
    }
  }

  Future<void> _captureMediaFromPath(MediaKind kind, String filePath) async {
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

    // Track photo against the current inspection point.
    if (kind == MediaKind.photo) {
      _pendingPhotoIds.add(id);
    }
    notifyListeners();

    // Prepare bytes: images → JPG, videos → raw file bytes.
    final Uint8List bytes;
    final String mimeType;
    if (kind == MediaKind.photo) {
      bytes = await mediaService.toJpgBytes(filePath);
      mimeType = 'image/jpeg';
    } else {
      bytes = await mediaService.readFileBytes(filePath);
      mimeType = 'video/mp4';
    }

    // Debug: verify JPG conversion pipeline
    final isJpeg = bytes.length >= 3 &&
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    debugPrint('📸 Media ready: ${bytes.length} bytes | '
        'mime=$mimeType | jpeg=$isJpeg | point=${point?.id} | src=$filePath');

    item.status = MediaStatus.uploading;
    notifyListeners();

    final result = await backend.uploadMedia(
      sessionId: report.sessionId,
      kind: kind,
      bytes: bytes,
      mimeType: mimeType,
      zoneId: report.currentZone,
    );

    item.status = result.status;
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

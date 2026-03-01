import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'backend_port.dart';
import 'models.dart';

/// HTTP-based implementation of [BackendPort] targeting the FastAPI backend.
///
/// Endpoints:
///   POST /chat   — generator agent (inspection)
///   POST /review — reviewer agent  (reports)
///
/// Frame uploads go to port 8001 (data_stream server) when available.
class HttpBackend implements BackendPort {
  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  HttpBackend({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client();

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// Best-effort upload of an image frame to the backend server so the
  /// vision tool can read it from disk at `data/stream/current_frame.jpg`.
  Future<bool> uploadFrame(String filePath) async {
    try {
      final uploadBase = baseUrl.replaceAll(RegExp(r':\d+$'), ':8000');
      final request = http.MultipartRequest(
          'POST', Uri.parse('$uploadBase/upload-frame'));
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      final streamed = await _client.send(request).timeout(
          const Duration(seconds: 10));
      final resp = await http.Response.fromStream(streamed);
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (e) {
      debugPrint('Frame upload failed (data_stream may not be running): $e');
      return false;
    }
  }

  // ── Session lifecycle ───────────────────────────────────────────────────

  @override
  Future<SessionStartResult> createSession(String machineId) async {
    final sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}';

    final resp = await _client
        .post(
          _uri('/chat'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'user_id': 'operator',
            'session_id': sessionId,
            'text':
                'Starting pre-operation inspection for machine $machineId. '
                'Guide me through the walk-around.',
          }),
        )
        .timeout(timeout);
    _checkStatus(resp);

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return SessionStartResult(
      sessionId: json['session_id'] as String? ?? sessionId,
      initialGuidance:
          json['message'] as String? ?? 'Session started for $machineId.',
      startingZone: 'front_slight_sides',
      startingStep: 'Begin walk-around',
    );
  }

  @override
  Future<void> endSession(String sessionId) async {
    // FastAPI sessions are in-memory; no explicit teardown needed.
  }

  // ── Inspect turn ───────────────────────────────────────────────────────

  @override
  Future<InspectTurn> sendInspectTurn({
    required String sessionId,
    required String zoneId,
    String? text,
    String? audioFilePath,
    String? imageFilePath,
    String? videoFilePath,
  }) async {
    String messageText = text ?? '';

    if (imageFilePath != null) {
      final uploaded = await uploadFrame(imageFilePath);
      if (messageText.isEmpty) {
        messageText = uploaded
            ? 'I just took a photo at zone $zoneId. '
              'Please use your vision tool to analyze the current frame.'
            : 'Photo taken at zone $zoneId.';
      }
    }

    if (videoFilePath != null && messageText.isEmpty) {
      messageText = 'Video recorded at zone $zoneId.';
    }

    if (audioFilePath != null && messageText.isEmpty) {
      messageText = 'Audio note recorded at zone $zoneId.';
    }

    if (messageText.isEmpty) {
      messageText = 'Continuing inspection at zone $zoneId. What should I check next?';
    }

    final resp = await _client
        .post(
          _uri('/chat'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'user_id': 'operator',
            'session_id': sessionId,
            'text': messageText,
          }),
        )
        .timeout(timeout);
    _checkStatus(resp);

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return InspectTurn(
      source: AgentRole.orchestrator,
      agentText: json['message'] as String? ?? '',
    );
  }

  // ── Media upload ───────────────────────────────────────────────────────

  @override
  Future<MediaProcessResult> uploadMedia({
    required String sessionId,
    required MediaKind kind,
    required String filePath,
    required String mimeType,
    String? zoneId,
  }) async {
    if (kind == MediaKind.photo) {
      await uploadFrame(filePath);
    }

    return const MediaProcessResult(
      status: MediaStatus.complete,
      notes: 'Media received.',
    );
  }

  // ── Reports ────────────────────────────────────────────────────────────

  @override
  Future<ReportsQueryResult> queryReports({
    required String machineId,
    required String query,
    List<ChatMessage> history = const [],
  }) async {
    final sessionId = 'review_$machineId';

    final resp = await _client
        .post(
          _uri('/review'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'user_id': 'manager',
            'session_id': sessionId,
            'text': query,
          }),
        )
        .timeout(timeout);
    _checkStatus(resp);

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return ReportsQueryResult(
      results: const [],
      assistantText: json['analysis'] as String? ?? '',
    );
  }

  @override
  Future<ReportUpdateResult> editReport({
    required String reportId,
    required String instruction,
  }) async {
    final resp = await _client
        .post(
          _uri('/review'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'user_id': 'manager',
            'session_id': 'review_edit',
            'text': 'Update report $reportId: $instruction',
          }),
        )
        .timeout(timeout);
    _checkStatus(resp);

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return ReportUpdateResult(
      success: json['status'] == 'success',
      assistantText: json['analysis'] as String? ?? '',
    );
  }

  // ── Download ─────────────────────────────────────────────────────────

  @override
  Future<Uint8List> downloadReport({required Map<String, dynamic> payload}) async {
    final resp = await _client
        .post(
          _uri('/load-inspection'),
          headers: _jsonHeaders,
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    _checkStatus(resp);
    return resp.bodyBytes;
  }

  // ── PDF download ─────────────────────────────────────────────────────

  @override
  Future<Uint8List> downloadReportPdf({required Map<String, dynamic> payload}) async {
    final resp = await _client
        .post(
          _uri('/load-inspection'),
          headers: _jsonHeaders,
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    _checkStatus(resp);
    return resp.bodyBytes;
  }

  // ── Cleanup ────────────────────────────────────────────────────────────

  @override
  void dispose() => _client.close();

  // ── Helpers ────────────────────────────────────────────────────────────

  void _checkStatus(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw HttpException(
      'HTTP ${resp.statusCode}: ${resp.body}',
      uri: resp.request?.url,
    );
  }
}

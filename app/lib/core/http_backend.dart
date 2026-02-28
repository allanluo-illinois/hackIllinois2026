import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'backend_port.dart';
import 'models.dart';

/// HTTP-based implementation of [BackendPort].
///
/// All communication uses JSON over HTTP — no WebSockets.
/// Multipart uploads are used for file-bearing endpoints.
class HttpBackend implements BackendPort {
  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  HttpBackend({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // ── Session lifecycle ───────────────────────────────────────────────────

  @override
  Future<SessionStartResult> createSession(String machineId) async {
    final resp = await _client
        .post(
          _uri('/api/session'),
          headers: _jsonHeaders,
          body: jsonEncode({'machineId': machineId}),
        )
        .timeout(timeout);
    _checkStatus(resp);
    return SessionStartResult.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  @override
  Future<void> endSession(String sessionId) async {
    try {
      await _client
          .delete(_uri('/api/session/$sessionId'), headers: _jsonHeaders)
          .timeout(timeout);
    } catch (e) {
      debugPrint('HttpBackend.endSession error: $e');
    }
  }

  // ── Inspect turn (multipart — supports text + files) ──────────────────

  @override
  Future<InspectTurn> sendInspectTurn({
    required String sessionId,
    required String zoneId,
    String? text,
    String? audioFilePath,
    String? imageFilePath,
    String? videoFilePath,
  }) async {
    final request = http.MultipartRequest(
        'POST', _uri('/api/session/$sessionId/turn'));
    request.fields['zone_id'] = zoneId;
    if (text != null) request.fields['text'] = text;

    if (audioFilePath != null) {
      request.files.add(await http.MultipartFile.fromPath(
          'audio', audioFilePath,
          contentType: _parseMediaType('audio/mp4')));
    }
    if (imageFilePath != null) {
      request.files.add(await http.MultipartFile.fromPath(
          'image', imageFilePath,
          contentType: _parseMediaType('image/jpeg')));
    }
    if (videoFilePath != null) {
      request.files.add(await http.MultipartFile.fromPath(
          'video', videoFilePath,
          contentType: _parseMediaType('video/mp4')));
    }

    final streamed = await _client.send(request).timeout(timeout);
    final resp = await http.Response.fromStream(streamed);
    _checkStatus(resp);
    return InspectTurn.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ── Media upload ──────────────────────────────────────────────────────

  @override
  Future<MediaProcessResult> uploadMedia({
    required String sessionId,
    required MediaKind kind,
    required String filePath,
    required String mimeType,
    String? zoneId,
  }) async {
    final request = http.MultipartRequest(
        'POST', _uri('/api/session/$sessionId/media'));
    request.fields['kind'] = kind.name;
    if (zoneId != null) request.fields['zone_id'] = zoneId;
    request.files.add(await http.MultipartFile.fromPath(
        'file', filePath,
        contentType: _parseMediaType(mimeType)));

    final streamed = await _client.send(request).timeout(timeout);
    final resp = await http.Response.fromStream(streamed);
    _checkStatus(resp);
    return MediaProcessResult.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ── Reports ─────────────────────────────────────────────────────────────

  @override
  Future<ReportsQueryResult> queryReports({
    required String machineId,
    required String query,
    List<ChatMessage> history = const [],
  }) async {
    final resp = await _client
        .post(
          _uri('/api/reports/query'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'machineId': machineId,
            'query': query,
            'history': history.map((m) => m.toJson()).toList(),
          }),
        )
        .timeout(timeout);
    _checkStatus(resp);
    return ReportsQueryResult.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  @override
  Future<ReportUpdateResult> editReport({
    required String reportId,
    required String instruction,
  }) async {
    final resp = await _client
        .post(
          _uri('/api/reports/$reportId/edit'),
          headers: _jsonHeaders,
          body: jsonEncode({'instruction': instruction}),
        )
        .timeout(timeout);
    _checkStatus(resp);
    return ReportUpdateResult.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────

  @override
  void dispose() => _client.close();

  // ── Helpers ─────────────────────────────────────────────────────────────

  void _checkStatus(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw HttpException(
      'HTTP ${resp.statusCode}: ${resp.body}',
      uri: resp.request?.url,
    );
  }

  static MediaType _parseMediaType(String mime) {
    final parts = mime.split('/');
    return MediaType(parts[0], parts.length > 1 ? parts[1] : '*');
  }
}

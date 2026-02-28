import 'dart:async';
import 'dart:typed_data';

import 'models.dart';

abstract class AudioTransport {
  Stream<BackendEvent> get events;
  Future<void> open(String sessionId);
  Future<void> sendChunk(Uint8List chunk);
  Future<void> close();
}

class MockAudioTransport implements AudioTransport {
  final _controller = StreamController<BackendEvent>.broadcast();
  int _chunkCount = 0;

  static const _partialTexts = [
    'Checking…',
    'Checking bucket teeth…',
    'Checking bucket teeth condition…',
    'Bucket teeth condition looks normal…',
    'Bucket teeth condition looks normal, no visible wear…',
  ];

  @override
  Stream<BackendEvent> get events => _controller.stream;

  @override
  Future<void> open(String sessionId) async {
    _chunkCount = 0;
  }

  @override
  Future<void> sendChunk(Uint8List chunk) async {
    _chunkCount++;
    if (_chunkCount % 8 == 0) {
      final idx = (_chunkCount ~/ 8 - 1) % _partialTexts.length;
      _controller.add(AsrPartial(_partialTexts[idx]));
    }
  }

  @override
  Future<void> close() async {
    _controller.add(const AsrFinal(
      'Bucket teeth condition looks normal, no visible wear or damage detected.',
    ));

    await Future<void>.delayed(const Duration(milliseconds: 200));
    _controller.add(const AgentReply(
      'Good. Now please capture a photo of the bucket teeth for documentation.',
    ));

    await Future<void>.delayed(const Duration(milliseconds: 100));
    _controller.add(const ReportPatch({
      'id': 'f_mock_001',
      'severity': 'ok',
      'title': 'Bucket teeth',
      'detail': 'Visual inspection normal — no wear or damage.',
    }));
  }
}

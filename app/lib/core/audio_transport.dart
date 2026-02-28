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
  String _latestTranscript = '';
  String _lastEmittedAgent = '';
  Timer? _agentTimer;

  static const _partialTexts = [
    'Checking…',
    'Checking bucket teeth…',
    'Checking bucket teeth condition…',
    'Bucket teeth condition looks normal…',
    'Bucket teeth condition looks normal, no visible wear…',
  ];

  static const _keywordResponses = <String, String>{
    'tire': 'Focus on tread wear, sidewall cuts, lug nuts.',
    'hose': 'Look for leaks, cracks, wetness around fittings.',
    'hydraulic': 'Look for leaks, cracks, wetness around fittings.',
    'lights': 'Confirm all lights are intact and functioning.',
    'light': 'Confirm all lights are intact and functioning.',
    'seatbelt': 'Check fraying and latch operation.',
    'belt': 'Check fraying and latch operation.',
    'leak': 'Mark as REVIEW and capture a photo.',
    'bucket': 'Inspect teeth, cutting edge, and structural welds.',
    'engine': 'Listen for unusual sounds, check fluid levels.',
    'oil': 'Check for proper level and discoloration.',
    'coolant': 'Verify level and look for residue around cap.',
    'mirror': 'Confirm mirrors are secure and uncracked.',
    'cab': 'Check seals, glass condition, and step integrity.',
  };

  @override
  Stream<BackendEvent> get events => _controller.stream;

  @override
  Future<void> open(String sessionId) async {
    _chunkCount = 0;
    _latestTranscript = '';
    _lastEmittedAgent = '';

    _agentTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      final response = _generateAgentResponse(_latestTranscript);
      if (response != _lastEmittedAgent) {
        _lastEmittedAgent = response;
        _controller.add(AgentPartial(response));
      }
    });
  }

  @override
  Future<void> sendChunk(Uint8List chunk) async {
    _chunkCount++;
    if (_chunkCount % 8 == 0) {
      final idx = (_chunkCount ~/ 8 - 1) % _partialTexts.length;
      _latestTranscript = _partialTexts[idx];
      _controller.add(AsrPartial(_latestTranscript));
    }
  }

  @override
  Future<void> close() async {
    _agentTimer?.cancel();
    _agentTimer = null;

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

  String _generateAgentResponse(String transcript) {
    if (transcript.isEmpty) {
      return 'Tell me what zone you\'re inspecting.';
    }

    final lower = transcript.toLowerCase();
    for (final entry in _keywordResponses.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }

    return 'Understood — continue your inspection.';
  }
}

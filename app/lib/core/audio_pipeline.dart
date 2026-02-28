import 'dart:async';

import 'audio_capture.dart';
import 'audio_transport.dart';
import 'models.dart';

class AudioPipeline {
  final AudioSource source;
  final AudioTransport transport;

  final _eventController = StreamController<BackendEvent>.broadcast();
  StreamSubscription? _chunkSub;
  StreamSubscription? _levelSub;
  StreamSubscription? _transportSub;

  AudioPipeline({required this.source, required this.transport});

  Stream<BackendEvent> get events => _eventController.stream;

  Future<void> start(String sessionId) async {
    _transportSub = transport.events.listen(_eventController.add);
    _levelSub = source.levelDb.listen((db) {
      _eventController.add(AudioLevel(db));
    });
    await transport.open(sessionId);
    _chunkSub = source.audioChunks.listen((chunk) {
      transport.sendChunk(chunk);
    });
    await source.start();
  }

  Future<void> stop() async {
    await source.stop();
    await _chunkSub?.cancel();
    _chunkSub = null;
    await _levelSub?.cancel();
    _levelSub = null;
    await transport.close();
    await _transportSub?.cancel();
    _transportSub = null;
  }
}

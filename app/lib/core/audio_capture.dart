import 'dart:async';

import 'package:flutter/services.dart';

abstract class AudioSource {
  Stream<Uint8List> get audioChunks;
  Stream<double> get levelDb;
  Future<void> start();
  Future<void> stop();
}

class AvFoundationAudioSource implements AudioSource {
  static const _method = MethodChannel('com.catinspector/audio_capture');
  static const _event = EventChannel('com.catinspector/audio_stream');

  final _chunkController = StreamController<Uint8List>.broadcast();
  final _levelController = StreamController<double>.broadcast();
  StreamSubscription? _platformSub;

  @override
  Stream<Uint8List> get audioChunks => _chunkController.stream;

  @override
  Stream<double> get levelDb => _levelController.stream;

  @override
  Future<void> start() async {
    _platformSub = _event.receiveBroadcastStream().listen((data) {
      if (data is Map) {
        final pcm = data['pcm'];
        if (pcm is Uint8List) _chunkController.add(pcm);
        final db = data['rmsDb'];
        if (db is double) _levelController.add(db);
      } else if (data is Uint8List) {
        _chunkController.add(data);
      }
    });
    await _method.invokeMethod('start');
  }

  @override
  Future<void> stop() async {
    await _method.invokeMethod('stop');
    await _platformSub?.cancel();
    _platformSub = null;
  }

  Future<bool> isRunning() async =>
      await _method.invokeMethod<bool>('isRunning') ?? false;
}

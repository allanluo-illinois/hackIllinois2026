import 'package:flutter/services.dart';

/// Records audio to a compressed .m4a file on the device.
/// Call [start] to begin recording, [stop] to finish and get the file path.
abstract class AudioRecorder {
  Future<void> start();

  /// Stops recording and returns the path to the .m4a file, or null if
  /// nothing was recorded.
  Future<String?> stop();

  Future<bool> isRunning();
}

class AvFoundationRecorder implements AudioRecorder {
  static const _method = MethodChannel('com.catinspector/audio_capture');

  @override
  Future<void> start() => _method.invokeMethod('start');

  @override
  Future<String?> stop() => _method.invokeMethod<String>('stop');

  @override
  Future<bool> isRunning() async =>
      await _method.invokeMethod<bool>('isRunning') ?? false;
}

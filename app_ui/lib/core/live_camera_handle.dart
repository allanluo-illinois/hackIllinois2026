import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Callback that receives the path to a captured JPEG frame.
typedef FrameUploadCallback = Future<void> Function(String filePath);

/// Lightweight bridge that lets [AppState] capture a frame from the live
/// camera feed without directly depending on the widget tree.
///
/// [CameraPreviewCard] calls [attach]/[detach] as the controller comes and
/// goes; [AppState] calls [captureFrame] when the backend requests a photo.
///
/// Call [startPeriodicCapture] to begin streaming frames to the backend at a
/// fixed interval (default every 3 seconds).
class LiveCameraHandle {
  CameraController? _controller;
  Timer? _periodicTimer;
  bool _capturing = false;

  void attach(CameraController controller) {
    _controller = controller;
    debugPrint('📷 LiveCameraHandle: controller attached');
  }

  void detach() {
    stopPeriodicCapture();
    _controller = null;
    debugPrint('📷 LiveCameraHandle: controller detached');
  }

  bool get isReady => _controller?.value.isInitialized ?? false;

  bool get isPeriodicCaptureActive => _periodicTimer?.isActive ?? false;

  /// Grab a single JPEG frame from the live preview and return its path,
  /// or `null` if the camera isn't available.
  Future<String?> captureFrame() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return null;
    try {
      final file = await ctrl.takePicture();
      debugPrint('📷 LiveCameraHandle: captured ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('📷 LiveCameraHandle: capture failed — $e');
      return null;
    }
  }

  /// Begin periodically capturing frames and forwarding them to [onFrame].
  ///
  /// [interval] controls how often a frame is grabbed (default 3 s).
  /// If a previous capture is still in flight the tick is skipped so we
  /// never queue up work faster than the camera / network can handle.
  void startPeriodicCapture({
    required FrameUploadCallback onFrame,
    Duration interval = const Duration(seconds: 3),
  }) {
    stopPeriodicCapture();
    debugPrint('📷 Periodic capture started (every ${interval.inSeconds}s)');

    _periodicTimer = Timer.periodic(interval, (_) async {
      if (_capturing || !isReady) return;
      _capturing = true;
      try {
        final path = await captureFrame();
        if (path != null) {
          await onFrame(path);
        }
      } finally {
        _capturing = false;
      }
    });
  }

  /// Stop the periodic capture timer.
  void stopPeriodicCapture() {
    if (_periodicTimer != null) {
      _periodicTimer!.cancel();
      _periodicTimer = null;
      debugPrint('📷 Periodic capture stopped');
    }
  }
}

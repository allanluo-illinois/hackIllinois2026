import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Lightweight bridge that lets [AppState] capture a frame from the live
/// camera feed without directly depending on the widget tree.
///
/// [CameraPreviewCard] calls [attach]/[detach] as the controller comes and
/// goes; [AppState] calls [captureFrame] when the backend requests a photo.
class LiveCameraHandle {
  CameraController? _controller;

  void attach(CameraController controller) {
    _controller = controller;
    debugPrint('📷 LiveCameraHandle: controller attached');
  }

  void detach() {
    _controller = null;
    debugPrint('📷 LiveCameraHandle: controller detached');
  }

  bool get isReady => _controller?.value.isInitialized ?? false;

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
}

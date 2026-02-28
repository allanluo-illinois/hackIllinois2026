import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Thin wrapper around image_picker for capturing/picking photos and videos.
/// Keeps platform logic out of AppState and UI code.
///
/// On simulator (no camera), set [useGalleryFallback] to true so that
/// "take photo" / "record video" fall back to gallery picks for testing.
class MediaService {
  final ImagePicker _picker = ImagePicker();

  /// When true, camera actions fall back to gallery (for simulator testing).
  final bool useGalleryFallback;

  MediaService({this.useGalleryFallback = false});

  ImageSource get _cameraOrFallback =>
      useGalleryFallback ? ImageSource.gallery : ImageSource.camera;

  /// Capture a photo using the device camera.
  /// Returns the file path, or null if the user cancelled.
  Future<String?> takePhoto({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: _cameraOrFallback,
        maxWidth: maxWidth ?? 1920,
        maxHeight: maxHeight ?? 1080,
        imageQuality: imageQuality ?? 85,
      );
      return file?.path;
    } catch (e) {
      debugPrint('MediaService.takePhoto error: $e');
      return null;
    }
  }

  /// Record a video using the device camera. No duration limit —
  /// video is processed in real time by the backend.
  /// Returns the file path, or null if the user cancelled.
  Future<String?> recordVideo({
    CameraDevice preferredCamera = CameraDevice.rear,
  }) async {
    try {
      final XFile? file = await _picker.pickVideo(
        source: _cameraOrFallback,
        preferredCameraDevice: preferredCamera,
      );
      return file?.path;
    } catch (e) {
      debugPrint('MediaService.recordVideo error: $e');
      return null;
    }
  }

  /// Pick an image from the device gallery.
  /// Returns the file path, or null if the user cancelled.
  Future<String?> pickImageFromGallery({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxWidth ?? 1920,
      maxHeight: maxHeight ?? 1080,
      imageQuality: imageQuality ?? 85,
    );
    return file?.path;
  }

  /// Pick a video from the device gallery.
  /// Returns the file path, or null if the user cancelled.
  Future<String?> pickVideoFromGallery() async {
    final XFile? file = await _picker.pickVideo(
      source: ImageSource.gallery,
    );
    return file?.path;
  }

  // ── Image preparation ───────────────────────────────────────────────────

  /// Reads an image file and returns its bytes as JPEG.
  ///
  /// On iOS, `image_picker` with [imageQuality] already re-encodes HEIC → JPG,
  /// so most paths will already be JPEG. This method acts as the canonical
  /// normalisation step: if the file is already JPEG it returns raw bytes;
  /// otherwise it decodes → re-encodes via `dart:ui`.
  Future<Uint8List> toJpgBytes(String imagePath) async {
    final file = File(imagePath);
    final raw = await file.readAsBytes();

    if (_isJpeg(raw)) return raw;

    // Decode any supported image format and re-encode as JPEG.
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    final byteData =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    codec.dispose();
    frame.image.dispose();

    if (byteData == null) {
      debugPrint('MediaService.toJpgBytes: failed to decode $imagePath');
      return raw; // fallback: send original bytes
    }

    // Re-encode RGBA → PNG via dart:ui (then the backend can accept it).
    // dart:ui does not expose a JPEG encoder, so we encode as PNG.
    // For true JPEG encoding, a native plugin (e.g. flutter_image_compress)
    // can be swapped in here without changing any callers.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final image = await _decodeImage(raw);
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    final encoded = await picture.toImage(image.width, image.height);
    final png =
        await encoded.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    encoded.dispose();
    image.dispose();

    return png?.buffer.asUint8List() ?? raw;
  }

  /// Reads raw file bytes (for video or any binary payload).
  Future<Uint8List> readFileBytes(String path) async {
    return File(path).readAsBytes();
  }

  /// True if [bytes] starts with the JPEG magic bytes (0xFF 0xD8 0xFF).
  static bool _isJpeg(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;

  static Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image.clone();
    codec.dispose();
    return image;
  }
}

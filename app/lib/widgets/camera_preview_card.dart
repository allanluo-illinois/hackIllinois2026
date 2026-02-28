import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Live video feed panel using the device camera.
///
/// Initialises a [CameraController] when [isActive] becomes true and
/// disposes it when deactivated. The preview is shown inside an
/// AnimatedContainer so it slides in/out smoothly.
class CameraPreviewCard extends StatefulWidget {
  const CameraPreviewCard({
    super.key,
    required this.isActive,
    required this.onSnapPhoto,
  });

  /// Driven by AppState.isVideoRecording — caller controls this.
  final bool isActive;

  /// Called when the inspector taps "Snap Photo" inside the feed.
  final VoidCallback onSnapPhoto;

  @override
  State<CameraPreviewCard> createState() => _CameraPreviewCardState();
}

class _CameraPreviewCardState extends State<CameraPreviewCard>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initialising = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) _initCamera();
  }

  @override
  void didUpdateWidget(CameraPreviewCard old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _initCamera();
    } else if (!widget.isActive && old.isActive) {
      _disposeCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release camera when app goes to background, re-init on resume.
    if (_controller == null) return;
    if (state == AppLifecycleState.inactive) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed && widget.isActive) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (_initialising || (_controller?.value.isInitialized ?? false)) return;
    _initialising = true;
    _error = null;
    setState(() {});

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _error = 'No cameras available';
        _initialising = false;
        if (mounted) setState(() {});
        return;
      }

      // Prefer the rear camera.
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false, // audio is handled separately by AudioPipeline
      );

      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }

      _controller = controller;
      _initialising = false;
      setState(() {});
    } catch (e) {
      _error = e.toString();
      _initialising = false;
      if (mounted) setState(() {});
    }
  }

  void _disposeCamera() {
    _controller?.dispose();
    _controller = null;
    _initialising = false;
  }

  @override
  Widget build(BuildContext context) {
    final previewHeight =
        (MediaQuery.of(context).size.width - 24) * 9 / 16;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      height: widget.isActive ? previewHeight : 0,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: widget.isActive
          ? Stack(
              fit: StackFit.expand,
              children: [
                // ── Viewport ───────────────────────────────────────────────
                _buildViewport(),

                // ── Top bar ────────────────────────────────────────────────
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.fiber_manual_record,
                            color: Colors.red, size: 10),
                        SizedBox(width: 6),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Feed active — agent watching',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Snap photo button (bottom-right) ───────────────────────
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: _SnapButton(onTap: widget.onSnapPhoto),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildViewport() {
    final controller = _controller;

    // Camera ready — show live preview.
    if (controller != null && controller.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: controller.value.previewSize!.height,
          height: controller.value.previewSize!.width,
          child: CameraPreview(controller),
        ),
      );
    }

    // Error state.
    if (_error != null) {
      return Container(
        color: const Color(0xFF0A0A0A),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_outlined,
                    color: Colors.white24, size: 48),
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    // Initialising — show loading indicator.
    return Container(
      color: const Color(0xFF0A0A0A),
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white38),
      ),
    );
  }
}

class _SnapButton extends StatelessWidget {
  const _SnapButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white30),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt, color: Colors.white, size: 16),
            SizedBox(width: 6),
            Text('Snap Photo',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

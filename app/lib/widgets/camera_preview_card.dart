import 'package:flutter/material.dart';

/// Live video feed panel.
/// The placeholder viewport is replaced with CameraPreview(controller)
/// from the `camera` package when integrating real hardware — no other
/// changes needed.
class CameraPreviewCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final previewHeight =
        (MediaQuery.of(context).size.width - 24) * 9 / 16;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      height: isActive ? previewHeight : 0,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: isActive
          ? Stack(
              fit: StackFit.expand,
              children: [
                // ── Viewport ───────────────────────────────────────────────
                // Swap this for CameraPreview(controller) from `camera` pkg.
                Container(
                  color: const Color(0xFF0A0A0A),
                  child: const Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam_outlined,
                              color: Colors.white24, size: 48),
                          SizedBox(height: 8),
                          Text('Live Feed',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),

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
                  child: _SnapButton(onTap: onSnapPhoto),
                ),
              ],
            )
          : const SizedBox.shrink(),
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

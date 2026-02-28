import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../widgets/camera_preview_card.dart';

class InspectTab extends StatelessWidget {
  const InspectTab({super.key});

  @override
  Widget build(BuildContext context) {
    final report = context.watch<AppState>().liveReport;
    return report == null ? const _Landing() : const _ActiveSession();
  }
}

// ── Landing ────────────────────────────────────────────────────────────────

class _Landing extends StatefulWidget {
  const _Landing();

  @override
  State<_Landing> createState() => _LandingState();
}

class _LandingState extends State<_Landing> {
  final _ctrl = TextEditingController(text: 'WL-0472');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Inspect')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset(
                'assets/982.png',
                height: 180,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Text('CAT 950–982 Inspector',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 32),
              TextField(
                controller: _ctrl,
                decoration: const InputDecoration(
                  labelText: 'Machine ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.tag),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Inspection'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: state.inspectBusy
                    ? null
                    : () {
                        final id = _ctrl.text.trim();
                        if (id.isNotEmpty) {
                          context.read<AppState>().startSession(id);
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Active session ─────────────────────────────────────────────────────────

class _ActiveSession extends StatefulWidget {
  const _ActiveSession();

  @override
  State<_ActiveSession> createState() => _ActiveSessionState();
}

class _ActiveSessionState extends State<_ActiveSession> {
  late Timer _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    final start = context.read<AppState>().liveReport!.startedAt;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsed = DateTime.now().difference(start));
      }
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  void _confirmEnd(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Session?'),
        content: const Text(
            'This will discard the current session and return to the start screen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AppState>().endSession();
            },
            child: const Text('End Session'),
          ),
        ],
      ),
    );
  }

  String get _timerLabel {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final report = state.liveReport;
    if (report == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspect'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Chip(
              backgroundColor: const Color(0xFFFFCD11),
              avatar: const Icon(Icons.timer_outlined, size: 16,
                  color: Colors.black),
              label: Text(_timerLabel,
                  style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()])),
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.stop_circle_outlined,
                color: Color(0xFFFF4444)),
            label: const Text('End',
                style: TextStyle(
                    color: Color(0xFFFF4444), fontWeight: FontWeight.w600)),
            onPressed: () => _confirmEnd(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SessionHeader(report: report),
          const SizedBox(height: 10),
          _AgentCard(text: state.latestAgentText, busy: state.inspectBusy),
          if (state.isAudioRecording || state.liveTranscript.isNotEmpty) ...[
            const SizedBox(height: 10),
            _LiveTranscriptCard(
              text: state.liveTranscript,
              isListening: state.isAudioRecording,
            ),
          ],
          const SizedBox(height: 10),
          _ActionRow(busy: state.inspectBusy),
          const SizedBox(height: 10),
          CameraPreviewCard(
            isActive: state.isVideoRecording,
            onSnapPhoto: () => context.read<AppState>().capturePhoto(),
          ),
          if (state.isVideoRecording) const SizedBox(height: 10),
          _LiveReportCard(report: report),
        ],
      ),
    );
  }
}

// ── Session header card ────────────────────────────────────────────────────

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({required this.report});
  final LiveReport report;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.directions_car_outlined, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report.machineId,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(report.currentZone,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Chip(
              label: const Text('Active'),
              avatar: const Icon(Icons.circle, size: 10, color: Colors.green),
              backgroundColor:
                  Colors.green.withValues(alpha: 0.1),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Agent guidance card ────────────────────────────────────────────────────

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.text, required this.busy});
  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.volume_up_outlined, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: busy
                  ? const SizedBox(
                      height: 20,
                      child: LinearProgressIndicator(),
                    )
                  : Text(
                      text.isEmpty ? 'Waiting for guidance…' : text,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action row ─────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.busy});
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // PRIMARY: Talk button — full width, voice is the main input
        _TalkButton(
          isListening: state.isAudioRecording,
          busy: busy,
          onToggle: () => context.read<AppState>().toggleAudio(),
        ),
        const SizedBox(height: 8),
        // SECONDARY: Live feed toggle | Photo evidence | Text note
        Row(
          children: [
            _IconToggle(
              icon: Icons.videocam_outlined,
              activeIcon: Icons.videocam,
              label: 'Live Feed',
              isActive: state.isVideoRecording,
              onTap: busy ? null : () => context.read<AppState>().toggleVideo(),
            ),
            const SizedBox(width: 8),
            _IconToggle(
              icon: Icons.camera_alt_outlined,
              activeIcon: Icons.camera_alt,
              label: 'Photo',
              isActive: false,
              onTap: busy ? null : () => context.read<AppState>().capturePhoto(),
            ),
            const SizedBox(width: 8),
            _IconToggle(
              icon: Icons.edit_note_outlined,
              activeIcon: Icons.edit_note,
              label: 'Note',
              isActive: false,
              onTap: busy ? null : () => _showNoteSheet(context),
            ),
          ],
        ),
      ],
    );
  }

  void _showNoteSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NoteSheet(),
    );
  }
}

/// Large primary Talk button — the inspector's main input.
class _TalkButton extends StatelessWidget {
  const _TalkButton({
    required this.isListening,
    required this.busy,
    required this.onToggle,
  });

  final bool isListening;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor:
            isListening ? Colors.red : const Color(0xFFFFCD11),
        foregroundColor: isListening ? Colors.white : Colors.black,
      ),
      onPressed: busy ? null : onToggle,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isListening)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.circle, size: 10, color: Colors.white),
            ),
          Icon(isListening ? Icons.mic : Icons.mic_none_outlined),
          const SizedBox(width: 8),
          Text(
            isListening ? 'Listening…  Tap to send' : 'Talk to Agent',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Compact toggle for secondary actions (Live Feed, Photo, Note).
class _IconToggle extends StatelessWidget {
  const _IconToggle({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          foregroundColor: isActive ? Colors.red : null,
          side: isActive
              ? const BorderSide(color: Colors.red, width: 1.5)
              : null,
        ),
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.circle, size: 8, color: Colors.red),
              ),
            Icon(isActive ? activeIcon : icon, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ── Note bottom sheet ──────────────────────────────────────────────────────

class _NoteSheet extends StatefulWidget {
  const _NoteSheet();

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _ctrl = TextEditingController();
  FindingSeverity _severity = FindingSeverity.ok;

  static const _labels = {
    FindingSeverity.ok: 'OK',
    FindingSeverity.review: 'Review',
    FindingSeverity.critical: 'Critical',
  };

  static const _colors = {
    FindingSeverity.ok: Colors.green,
    FindingSeverity.review: Colors.orange,
    FindingSeverity.critical: Colors.red,
  };

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add Finding',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          // Severity chips
          Wrap(
            spacing: 8,
            children: FindingSeverity.values.map((s) {
              final selected = s == _severity;
              return FilterChip(
                label: Text(_labels[s]!),
                selected: selected,
                selectedColor: _colors[s]!.withValues(alpha: 0.2),
                checkmarkColor: _colors[s],
                onSelected: (_) => setState(() => _severity = s),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Describe the finding…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final text = _ctrl.text.trim();
              if (text.isNotEmpty) {
                context.read<AppState>().addManualFinding(_severity, text);
                Navigator.pop(context);
              }
            },
            child: const Text('Add Finding'),
          ),
        ],
      ),
    );
  }
}

// ── Live report card ───────────────────────────────────────────────────────

class _LiveReportCard extends StatefulWidget {
  const _LiveReportCard({required this.report});
  final LiveReport report;

  @override
  State<_LiveReportCard> createState() => _LiveReportCardState();
}

class _LiveReportCardState extends State<_LiveReportCard> {
  bool _jsonExpanded = false;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Live Report',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 16),

            // Findings
            if (report.findings.isEmpty)
              const _EmptyHint(text: 'No findings yet.')
            else
              ...report.findings.reversed
                  .take(5)
                  .map((f) => _FindingTile(finding: f)),

            // Media
            if (report.media.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Media',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              ...report.media.reversed.map((m) => _MediaTile(item: m)),
            ],

            // Debug JSON
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _jsonExpanded = !_jsonExpanded),
              child: Row(
                children: [
                  Icon(
                    _jsonExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 18,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text('Debug JSON',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            ),
            if (_jsonExpanded)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  const JsonEncoder.withIndent('  ').convert(report.toJson()),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Finding tile ───────────────────────────────────────────────────────────

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.finding});
  final Finding finding;

  static const _icons = {
    FindingSeverity.ok: (Icons.check_circle_outline, Colors.green),
    FindingSeverity.review: (Icons.warning_amber_outlined, Colors.orange),
    FindingSeverity.critical: (Icons.error_outline, Colors.red),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _icons[finding.severity]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(finding.title,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(finding.detail,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Media tile ─────────────────────────────────────────────────────────────

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.item});
  final MediaItem item;

  static const _statusColors = {
    MediaStatus.queued: Colors.grey,
    MediaStatus.uploading: Colors.blue,
    MediaStatus.processing: Colors.orange,
    MediaStatus.complete: Colors.green,
    MediaStatus.failed: Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[item.status]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            item.kind == MediaKind.photo
                ? Icons.image_outlined
                : item.kind == MediaKind.video
                    ? Icons.videocam_outlined
                    : Icons.mic_none_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(item.label,
                  style: Theme.of(context).textTheme.bodySmall)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              item.status.name,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live transcript card ───────────────────────────────────────────────────

class _LiveTranscriptCard extends StatelessWidget {
  const _LiveTranscriptCard({required this.text, required this.isListening});
  final String text;
  final bool isListening;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey.shade900,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (isListening)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white70,
                  ),
                ),
              ),
            Expanded(
              child: Text(
                text.isEmpty ? 'Listening…' : text,
                style: TextStyle(
                  color: text.isEmpty ? Colors.white38 : Colors.white,
                  fontSize: 14,
                  fontStyle: text.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline)),
    );
  }
}

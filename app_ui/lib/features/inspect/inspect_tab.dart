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
  final _machineCtrl = TextEditingController(text: 'WL-0472');
  late final TextEditingController _urlCtrl;
  bool _showServer = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(
        text: context.read<AppState>().backendUrl);
  }

  @override
  void dispose() {
    _machineCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Inspect')),
      body: Center(
        child: SingleChildScrollView(
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
                controller: _machineCtrl,
                decoration: const InputDecoration(
                  labelText: 'Machine ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.tag),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setState(() => _showServer = !_showServer),
                child: Row(
                  children: [
                    Icon(
                      _showServer ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text('Server',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline)),
                  ],
                ),
              ),
              if (_showServer) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'Backend URL',
                    hintText: 'http://192.168.x.x:8080',
                    prefixIcon: const Icon(Icons.dns_outlined),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check),
                      tooltip: 'Apply',
                      onPressed: () {
                        context
                            .read<AppState>()
                            .updateBackendUrl(_urlCtrl.text);
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
                  onSubmitted: (url) {
                    context.read<AppState>().updateBackendUrl(url);
                  },
                ),
              ],
              if (state.lastError != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(error: state.lastError!),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Inspection'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: state.inspectBusy
                    ? null
                    : () {
                        final id = _machineCtrl.text.trim();
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
          if (state.lastError != null) ...[
            _ErrorBanner(error: state.lastError!),
            const SizedBox(height: 10),
          ],
          _AgentCard(
            text: state.latestAgentText,
            busy: state.inspectBusy,
            role: state.latestAgentRole,
          ),
          if (state.pendingAction != RequestedAction.none) ...[
            const SizedBox(height: 10),
            _RequestedActionBanner(action: state.pendingAction),
          ],
          const SizedBox(height: 10),
          _ActionRow(busy: state.inspectBusy),
          const SizedBox(height: 10),
          CameraPreviewCard(
            isActive: state.isVideoActive,
            onSnapPhoto: () => context.read<AppState>().capturePhoto(),
          ),
          if (state.isVideoActive) const SizedBox(height: 10),
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
  const _AgentCard({
    required this.text,
    required this.busy,
    required this.role,
  });
  final String text;
  final bool busy;
  final AgentRole role;

  static const _roleMeta = {
    AgentRole.orchestrator: (label: 'Agent', color: Color(0xFF1A1A1A)),
    AgentRole.vision: (label: 'Vision', color: Color(0xFF1565C0)),
    AgentRole.safety: (label: 'Safety', color: Color(0xFFEF6C00)),
    AgentRole.reports: (label: 'Reports', color: Color(0xFF6A1B9A)),
  };

  @override
  Widget build(BuildContext context) {
    final meta = _roleMeta[role]!;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.volume_up_outlined, size: 20),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: meta.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    meta.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: meta.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (busy)
              const SizedBox(
                height: 20,
                child: LinearProgressIndicator(),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14) *
                      1.4 * 2,
                ),
                child: Text(
                  text.isEmpty ? 'Waiting for guidance…' : text,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Action row ─────────────────────────────────────────────────────────────

class _ActionRow extends StatefulWidget {
  const _ActionRow({required this.busy});
  final bool busy;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  final _textCtrl = TextEditingController();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _sendText() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || widget.busy) return;
    _textCtrl.clear();
    context.read<AppState>().sendTextTurn(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textCtrl,
                enabled: !widget.busy,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: InputDecoration(
                  hintText: 'Type a message to the agent…',
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  isDense: true,
                  suffixIcon: widget.busy
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: widget.busy ? null : _sendText,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _TalkButton(
          isListening: state.isAudioRecording,
          busy: widget.busy,
          onToggle: () => context.read<AppState>().toggleAudio(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _IconToggle(
              icon: Icons.videocam_outlined,
              activeIcon: Icons.videocam,
              label: 'Live Feed',
              isActive: state.isVideoActive,
              flex: 2,
              onTap: widget.busy ? null : () => context.read<AppState>().toggleVideo(),
            ),
            const SizedBox(width: 8),
            _IconToggle(
              icon: Icons.edit_note_outlined,
              activeIcon: Icons.edit_note,
              label: 'Note',
              isActive: false,
              onTap: widget.busy ? null : () => _showNoteSheet(context),
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

/// Large primary Talk button — record audio, then upload on release.
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
            isListening ? 'Recording…  Tap to send' : 'Talk to Agent',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Compact toggle for secondary actions (Camera, Photo, Note).
class _IconToggle extends StatelessWidget {
  const _IconToggle({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.flex = 1,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
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

            if (report.findings.isEmpty)
              const _EmptyHint(text: 'No findings yet.')
            else
              ...report.findings.reversed
                  .take(5)
                  .map((f) => _FindingTile(finding: f)),

            if (report.media.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Media',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              ...report.media.reversed.map((m) => _MediaTile(item: m)),
            ],

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
    final color = _statusColors[item.status] ?? Colors.grey;
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

// ── Error banner ──────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(error,
                  style: TextStyle(
                      color: Colors.red.shade800,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: Colors.red.shade400,
              onPressed: () => context.read<AppState>().clearError(),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Requested action banner ──────────────────────────────────────────────

class _RequestedActionBanner extends StatelessWidget {
  const _RequestedActionBanner({required this.action});
  final RequestedAction action;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String label, String buttonLabel) = switch (action) {
      RequestedAction.capturePhoto => (
        Icons.camera_alt,
        'Agent requests a photo of this area',
        'Take Photo',
      ),
      RequestedAction.captureVideo => (
        Icons.videocam,
        'Agent requests a video of this area',
        'Record',
      ),
      RequestedAction.confirmOkReviewCritical => (
        Icons.checklist,
        'Confirm the status of this inspection point',
        '',
      ),
      RequestedAction.none => (Icons.abc, '', ''),
    };

    return Card(
      color: const Color(0xFFE3F2FD),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF1565C0), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: Color(0xFF1565C0),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            if (buttonLabel.isNotEmpty)
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  final state = context.read<AppState>();
                  if (action == RequestedAction.capturePhoto) {
                    state.capturePhoto();
                  } else if (action == RequestedAction.captureVideo) {
                    state.captureVideo();
                  }
                  state.dismissPendingAction();
                },
                child: Text(buttonLabel),
              ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: const Color(0xFF1565C0),
              onPressed: () =>
                  context.read<AppState>().dismissPendingAction(),
              visualDensity: VisualDensity.compact,
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    if (state.availableReports.isEmpty) {
      state.loadAvailableReports();
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send(AppState state) {
    final q = _inputCtrl.text.trim();
    if (q.isEmpty || state.reportsBusy) return;
    _inputCtrl.clear();
    state.runReportsQuery(q).then((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Column(
        children: [
          // ── 1. Available Reports (always visible) ────────────────────────
          if (state.availableReports.isNotEmpty)
            _AvailableReportsSection(reports: state.availableReports),

          // ── 2. Chat history ──────────────────────────────────────────────
          Expanded(
            child: state.chatMessages.isEmpty
                ? const _EmptyHistory()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: state.chatMessages.length,
                    itemBuilder: (_, i) =>
                        _ChatBubble(msg: state.chatMessages[i]),
                  ),
          ),

          // ── 4. Input bar ─────────────────────────────────────────────────
          _InputBar(
            controller: _inputCtrl,
            busy: state.reportsBusy,
            onSend: () => _send(state),
          ),
        ],
      ),
    );
  }
}

// ── Available reports (always visible) ─────────────────────────────────────

class _AvailableReportsSection extends StatelessWidget {
  const _AvailableReportsSection({required this.reports});
  final List<ReportSummary> reports;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: reports.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _ReportCard(summary: reports[i]),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final dateStr =
        '${summary.date.year}-${summary.date.month.toString().padLeft(2, '0')}-'
        '${summary.date.day.toString().padLeft(2, '0')}';

    return SizedBox(
      width: 220,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => state.downloadReport({
            'machine': {
              'model': summary.machineId,
              'serial_number': summary.reportId,
            },
            'date_generated': dateStr,
            'summary': summary.summaryLine,
          }),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.picture_as_pdf, size: 18, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        summary.reportId,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(summary.machineId,
                    style: Theme.of(context).textTheme.labelSmall),
                Text(dateStr,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
                const Spacer(),
                Text(
                  summary.summaryLine,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chat history ───────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.msg});
  final ChatMessage msg;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == ChatRole.user;
    final cs = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(msg.text,
            style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No conversation yet.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}

// ── Input bar ──────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar(
      {required this.controller,
      required this.busy,
      required this.onSend});
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !busy,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Ask about past inspections…',
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  isDense: true,
                  suffixIcon: busy
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
              onPressed: busy ? null : onSend,
            ),
          ],
        ),
      ),
    );
  }
}

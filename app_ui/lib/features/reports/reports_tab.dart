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
          // ── 1. Query Results ─────────────────────────────────────────────
          if (state.reportsQueryResults.isNotEmpty)
            _QueryResultsRow(results: state.reportsQueryResults),

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

// ── Query results horizontal scroll ───────────────────────────────────────

class _QueryResultsRow extends StatelessWidget {
  const _QueryResultsRow({required this.results});
  final List<ReportSummary> results;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 148,
      child: results.isEmpty
          ? Center(
              child: Text(
                'Search results will appear here.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline),
              ),
            )
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: results.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _ResultCard(summary: results[i]),
            ),
    );
  }
}

class _ResultCard extends StatefulWidget {
  const _ResultCard({required this.summary});
  final ReportSummary summary;

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _downloading = false;

  Future<void> _downloadPdf() async {
    setState(() => _downloading = true);
    try {
      final s = widget.summary;
      final state = context.read<AppState>();
      final report = state.liveReport;

      // Build payload matching the backend /load-inspection schema.
      final payload = <String, dynamic>{
        'machine': {
          'model': 'CAT 950',
          'serial_number': s.machineId,
        },
        'date_generated':
            '${s.date.year}-${s.date.month.toString().padLeft(2, '0')}-${s.date.day.toString().padLeft(2, '0')}',
        'general_comments': s.summaryLine,
        'sections': <String, dynamic>{},
      };

      // Populate sections from live report findings if available.
      if (report != null && report.findings.isNotEmpty) {
        final items = report.findings
            .map((f) => {
                  'component': f.title,
                  'status': f.severity == FindingSeverity.ok
                      ? 'PASS'
                      : f.severity == FindingSeverity.review
                          ? 'MONITOR'
                          : 'FAIL',
                  'comments': f.detail,
                })
            .toList();
        payload['sections'] = {'Inspection_Findings': items};
      }

      await state.downloadReportPdf(payload);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final dateStr =
        '${summary.date.year}-${summary.date.month.toString().padLeft(2, '0')}-'
        '${summary.date.day.toString().padLeft(2, '0')}';

    return SizedBox(
      width: 220,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.description_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      summary.reportId,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_downloading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    GestureDetector(
                      onTap: _downloadPdf,
                      child: const Icon(Icons.download, size: 18),
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

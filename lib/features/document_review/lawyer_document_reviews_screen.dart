import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/document_review.dart';
import '../../services/document_review_service.dart';
import 'review_screens.dart' show openReviewDocument;

/// The lawyer's side of Advocate Document Opinion: the documents an admin has
/// assigned to them, each opened in the phone's viewer and answered with a
/// written opinion. Their share of the fee is credited the moment it is sent.
class LawyerDocumentReviewsScreen extends StatefulWidget {
  const LawyerDocumentReviewsScreen({super.key});

  @override
  State<LawyerDocumentReviewsScreen> createState() => _LawyerDocumentReviewsScreenState();
}

class _LawyerDocumentReviewsScreenState extends State<LawyerDocumentReviewsScreen> {
  List<DocumentReview>? _reviews;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await context.read<DocumentReviewService>().assignedToMe();
      if (mounted) {
        setState(() {
          _reviews = rows;
          _error = '';
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _write(DocumentReview r) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (_) => Provider.value(
        value: context.read<DocumentReviewService>(),
        child: _ReportSheet(review: r),
      ),
    );
    if (sent == true) {
      if (mounted) Toast.success(context, 'Opinion sent to the client. Your earning has been credited.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _reviews;
    final open = rows?.where((r) => r.status != 'delivered' && r.status != 'cancelled').toList() ?? const [];
    final done = rows?.where((r) => r.status == 'delivered').toList() ?? const [];

    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(title: const Text('Document opinions')),
      body: _error.isNotEmpty && rows == null
          ? ErrorView(message: _error, onRetry: _load)
          : rows == null
              ? const LoadingView(label: 'Loading assigned documents…')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: rows.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 80),
                            EmptyView(
                              icon: Icons.assignment_outlined,
                              title: 'No documents assigned yet',
                              message: 'When a client asks for an Advocate Document Opinion in your area, '
                                  'our team assigns it to you and it appears here.',
                            ),
                          ],
                        )
                      : ListView(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomGutter(context)),
                          children: [
                            if (open.isNotEmpty) ...[
                              _heading('Waiting for your opinion (${open.length})'),
                              for (final r in open) _LawyerReviewCard(review: r, onWrite: () => _write(r)),
                            ],
                            if (done.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _heading('Sent (${done.length})'),
                              for (final r in done) _LawyerReviewCard(review: r),
                            ],
                          ],
                        ),
                ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      );
}

class _LawyerReviewCard extends StatefulWidget {
  const _LawyerReviewCard({required this.review, this.onWrite});
  final DocumentReview review;
  final VoidCallback? onWrite;

  @override
  State<_LawyerReviewCard> createState() => _LawyerReviewCardState();
}

class _LawyerReviewCardState extends State<_LawyerReviewCard> {
  bool _showReport = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final delivered = r.status == 'delivered';
    final due = r.assignedAt?.add(const Duration(hours: 24));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: delivered ? AppColors.border : AppColors.accent.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.fileName.isEmpty ? 'Document' : r.fileName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              ),
              Text(
                delivered ? 'Earned ${Fmt.money(r.earning)}' : Fmt.money(r.amount),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: delivered ? const Color(0xFF047857) : AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            [
              if (r.userName.isNotEmpty) r.userName,
              r.areaLabel.split(' (').first,
              '${r.pages} ${r.pages == 1 ? 'page' : 'pages'}',
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
          if (r.question.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(10)),
              child: Text('Client asks: “${r.question}”', style: const TextStyle(fontSize: 13, height: 1.4)),
            ),
          ],
          if (!delivered && due != null) ...[
            const SizedBox(height: 8),
            Text('Due by ${Fmt.dateTime(due)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.warning)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: r.hasFile ? () => openReviewDocument(context, r) : null,
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: const Text('Open document'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: delivered
                    ? OutlinedButton.icon(
                        onPressed: () => setState(() => _showReport = !_showReport),
                        icon: Icon(_showReport ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
                        label: Text(_showReport ? 'Hide opinion' : 'My opinion'),
                      )
                    : FilledButton.icon(
                        onPressed: widget.onWrite,
                        icon: const Icon(Icons.edit_note_rounded, size: 18),
                        label: const Text('Write opinion'),
                      ),
              ),
            ],
          ),
          if (delivered && _showReport) ...[
            const SizedBox(height: 10),
            SelectableText(r.report, style: const TextStyle(fontSize: 13.5, height: 1.55)),
          ],
        ],
      ),
    );
  }
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.review});
  final DocumentReview review;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const _min = 40;
  final _text = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await context.read<DocumentReviewService>().sendReport(widget.review.id, _text.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = _min - _text.text.trim().length;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Your written opinion', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'The client reads this exactly as written. Cover the risks, what to change, and whether it is safe to sign.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 8,
            maxLines: 16,
            maxLength: 20000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: '1. Summary…\n2. Risky clauses…\n3. What to change…\n4. My advice…',
              alignLabelWithHint: true,
            ),
          ),
          if (_error.isNotEmpty) ...[
            NoticeBanner(message: _error, tone: ChipTone.danger, icon: Icons.error_outline_rounded),
            const SizedBox(height: 8),
          ],
          PrimaryButton(
            label: left > 0 ? 'Write $left more characters' : 'Send opinion to client',
            busy: _busy,
            onPressed: left > 0 || _busy ? null : _send,
          ),
        ],
      ),
    );
  }
}

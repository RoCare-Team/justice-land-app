import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/document_review.dart';
import '../../services/document_review_service.dart';
import '../../state/auth_controller.dart';

/// Opens the uploaded document in the phone's viewer through its signed link —
/// the app's sign-in cookie does not travel with it, the signature does.
Future<void> openReviewDocument(BuildContext context, DocumentReview r) async {
  if (r.signedFileUrl.isEmpty) {
    Toast.error(context, 'The document is no longer stored.');
    return;
  }
  final url = r.signedFileUrl.startsWith('http') ? r.signedFileUrl : '${AppConfig.baseUrl}${r.signedFileUrl}';
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) Toast.error(context, 'Could not open the document.');
}

({String label, Color fg, Color bg}) riskStyle(String level) => switch (level) {
      'high' => (label: 'High risk', fg: AppColors.danger, bg: AppColors.dangerSoft),
      'medium' => (label: 'Medium risk', fg: AppColors.warning, bg: AppColors.warningSoft),
      'low' => (label: 'Low risk', fg: const Color(0xFF047857), bg: AppColors.successSoft),
      _ => (label: 'Checked', fg: AppColors.primary, bg: AppColors.muted),
    };

({Color fg, Color bg}) statusStyle(DocumentReview r) => r.isReady
    ? (fg: const Color(0xFF047857), bg: AppColors.successSoft)
    : r.status == 'cancelled'
        ? (fg: AppColors.danger, bg: AppColors.dangerSoft)
        : (fg: AppColors.warning, bg: AppColors.warningSoft);

/* ════════════════════════════════════════════════════════════════════════ */
/*  My document reviews                                                     */
/* ════════════════════════════════════════════════════════════════════════ */

class MyDocumentReviewsScreen extends StatefulWidget {
  const MyDocumentReviewsScreen({super.key});

  @override
  State<MyDocumentReviewsScreen> createState() => _MyDocumentReviewsScreenState();
}

class _MyDocumentReviewsScreenState extends State<MyDocumentReviewsScreen> {
  List<DocumentReview>? _reviews;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await context.read<DocumentReviewService>().overview();
      if (mounted) {
        setState(() {
          _reviews = o.reviews;
          _error = '';
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = context.watch<AuthController>().isUser;
    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(title: const Text('My document reviews')),
      floatingActionButton: signedIn
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/document-review'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Check a document'),
            )
          : null,
      body: !signedIn
          ? EmptyView(
              icon: Icons.lock_outline_rounded,
              title: 'Sign in to see your reviews',
              action: PrimaryButton(
                label: 'Sign in',
                expand: false,
                onPressed: () => context.push('/login?redirect=/document-reviews'),
              ),
            )
          : _error.isNotEmpty && _reviews == null
              ? ErrorView(message: _error, onRetry: _load)
              : _reviews == null
                  ? const LoadingView(label: 'Loading your reviews…')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _reviews!.isEmpty
                          ? ListView(
                              children: [
                                const SizedBox(height: 60),
                                EmptyView(
                                  icon: Icons.description_outlined,
                                  title: 'No documents checked yet',
                                  message: 'Have an agreement, notice or deed checked by AI in two minutes, '
                                      'or get a written opinion from an advocate.',
                                  action: PrimaryButton(
                                    label: 'Check a document',
                                    expand: false,
                                    onPressed: () => context.push('/document-review'),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: EdgeInsets.fromLTRB(16, 12, 16, bottomGutter(context, 90)),
                              itemCount: _reviews!.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) => _ReviewTile(review: _reviews![i]),
                            ),
                    ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final DocumentReview review;

  @override
  Widget build(BuildContext context) {
    final r = review;
    final st = statusStyle(r);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/document-reviews/${r.id}'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: r.isAi ? const Color(0xFF10B981) : const Color(0xFFF97316),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(r.isAi ? Icons.document_scanner_rounded : Icons.assignment_turned_in_rounded,
                    color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.fileName.isEmpty ? r.productName : r.fileName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${r.productName} · ${Fmt.money(r.amount)} · ${Fmt.date(r.createdAt)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(20)),
                      child: Text(r.statusLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: st.fg)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════ */
/*  One review: the AI's findings or the advocate's opinion                 */
/* ════════════════════════════════════════════════════════════════════════ */

class DocumentReviewDetailScreen extends StatefulWidget {
  const DocumentReviewDetailScreen({super.key, required this.reviewId});
  final String reviewId;

  @override
  State<DocumentReviewDetailScreen> createState() => _DocumentReviewDetailScreenState();
}

class _DocumentReviewDetailScreenState extends State<DocumentReviewDetailScreen> {
  DocumentReview? _review;
  String _error = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      // Opening a paid AI review runs its read if it has not run — this call
      // can take up to a minute, which the loading screen says.
      final r = await context.read<DocumentReviewService>().read(widget.reviewId);
      if (mounted) setState(() => _review = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _review;
    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(
        title: Text(r?.productName ?? 'Document review'),
        actions: [
          if (r != null && r.hasFile)
            IconButton(
              tooltip: 'View my document',
              onPressed: () => openReviewDocument(context, r),
              icon: const Icon(Icons.description_outlined),
            ),
        ],
      ),
      body: _loading && r == null
          ? const _ReadingView()
          : r == null
              ? ErrorView(message: _error.isEmpty ? 'This review could not be opened.' : _error, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, bottomGutter(context)),
                    children: [
                      _header(r),
                      const SizedBox(height: 14),
                      if (r.isAi) ..._aiBody(r) else ..._expertBody(r),
                      const SizedBox(height: 18),
                      _OutlinedAction(
                        icon: Icons.support_agent_rounded,
                        label: 'Talk to a lawyer about this document',
                        onTap: () => context.go('/lawyers'),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _header(DocumentReview r) {
    final st = statusStyle(r);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primaryLight, AppColors.primaryDark]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.fileName.isEmpty ? 'Your document' : r.fileName,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(20)),
                child: Text(r.statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: st.fg)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${r.areaLabel.split(' (').first} · ${r.pages} ${r.pages == 1 ? 'page' : 'pages'} · ${Fmt.money(r.amount)} paid',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          if (r.question.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('“${r.question}”',
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  List<Widget> _aiBody(DocumentReview r) {
    final ai = r.ai;
    if (ai == null || r.aiPending) {
      return [
        _Card(
          child: Column(
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 34, color: AppColors.warning),
              const SizedBox(height: 10),
              Text(
                ai?.error.isNotEmpty ?? false ? 'The check did not finish' : 'Your document is being read',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                ai?.error.isNotEmpty ?? false
                    ? 'Something went wrong while reading it. Try again — you will not be charged twice.'
                    : 'This usually takes under a minute.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkMuted, height: 1.4),
              ),
              const SizedBox(height: 14),
              PrimaryButton(label: 'Check again', busy: _loading, expand: false, onPressed: _load),
            ],
          ),
        ),
      ];
    }

    final risk = riskStyle(ai.riskLevel);
    return [
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: risk.bg, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined, size: 15, color: risk.fg),
                      const SizedBox(width: 5),
                      Text(risk.label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: risk.fg)),
                    ],
                  ),
                ),
                const Spacer(),
                if (ai.documentType.isNotEmpty)
                  Flexible(
                    child: Text(ai.documentType,
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
                  ),
              ],
            ),
            if (ai.summary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(ai.summary, style: const TextStyle(fontSize: 14, height: 1.55)),
            ],
          ],
        ),
      ),
      if (ai.redFlags.isNotEmpty)
        _Section(
          icon: Icons.flag_rounded,
          color: AppColors.danger,
          title: 'Red flags (${ai.redFlags.length})',
          children: [for (final f in ai.redFlags) _FlagRow(flag: f)],
        ),
      if (ai.missingClauses.isNotEmpty)
        _Section(
          icon: Icons.playlist_add_rounded,
          color: AppColors.warning,
          title: 'Missing clauses (${ai.missingClauses.length})',
          children: [for (final f in ai.missingClauses) _FlagRow(flag: f, plain: true)],
        ),
      if (ai.keyTerms.isNotEmpty)
        _Section(
          icon: Icons.key_rounded,
          color: AppColors.primary,
          title: 'Key terms',
          children: [
            for (final t in ai.keyTerms)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(t.label, style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Text(t.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      if (ai.suggestions.isNotEmpty)
        _Section(
          icon: Icons.lightbulb_outline_rounded,
          color: const Color(0xFF059669),
          title: 'What to do',
          children: [
            for (final s in ai.suggestions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF059669)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s, style: const TextStyle(fontSize: 13.5, height: 1.45))),
                  ],
                ),
              ),
          ],
        ),
      const SizedBox(height: 12),
      Text(
        'This is an automated check to help you spot problems — not legal advice. '
        'For an opinion you can rely on, ask an advocate.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11.5, height: 1.45, color: AppColors.inkFaint),
      ),
      const SizedBox(height: 10),
      _OutlinedAction(
        icon: Icons.assignment_turned_in_rounded,
        label: 'Get an Advocate Document Opinion',
        onTap: () => context.push('/document-review?kind=expert'),
      ),
    ];
  }

  List<Widget> _expertBody(DocumentReview r) {
    final steps = [
      (label: 'Paid', done: r.status != 'pending', at: r.paidAt),
      (label: 'Advocate assigned', done: r.status == 'assigned' || r.status == 'delivered', at: r.assignedAt),
      (label: 'Opinion sent', done: r.status == 'delivered', at: r.deliveredAt),
    ];
    return [
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Icon(steps[i].done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 20, color: steps[i].done ? AppColors.success : AppColors.inkFaint),
                      if (i < steps.length - 1)
                        Container(width: 2, height: 22, color: steps[i].done ? AppColors.success : AppColors.border),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        steps[i].label +
                            (i == 1 && r.advocateName.isNotEmpty ? ' · ${r.advocateName}' : '') +
                            (steps[i].at != null ? '  —  ${Fmt.date(steps[i].at)}' : ''),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: steps[i].done ? AppColors.ink : AppColors.inkFaint,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            if (r.status != 'delivered') ...[
              const SizedBox(height: 8),
              Text(
                'An advocate sends a written opinion within 24 hours of payment. '
                'Pull down to refresh and see it here.',
                style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.inkMuted),
              ),
            ],
          ],
        ),
      ),
      if (r.report.isNotEmpty)
        _Section(
          icon: Icons.gavel_rounded,
          color: AppColors.primary,
          title: r.advocateName.isEmpty ? 'Advocate’s opinion' : 'Opinion by ${r.advocateName}',
          children: [
            SelectableText(r.report, style: const TextStyle(fontSize: 14, height: 1.6)),
          ],
        ),
    ];
  }
}

class _ReadingView extends StatelessWidget {
  const _ReadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 42, width: 42, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 18),
            const Text('Opening your review…', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              'If the AI is still reading your document this can take up to a minute. Please keep the app open.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkMuted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.color, required this.title, required this.children});
  final IconData icon;
  final Color color;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 19, color: color),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.flag, this.plain = false});
  final ReviewFlag flag;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final sev = riskStyle(flag.severity);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: plain ? AppColors.muted : sev.bg.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(flag.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
              if (!plain && flag.severity.isNotEmpty)
                Text(flag.severity.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: sev.fg)),
            ],
          ),
          if (flag.detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(flag.detail, style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.inkMuted)),
          ],
        ],
      ),
    );
  }
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/legal_query.dart';
import '../../state/queries_controller.dart';
import 'lawyer_widgets.dart';

/// Client Queries — legal problems posted from the website and the app by
/// people without an account, shared by every lawyer on a paid plan until one
/// takes them.
///
/// Mirrors the website's portal page: a credit meter, then Open / My queries /
/// Resolved. On Starter the pool is locked and the page says what a plan opens.
class LawyerQueriesScreen extends StatefulWidget {
  const LawyerQueriesScreen({super.key});

  @override
  State<LawyerQueriesScreen> createState() => _LawyerQueriesScreenState();
}

class _LawyerQueriesScreenState extends State<LawyerQueriesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  String _category = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<QueriesController>().refresh();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _claim(LegalQuery q) async {
    final queries = context.read<QueriesController>();
    try {
      await queries.claim(q.id);
      if (!mounted) return;
      Toast.success(context, 'Query taken. The client’s number is in My queries.');
      _tabs.animateTo(1);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'no_plan' || e.code == 'no_credits') {
        _showUpgrade(e.message);
      } else {
        Toast.error(context, e.message);
      }
    }
  }

  Future<void> _release(LegalQuery q) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Release this query?'),
        content: const Text(
          'It goes back to the pool for another lawyer. The credit you used is not returned.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Release')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<QueriesController>().release(q.id);
      if (mounted) Toast.show(context, 'Released. Another lawyer can take it now.');
    } on ApiException catch (e) {
      if (mounted) Toast.error(context, e.message);
    }
  }

  Future<void> _resolve(LegalQuery q) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as resolved'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'It leaves the pool for good — no lawyer will see it again.',
              style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'What came of it? (optional)',
                helperText: 'Only you see this.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Mark resolved')),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (ok != true || !mounted) return;
    try {
      await context.read<QueriesController>().resolve(q.id, note: text);
      if (!mounted) return;
      Toast.success(context, 'Marked resolved. It is off every lawyer’s list.');
      _tabs.animateTo(2);
    } on ApiException catch (e) {
      if (mounted) Toast.error(context, e.message);
    }
  }

  void _showUpgrade(String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.workspace_premium_rounded, color: AppColors.accent, size: 36),
        title: const Text('Query credits'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Not now')),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.push('/lawyer/plan');
            },
            child: const Text('See plans'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final queries = context.watch<QueriesController>();
    final board = queries.board;
    final open = _category.isEmpty ? board.open : board.open.where((q) => q.category == _category).toList();

    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(
        title: const Text('Client Queries'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          indicatorColor: AppColors.accent,
          tabs: [
            Tab(text: 'Open (${queries.openCount})'),
            Tab(text: 'Mine (${board.mine.length})'),
            Tab(text: 'Resolved (${board.resolved.length})'),
          ],
        ),
      ),
      body: !queries.loaded && queries.loading
          ? const SkeletonList(count: 4, height: 150)
          : !queries.loaded && queries.error != null
              ? ErrorView(
                  message: queries.error!.message,
                  isNetwork: queries.error!.isNetwork,
                  onRetry: queries.refresh,
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _list(
                      header: [
                        if (!board.locked) _CreditsCard(credits: board.credits),
                        if (!board.locked && board.categories.length > 1) _categoryFilter(board.categories),
                      ],
                      items: board.locked ? const [] : open,
                      tab: _Tab.open,
                      locked: board.locked,
                      waiting: board.openTotal,
                      canClaim: board.credits.left > 0,
                    ),
                    _list(items: board.mine, tab: _Tab.mine),
                    _list(items: board.resolved, tab: _Tab.resolved),
                  ],
                ),
    );
  }

  Widget _categoryFilter(List<String> categories) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in ['', ...categories])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c.isEmpty ? 'All' : c),
                selected: _category == c,
                showCheckmark: false,
                onSelected: (_) => setState(() => _category = c),
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _category == c ? Colors.white : AppColors.ink,
                ),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surface,
                side: BorderSide(color: _category == c ? AppColors.primary : AppColors.border),
                shape: const StadiumBorder(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _list({
    required List<LegalQuery> items,
    required _Tab tab,
    List<Widget> header = const [],
    bool locked = false,
    int waiting = 0,
    bool canClaim = true,
  }) {
    final queries = context.read<QueriesController>();
    return RefreshIndicator(
      onRefresh: queries.refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 14, 16, bottomGutter(context)),
        children: [
          for (final h in header) ...[h, const SizedBox(height: 12)],
          if (locked)
            _LockedPool(waiting: waiting)
          else if (items.isEmpty)
            EmptyCard(
              icon: switch (tab) {
                _Tab.open => Icons.inbox_outlined,
                _Tab.mine => Icons.volunteer_activism_outlined,
                _Tab.resolved => Icons.task_alt_rounded,
              },
              title: switch (tab) {
                _Tab.open => 'No open queries right now',
                _Tab.mine => 'You have not taken any query',
                _Tab.resolved => 'Nothing resolved yet',
              },
              message: switch (tab) {
                _Tab.open => 'New legal problems appear here for every lawyer on a plan. Pull down to check again.',
                _Tab.mine => 'Take a query from the Open tab and the client’s number appears here.',
                _Tab.resolved => 'Queries you finish are kept here for your records.',
              },
            )
          else
            for (final q in items) ...[
              _QueryCard(
                query: q,
                tab: tab,
                busy: queries.isBusy(q.id),
                canClaim: canClaim,
                onClaim: () => _claim(q),
                onRelease: () => _release(q),
                onResolve: () => _resolve(q),
              ),
              const SizedBox(height: 12),
            ],
          if (tab == _Tab.open && !locked) ...[
            const SizedBox(height: 4),
            const NoticeBanner(
              tone: ChipTone.neutral,
              icon: Icons.info_outline_rounded,
              message:
                  'Only one lawyer can take a query, and taking it uses 1 credit. It then disappears for everyone else. Releasing a query does not return the credit.',
            ),
          ],
        ],
      ),
    );
  }
}

enum _Tab { open, mine, resolved }

/// "7 of 10 query credits left · renews on 16 Oct"
class _CreditsCard extends StatelessWidget {
  const _CreditsCard({required this.credits});

  final QueryCredits credits;

  @override
  Widget build(BuildContext context) {
    final empty = credits.left == 0;
    final fraction = credits.allowance == 0 ? 0.0 : credits.left / credits.allowance;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: empty ? AppColors.warningSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: empty ? AppColors.warning.withValues(alpha: 0.3) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: empty ? AppColors.warning.withValues(alpha: 0.12) : AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.toll_rounded, color: empty ? AppColors.warning : AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${credits.left}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        TextSpan(text: ' of ${credits.allowance}', style: TextStyle(fontSize: 14, color: AppColors.inkFaint)),
                        const TextSpan(text: '  query credits left', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    Text(
                      '${credits.planName} plan · 1 credit = 1 query'
                      '${credits.resetsAt != null ? ' · renews ${Fmt.date(credits.resetsAt)}' : ''}',
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 7,
              backgroundColor: AppColors.ink.withValues(alpha: 0.08),
              color: empty ? AppColors.warning : AppColors.success,
            ),
          ),
          if (empty) ...[
            const SizedBox(height: 10),
            Text(
              'You have used this month’s credits. You can take queries again'
              '${credits.resetsAt != null ? ' from ${Fmt.date(credits.resetsAt)}' : ' next month'}.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.warning),
            ),
          ],
          if (!credits.isTopPlan)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push('/lawyer/plan'),
                icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                label: const Text('Get 25 a month with Premium'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Starter: the count, and the way to unlock it.
class _LockedPool extends StatelessWidget {
  const _LockedPool({required this.waiting});

  final int waiting;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryLight, AppColors.primaryDark],
              ),
            ),
            child: Column(
              children: [
                Container(
                  height: 56,
                  width: 56,
                  decoration: const BoxDecoration(color: Colors.white12, shape: BoxShape.circle),
                  child: const Icon(Icons.lock_outline_rounded, color: AppColors.accent, size: 26),
                ),
                const SizedBox(height: 12),
                Text(
                  waiting > 0
                      ? '$waiting client ${waiting == 1 ? 'query is' : 'queries are'} waiting'
                      : 'Get client queries',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: AppText.display, fontSize: 21, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 6),
                const Text(
                  'People post their legal problem on Justiceland and a lawyer calls them. Queries are shown only to lawyers on a paid plan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.45, color: Colors.white70),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _point(Icons.toll_rounded, 'Professional: 10 query credits every month'),
                _point(Icons.workspace_premium_rounded, 'Premium: 25 query credits every month'),
                _point(Icons.phone_in_talk_outlined, '1 credit = 1 query — you get the client’s name and number, nobody else does'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () => context.push('/lawyer/plan'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: const Color(0xFF241B02),
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    icon: const Icon(Icons.workspace_premium_rounded, size: 20),
                    label: const Text('Upgrade to take queries'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _point(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.4))),
        ],
      ),
    );
  }
}

class _QueryCard extends StatelessWidget {
  const _QueryCard({
    required this.query,
    required this.tab,
    required this.busy,
    required this.canClaim,
    required this.onClaim,
    required this.onRelease,
    required this.onResolve,
  });

  final LegalQuery query;
  final _Tab tab;
  final bool busy;
  final bool canClaim;
  final VoidCallback onClaim;
  final VoidCallback onRelease;
  final VoidCallback onResolve;

  Future<void> _launch(Uri uri) async {
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final q = query;
    final phoneDigits = q.phone.replaceAll(RegExp(r'\D'), '');
    final local = phoneDigits.length > 10 ? phoneDigits.substring(phoneDigits.length - 10) : phoneDigits;

    return LCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                child: Text(
                  Fmt.initial(q.displayName),
                  style: const TextStyle(fontFamily: AppText.display, fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            tab == _Tab.open ? (q.askedBy.isEmpty ? 'Client' : q.askedBy) : q.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (tab == _Tab.open) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(999)),
                            child: Text('Contact hidden', style: TextStyle(fontSize: 10.5, color: AppColors.inkFaint)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (q.category.isNotEmpty)
                          Text(q.category, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                        if (q.city.isNotEmpty) _meta(Icons.location_on_outlined, q.city),
                        _meta(Icons.schedule_rounded, q.age.isNotEmpty ? q.age : Fmt.timeAgo(q.createdAt)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(12)),
            child: Text(q.message, style: const TextStyle(fontSize: 13.5, height: 1.5)),
          ),
          const SizedBox(height: 12),
          if (tab == _Tab.open) ...[
            Text(
              '${q.phoneMasked} · the full number is shown once you take this query.',
              style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: busy || !canClaim ? null : onClaim,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                icon: busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : const Icon(Icons.volunteer_activism_rounded, size: 18),
                label: Text(canClaim ? 'Take this query · 1 credit' : 'No credits left this month'),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: local.isEmpty ? null : () => _launch(Uri(scheme: 'tel', path: '+91$local')),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: Text(local.isEmpty ? 'No number' : Fmt.phone(local)),
                  ),
                ),
                if (q.email.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: q.email,
                    onPressed: () => _launch(Uri(scheme: 'mailto', path: q.email)),
                    icon: const Icon(Icons.mail_outline_rounded, size: 20),
                  ),
                ],
                if (local.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'WhatsApp',
                    onPressed: () => launchUrl(Uri.parse('https://wa.me/91$local'), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.chat_outlined, size: 20, color: Color(0xFF25D366)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            if (tab == _Tab.mine)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : onResolve,
                      icon: busy
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.task_alt_rounded, size: 18),
                      label: const Text('Mark resolved'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: busy ? null : onRelease,
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: const Text('Release'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  const Icon(Icons.task_alt_rounded, size: 16, color: AppColors.success),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Resolved ${Fmt.date(q.resolvedAt)}${q.resolutionNote.isNotEmpty ? ' · ${q.resolutionNote}' : ''}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.success),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.inkFaint),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/consultation.dart';
import '../../services/consultation_service.dart';
import '../../state/auth_controller.dart';

/// Every consultation the signed-in person is part of, split three ways.
///
/// One call to `GET /api/consultations?scope=mine` and one server-side rule
/// about whose history it is: a client sees the sessions they booked, a lawyer
/// the ones they took. The tabs are only a reading of `status`, not three
/// different requests — the same list sorted into what has not started, what is
/// running now, and what is done.
class ConsultationsScreen extends StatefulWidget {
  const ConsultationsScreen({super.key, this.initialTab = 'active'});

  /// 'upcoming' | 'active' | 'completed'
  final String initialTab;

  @override
  State<ConsultationsScreen> createState() => _ConsultationsScreenState();
}

enum _Bucket {
  upcoming('Upcoming'),
  active('Active'),
  completed('Completed');

  const _Bucket(this.label);
  final String label;

  static _Bucket parse(String value) => _Bucket.values.firstWhere(
        (b) => b.name == value,
        orElse: () => _Bucket.active,
      );
}

class _ConsultationsScreenState extends State<ConsultationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: _Bucket.values.length,
    vsync: this,
    initialIndex: _Bucket.parse(widget.initialTab).index,
  );

  List<Consultation> _all = [];
  bool _loading = true;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!context.read<AuthController>().isSignedIn) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<ConsultationService>().history();
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// A pending request is "upcoming": it has been sent and the lawyer has not
  /// accepted it yet, so there is nothing to join and nothing has been charged.
  List<Consultation> _bucketed(_Bucket bucket) => _all.where((c) {
        return switch (bucket) {
          _Bucket.upcoming => c.status.isWaiting,
          _Bucket.active => c.status.isLive,
          _Bucket.completed => c.status.isOver,
        };
      }).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Consultations'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.inkMuted,
          indicatorColor: AppColors.primary,
          tabs: [
            for (final bucket in _Bucket.values)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(bucket.label),
                    // The count is on the tab because the whole point of the
                    // split is knowing which one has something in it without
                    // opening all three.
                    if (!_loading && _bucketed(bucket).isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_bucketed(bucket).length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
      body: !auth.isSignedIn
          ? EmptyView(
              icon: Icons.lock_outline_rounded,
              title: 'Sign in to see your consultations',
              message: 'Your chats, calls and video sessions live in your account.',
              action: FilledButton(
                onPressed: () => context.push('/login?redirect=/consultations'),
                child: const Text('Sign in'),
              ),
            )
          : TabBarView(
              controller: _tabs,
              children: [for (final b in _Bucket.values) _list(b)],
            ),
    );
  }

  Widget _list(_Bucket bucket) {
    if (_loading) return const SkeletonList(count: 4, height: 104);

    final error = _error;
    if (error != null) {
      return ErrorView(message: error.message, isNetwork: error.isNetwork, onRetry: _load);
    }

    final rows = _bucketed(bucket);
    if (rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(
              height: 380,
              child: EmptyView(
                icon: switch (bucket) {
                  _Bucket.upcoming => Icons.schedule_rounded,
                  _Bucket.active => Icons.forum_outlined,
                  _Bucket.completed => Icons.history_rounded,
                },
                title: switch (bucket) {
                  _Bucket.upcoming => 'Nothing waiting',
                  _Bucket.active => 'Nothing running right now',
                  _Bucket.completed => 'No past consultations',
                },
                message: switch (bucket) {
                  _Bucket.upcoming =>
                    'A request appears here until the lawyer accepts it. Nothing is charged while it waits.',
                  _Bucket.active =>
                    'Start one from a lawyer’s profile — chat, call or video.',
                  _Bucket.completed =>
                    'Finished consultations stay here with what each one cost.',
                },
                action: bucket == _Bucket.active
                    ? FilledButton(
                        onPressed: () => context.go('/lawyers'),
                        child: const Text('Find a lawyer'),
                      )
                    : null,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomGutter(context)),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => ConsultationTile(session: rows[i]),
      ),
    );
  }
}

/// One consultation, as a row.
///
/// Shared by this screen and the home screen's "continue where you left off"
/// band so a session cannot look like two different things in two places.
class ConsultationTile extends StatelessWidget {
  const ConsultationTile({super.key, required this.session, this.showOtherSide = true});

  final Consultation session;

  /// Whose name to print. A client wants the lawyer's; on a lawyer's own screen
  /// this is turned off, because their entire list would read as their own name.
  final bool showOtherSide;

  String get _route => switch (session.type) {
        ConsultationType.chat => '/consultation/${session.id}/chat',
        ConsultationType.video => '/consultation/${session.id}/video',
        ConsultationType.audio => '/consultation/${session.id}/audio',
      };

  @override
  Widget build(BuildContext context) {
    final live = session.status.isLive;
    final tone = switch (session.status) {
      ConsultationStatus.active => ChipTone.success,
      ConsultationStatus.pending => ChipTone.warning,
      ConsultationStatus.ended => ChipTone.info,
      _ => ChipTone.neutral,
    };

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(_route),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: live ? AppColors.success.withOpacity(0.45) : AppColors.border,
              width: live ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Avatar(
                name: showOtherSide ? session.advocateName : session.userName,
                photo: showOtherSide ? session.advocatePhoto : null,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showOtherSide ? session.advocateName : session.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          switch (session.type) {
                            ConsultationType.chat => Icons.chat_bubble_outline_rounded,
                            ConsultationType.audio => Icons.call_outlined,
                            ConsultationType.video => Icons.videocam_outlined,
                          },
                          size: 14,
                          color: AppColors.inkFaint,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          session.type.label,
                          style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                        ),
                        Text(
                          '  ·  ${Fmt.date(session.createdAt)}',
                          style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      session.isResume
                          ? 'Free resume'
                          : session.price > 0
                              ? '${Fmt.money(session.price)} · ${Fmt.pluralize(session.minutes, 'min')}'
                              : 'Not charged',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: session.price > 0 ? AppColors.inkStrong : AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusChip(label: live ? 'Active Now' : session.status.label, tone: tone),
                  const SizedBox(height: 8),
                  if (live)
                    Text(
                      'Join',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    )
                  else if (session.hasClaimableLeftover)
                    Text(
                      '${Fmt.leftover(session.resumeLeftoverSeconds)} left',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/account.dart';
import '../../models/consultation.dart';
import '../../services/consultation_service.dart';
import '../../services/dashboard_service.dart';
import '../../state/auth_controller.dart';

/// The lawyer's dashboard.
///
/// The inbox poll here is not just a refresh — calling it is the presence
/// heartbeat. A lawyer whose app is polling is a lawyer the platform will
/// offer to clients; stop polling and bookings start being refused as
/// "offline". That is why it keeps running while this screen is open.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.initialTab = 'inbox'});

  final String initialTab;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _tabNames = [
    'overview',
    'inbox',
    'consultations',
    'enquiries',
    'profile',
  ];

  late final TabController _tabs = TabController(
    length: _tabNames.length,
    vsync: this,
    // An unknown tab name opens the inbox, which is where a lawyer's day
    // actually starts — a request nobody sees is a client nobody answers.
    initialIndex: _tabNames.contains(widget.initialTab)
        ? _tabNames.indexOf(widget.initialTab)
        : _tabNames.indexOf('inbox'),
  );

  Timer? _poll;

  List<Consultation> _inbox = [];
  List<Consultation> _history = [];
  List<Enquiry> _enquiries = [];

  bool _loadingInbox = true;
  bool _loadingHistory = true;
  bool _loadingEnquiries = true;
  ApiException? _inboxError;

  bool _available = false;
  bool _togglingAvailability = false;

  @override
  void initState() {
    super.initState();
    _available = context.read<AuthController>().advocate?.available ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInbox();
      _loadHistory();
      _loadEnquiries();
      _poll = Timer.periodic(AppConfig.inboxPoll, (_) => _loadInbox(silent: true));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadInbox({bool silent = false}) async {
    if (!silent) setState(() => _loadingInbox = true);
    try {
      final list = await context.read<ConsultationService>().inbox();
      if (!mounted) return;
      setState(() {
        _inbox = list;
        _loadingInbox = false;
        _inboxError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingInbox = false;
        if (!silent) _inboxError = e;
      });
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final list = await context.read<ConsultationService>().history();
      if (!mounted) return;
      setState(() {
        _history = list;
        _loadingHistory = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  Future<void> _loadEnquiries() async {
    setState(() => _loadingEnquiries = true);
    try {
      final list = await context.read<DashboardService>().enquiries();
      if (!mounted) return;
      setState(() {
        _enquiries = list;
        _loadingEnquiries = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _loadingEnquiries = false);
    }
  }

  Future<void> _toggleAvailability(bool value) async {
    setState(() => _togglingAvailability = true);
    try {
      final result = await context.read<DashboardService>().setAvailable(value);
      if (!mounted) return;
      setState(() {
        _available = result;
        _togglingAvailability = false;
      });
      Toast.show(
        context,
        result
            ? 'You are online — clients can reach you.'
            : 'You are offline. New bookings will be refused until you switch back on.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _togglingAvailability = false);
      Toast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final advocate = auth.advocate;

    if (advocate == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        body: EmptyView(
          icon: Icons.lock_outline_rounded,
          title: 'Sign in as a lawyer',
          message: 'Your consultations and enquiries live here.',
          action: FilledButton(
            onPressed: () => context.push('/advocate/login'),
            child: const Text('Lawyer sign in'),
          ),
        ),
      );
    }

    final pending = _inbox.where((c) => c.status.isWaiting).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.inkMuted,
          indicatorColor: AppColors.primary,
          tabs: [
            const Tab(text: 'Overview'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Inbox'),
                  if (pending > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$pending',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Consultations'),
            const Tab(text: 'Enquiries'),
            const Tab(text: 'Profile'),
          ],
        ),
      ),
      body: Column(
        children: [
          _availabilityBar(advocate.status),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _overviewTab(),
                _inboxTab(),
                _historyTab(),
                _enquiriesTab(),
                _profileTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _availabilityBar(String status) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
      child: Column(
        children: [
          if (status != 'published')
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NoticeBanner(
                tone: ChipTone.warning,
                icon: Icons.schedule_rounded,
                message:
                    'Your profile is awaiting approval, so it is not in the public '
                    'directory yet. You can keep filling it in meanwhile.',
              ),
            ),
          Row(
            children: [
              Container(
                height: 9,
                width: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _available ? AppColors.success : AppColors.inkFaint,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _available
                      ? 'Online — clients can book you'
                      : 'Offline — bookings are being refused',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _available ? AppColors.success : AppColors.inkMuted,
                  ),
                ),
              ),
              if (_togglingAvailability)
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Switch.adaptive(
                  value: _available,
                  onChanged: _toggleAvailability,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The day at a glance, then the eight places a lawyer actually goes.
  ///
  /// Every figure here is counted from the consultations the server already
  /// sent — nothing is fetched twice and nothing is estimated. There is
  /// deliberately no "online time": the server does not record how long an
  /// availability switch has been on, and a number invented on the phone would
  /// be read as an earnings-adjacent fact. Pending requests take that slot,
  /// which is the thing a lawyer opening this screen most needs to know.
  Widget _overviewTab() {
    final today = DateTime.now();
    bool isToday(DateTime? d) =>
        d != null && d.year == today.year && d.month == today.month && d.day == today.day;

    final todays = _history.where((c) => isToday(c.createdAt)).toList();
    final earned = todays
        .where((c) => c.charged)
        .fold<int>(0, (sum, c) => sum + c.price);
    final pending = _inbox.where((c) => c.status.isWaiting).length;
    final active = _inbox.where((c) => c.status.isLive).length;
    final newEnquiries = _enquiries.where((e) => e.status == 'new').length;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_loadInbox(), _loadHistory(), _loadEnquiries()]);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomGutter(context)),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.secondary],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's Overview",
                  style: TextStyle(
                    fontFamily: AppText.display,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.92),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _overviewStat('${todays.length}', 'Consultations'),
                    _overviewDivider(),
                    _overviewStat(Fmt.money(earned), 'Earned'),
                    _overviewDivider(),
                    _overviewStat('$pending', 'Waiting'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // Without this the nested grid adopts the ambient MediaQuery
            // padding and opens a status-bar-sized gap above its first row.
            padding: EdgeInsets.zero,
            childAspectRatio: 0.86,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _dashTile(
                Icons.mark_email_unread_outlined,
                'Requests',
                badge: pending,
                onTap: () => _tabs.animateTo(_tabNames.indexOf('inbox')),
              ),
              _dashTile(
                Icons.forum_outlined,
                'Active',
                badge: active,
                onTap: () => _tabs.animateTo(_tabNames.indexOf('inbox')),
              ),
              _dashTile(
                Icons.payments_outlined,
                'Earnings',
                onTap: () => _tabs.animateTo(_tabNames.indexOf('consultations')),
              ),
              _dashTile(
                Icons.contact_mail_outlined,
                'Enquiries',
                badge: newEnquiries,
                onTap: () => _tabs.animateTo(_tabNames.indexOf('enquiries')),
              ),
              _dashTile(
                Icons.person_outline_rounded,
                'My Profile',
                onTap: () => context.push('/dashboard/profile'),
              ),
              _dashTile(
                Icons.tune_rounded,
                'Rates',
                onTap: () => context.push('/dashboard/profile'),
              ),
              _dashTile(
                Icons.history_rounded,
                'History',
                onTap: () => _tabs.animateTo(_tabNames.indexOf('consultations')),
              ),
              _dashTile(
                Icons.more_horiz_rounded,
                'More',
                onTap: () => context.push('/more'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (pending > 0)
            NoticeBanner(
              tone: ChipTone.warning,
              icon: Icons.notifications_active_outlined,
              message: pending == 1
                  ? 'One client is waiting for you to accept.'
                  : '$pending clients are waiting for you to accept.',
              action: TextButton(
                onPressed: () => _tabs.animateTo(_tabNames.indexOf('inbox')),
                child: const Text('Open'),
              ),
            )
          else if (!_available)
            NoticeBanner(
              tone: ChipTone.neutral,
              icon: Icons.toggle_off_outlined,
              message:
                  'You are offline, so new bookings are being refused. Switch '
                  'on above when you are free to take them.',
            ),
        ],
      ),
    );
  }

  Widget _overviewStat(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.65)),
          ),
        ],
      ),
    );
  }

  Widget _overviewDivider() =>
      Container(height: 30, width: 1, color: Colors.white.withOpacity(0.15));

  Widget _dashTile(
    IconData icon,
    String label, {
    int badge = 0,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                backgroundColor: AppColors.danger,
                child: Container(
                  height: 34,
                  width: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inboxTab() {
    if (_loadingInbox && _inbox.isEmpty) {
      return const SkeletonList(count: 3, height: 128);
    }

    final error = _inboxError;
    if (error != null && _inbox.isEmpty) {
      return ErrorView(
        message: error.message,
        isNetwork: error.isNetwork,
        onRetry: _loadInbox,
      );
    }

    if (_inbox.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadInbox,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.55,
              child: EmptyView(
                icon: Icons.inbox_rounded,
                title: _available ? 'Nothing waiting' : 'You are offline',
                message: _available
                    ? 'New consultation requests will appear here the moment they arrive.'
                    : 'Switch yourself online above so clients can reach you.',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInbox,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomGutter(context)),
        itemCount: _inbox.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _requestCard(_inbox[i]),
      ),
    );
  }

  Widget _requestCard(Consultation session) {
    final waiting = session.status.isWaiting;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: waiting ? AppColors.accent.withOpacity(0.5) : AppColors.border,
          width: waiting ? 1.4 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Avatar(name: session.userName, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.userName.isEmpty ? 'Client' : session.userName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${session.type.label} · ${Fmt.rate(session.rate)}',
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: session.status.label,
                tone: waiting ? ChipTone.warning : ChipTone.success,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.muted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 15, color: AppColors.inkFaint),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    waiting
                        ? 'They can talk for up to ${Fmt.pluralize(session.maxMinutes, 'minute')}.'
                        : '${Fmt.clock(session.remaining)} remaining',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (waiting)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: BorderSide(color: AppColors.danger.withOpacity(0.4)),
                    ),
                    onPressed: () => _act(session, accept: false),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => _act(session, accept: true),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openSession(session),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Open session'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _act(Consultation session, {required bool accept}) async {
    final service = context.read<ConsultationService>();
    try {
      final updated =
          accept ? await service.accept(session.id) : await service.reject(session.id);
      if (!mounted) return;
      await _loadInbox(silent: true);
      if (accept && mounted) _openSession(updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      Toast.error(context, e.message);
      _loadInbox(silent: true);
    }
  }

  void _openSession(Consultation session) {
    final route = switch (session.type) {
      ConsultationType.chat => '/consultation/${session.id}/chat',
      ConsultationType.video => '/consultation/${session.id}/video',
      ConsultationType.audio => '/consultation/${session.id}/audio',
    };
    context.push(route);
  }

  Widget _historyTab() {
    if (_loadingHistory) return const SkeletonList(count: 5, height: 96);

    if (_history.isEmpty) {
      return const EmptyView(
        icon: Icons.history_rounded,
        title: 'No consultations yet',
        message: 'Sessions you take will be listed here with what they earned.',
      );
    }

    final earned = _history.fold<int>(0, (sum, c) => sum + c.price);

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomGutter(context)),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total earned',
                          style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
                      Text(
                        Fmt.money(earned),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sessions',
                          style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
                      Text(
                        '${_history.length}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final session in _history)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                tileColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: AppColors.border),
                ),
                leading: Avatar(name: session.userName, size: 38),
                title: Text(
                  session.userName.isEmpty ? 'Client' : session.userName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${session.type.label} · ${Fmt.date(session.createdAt)}',
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
                trailing: Text(
                  session.price > 0 ? Fmt.money(session.price) : '—',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                onTap: () => _openSession(session),
              ),
            ),
        ],
      ),
    );
  }

  Widget _enquiriesTab() {
    if (_loadingEnquiries) return const SkeletonList(count: 4, height: 128);

    if (_enquiries.isEmpty) {
      return const EmptyView(
        icon: Icons.mail_outline_rounded,
        title: 'No enquiries yet',
        message: 'Clients who want a callback rather than a live session '
            'will appear here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEnquiries,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomGutter(context)),
        itemCount: _enquiries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _enquiryCard(_enquiries[i]),
      ),
    );
  }

  Widget _enquiryCard(Enquiry enquiry) {
    final tone = switch (enquiry.status) {
      'confirmed' => ChipTone.success,
      'declined' => ChipTone.danger,
      'pending' => ChipTone.warning,
      _ => ChipTone.info,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  enquiry.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              StatusChip(label: enquiry.status, tone: tone),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${Fmt.phone(enquiry.phone)} · ${Fmt.date(enquiry.createdAt)}',
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
          if (enquiry.preferredDate.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Prefers ${enquiry.preferredDate}',
              style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            enquiry.message,
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _setEnquiryStatus(enquiry, 'declined'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(color: AppColors.danger.withOpacity(0.35)),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _setEnquiryStatus(enquiry, 'confirmed'),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _setEnquiryStatus(Enquiry enquiry, String status) async {
    try {
      await context.read<DashboardService>().setEnquiryStatus(enquiry.id, status);
      if (!mounted) return;
      Toast.success(context, 'Enquiry marked $status.');
      _loadEnquiries();
    } on ApiException catch (e) {
      if (!mounted) return;
      Toast.error(context, e.message);
    }
  }

  Widget _profileTab() {
    final advocate = context.watch<AuthController>().advocate!;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomGutter(context)),
      children: [
        Row(
          children: [
            Avatar(name: advocate.name, photo: advocate.photo, size: 62),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(advocate.name,
                      style: Theme.of(context).textTheme.titleLarge),
                  if (advocate.legalCareId.isNotEmpty)
                    Text(
                      advocate.legalCareId,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: AppColors.inkFaint,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Your rates',
          icon: Icons.payments_outlined,
          child: Column(
            children: [
              DetailRow(
                label: 'Live chat',
                value: advocate.offersChat ? Fmt.rate(advocate.chatRate) : 'Not offered',
              ),
              DetailRow(
                label: 'Audio call',
                value: advocate.offersAudio ? Fmt.rate(advocate.audioRate) : 'Not offered',
              ),
              DetailRow(
                label: 'Video call',
                value: advocate.offersVideo ? Fmt.rate(advocate.videoRate) : 'Not offered',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Practice',
          icon: Icons.gavel_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DetailRow(label: 'Bar Council', value: advocate.barCouncilNumber),
              DetailRow(label: 'Experience', value: Fmt.experience(advocate.experience)),
              DetailRow(
                label: 'Location',
                value: [advocate.city, advocate.state].where((s) => s.isNotEmpty).join(', '),
              ),
              const SizedBox(height: 10),
              ChipWrap(
                children: [
                  for (final s in advocate.specializations)
                    Tag(label: s, tone: AppColors.accent),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Manage',
          icon: Icons.settings_outlined,
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_outlined, size: 20),
                title: const Text('Edit profile'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/dashboard/profile'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.open_in_new_rounded, size: 20),
                title: const Text('View public profile'),
                subtitle: advocate.isPublished
                    ? null
                    : Text(
                        'Not public yet — awaiting approval.',
                        style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                      ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: advocate.isPublished
                    ? () => context.push('/lawyers/${advocate.profilePath}')
                    : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout_rounded, size: 20, color: AppColors.danger),
                title: Text('Sign out', style: TextStyle(color: AppColors.danger)),
                onTap: () async {
                  await context.read<AuthController>().signOut();
                  if (context.mounted) context.go('/');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

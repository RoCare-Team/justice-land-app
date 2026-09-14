import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../state/auth_controller.dart';
import '../../state/lawyer_controller.dart';
import 'lawyer_widgets.dart';

/// The lawyer's home: who they are and whether they are taking clients, what
/// today has earned, who is waiting, and what is running right now.
class LawyerHomeScreen extends StatelessWidget {
  const LawyerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    final advocate = context.watch<AuthController>().advocate;
    final pending = lawyer.pending;
    final live = lawyer.live;

    return RefreshIndicator(
      onRefresh: lawyer.refreshAll,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const _Header(),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomGutter(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (advocate != null && !advocate.isPublished) ...[
                  const NoticeBanner(
                    tone: ChipTone.warning,
                    icon: Icons.schedule_rounded,
                    message: 'Your profile is under review. Clients will find you in the '
                        'directory once our team approves it.',
                  ),
                  const SizedBox(height: 14),
                ],
                const _QuickActions(),
                const SizedBox(height: 14),
                const _LiveBanner(),
                const SizedBox(height: 14),
                const _EarningsCard(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _StatTile(
                      icon: Icons.groups_rounded,
                      tone: AppColors.info,
                      value: '${lawyer.paid.length}',
                      label: 'Total\nConsultations',
                    ),
                    const SizedBox(width: 10),
                    _StatTile(
                      icon: Icons.schedule_rounded,
                      tone: AppColors.danger,
                      value: '${pending.length}',
                      label: 'Pending\nRequests',
                      onTap: () => context.go('/lawyer/requests'),
                    ),
                    const SizedBox(width: 10),
                    _StatTile(
                      icon: Icons.star_rounded,
                      tone: const Color(0xFF7C3AED),
                      value: (advocate?.rating ?? 0) > 0 ? Fmt.rating(advocate!.rating) : '—',
                      label: '${advocate?.reviews ?? 0} reviews',
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                SectionTitle(
                  title: 'Incoming Requests',
                  icon: Icons.assignment_ind_outlined,
                  count: pending.length,
                  action: 'See All',
                  onAction: () => context.go('/lawyer/requests'),
                ),
                if (!lawyer.inboxLoaded)
                  // A fixed block, not SkeletonList: that is a ListView of its own and
                  // cannot sit inside this page's scroll view.
                  Container(
                    height: 130,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (pending.isEmpty)
                  EmptyCard(
                    icon: Icons.notifications_none_rounded,
                    title: 'No requests right now',
                    message: lawyer.available
                        ? 'You are online — new requests ring here the moment they arrive.'
                        : 'You are offline. Go online so clients can reach you.',
                  )
                else
                  for (final s in pending.take(2))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RequestCard(
                        session: s,
                        onTap: () => context.push('/lawyer/client/${s.userId}'),
                      ),
                    ),
                const SizedBox(height: 18),
                SectionTitle(
                  title: 'Active Consultations',
                  icon: Icons.radio_button_checked_rounded,
                  count: live.length,
                  action: 'See All',
                  onAction: () => context.go('/lawyer/consultations'),
                ),
                if (live.isEmpty)
                  const EmptyCard(
                    icon: Icons.forum_outlined,
                    title: 'Nothing running',
                    message: 'Accepted chats and calls show here with a live timer.',
                  )
                else
                  for (final s in live)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: LiveSessionCard(session: s),
                    ),
                const SizedBox(height: 18),
                const _TodaySchedule(),
                const SizedBox(height: 18),
                const _StayOnlineBand(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final advocate = context.watch<AuthController>().advocate;
    final lawyer = context.watch<LawyerController>();
    final name = (advocate?.name ?? '').replaceFirst(RegExp(r'^Adv\.?\s*', caseSensitive: false), '');
    final top = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(18, top + 14, 18, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.balance_rounded, color: AppColors.accent, size: 26),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Justiceland',
                  style: TextStyle(fontFamily: AppText.display, fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              IconButton(
                onPressed: () => context.push('/lawyer/notifications'),
                icon: Badge(
                  isLabelVisible: lawyer.pending.isNotEmpty,
                  label: Text('${lawyer.pending.length}'),
                  backgroundColor: AppColors.danger,
                  child: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 26),
                ),
              ),
              GestureDetector(
                onTap: () => context.go('/lawyer/profile'),
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 2)),
                  child: Avatar(name: advocate?.name ?? '', photo: advocate?.photo, size: 42, online: lawyer.available),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('$_greeting,', style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(
                child: Text(
                  'Adv. $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: AppText.display, fontSize: 25, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              if (advocate?.verified ?? false) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified_rounded, color: AppColors.success, size: 22),
              ],
            ],
          ),
          const SizedBox(height: 2),
          const Text('Ready to help. Make a difference today!', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          const OnlineSwitch(onDark: true),
        ],
      ),
    );
  }
}

/// The online/offline switch as a white pill — on the navy header and on the
/// availability screen alike.
class OnlineSwitch extends StatelessWidget {
  const OnlineSwitch({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    final on = lawyer.available;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
      decoration: BoxDecoration(
        color: on ? AppColors.successSoft : Colors.white.withValues(alpha: onDark ? 0.92 : 1.0),
        borderRadius: BorderRadius.circular(999),
        border: onDark ? null : Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            on ? 'Online' : 'Offline',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: on ? const Color(0xFF15803D) : AppColors.inkMuted),
          ),
          const SizedBox(width: 6),
          if (lawyer.savingAvailability)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Switch(
              value: on,
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.success,
              onChanged: (value) => toggleOnline(context, value),
            ),
        ],
      ),
    );
  }

}

/// Flips the online switch and says what that means for bookings.
Future<void> toggleOnline(BuildContext context, bool value) async {
  try {
    await context.read<LawyerController>().setAvailable(value);
    if (context.mounted) {
      Toast.show(
        context,
        value ? 'You are online — clients can reach you.' : 'You are offline. New requests will be refused.',
      );
    }
  } on ApiException catch (e) {
    if (context.mounted) Toast.error(context, e.message);
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final advocate = context.watch<AuthController>().advocate;
    Widget tile(IconData icon, String label, String sub, VoidCallback onTap, {bool highlight = false}) {
      return Expanded(
        child: Material(
          color: highlight ? AppColors.accentSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: highlight ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border),
              ),
              child: Column(
                children: [
                  Icon(icon, size: 24, color: AppColors.primary),
                  const SizedBox(height: 6),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: AppColors.inkFaint)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    String rate(int r) => r > 0 ? Fmt.rate(r) : 'Off';
    void rates() => context.push('/lawyer/availability');

    return Row(
      children: [
        tile(Icons.chat_rounded, 'Chat', rate(advocate?.chatRate ?? 0), rates, highlight: true),
        const SizedBox(width: 8),
        tile(Icons.call_rounded, 'Audio Call', rate(advocate?.audioRate ?? 0), rates),
        const SizedBox(width: 8),
        tile(Icons.videocam_rounded, 'Video Call', rate(advocate?.videoRate ?? 0), rates),
        const SizedBox(width: 8),
        tile(Icons.settings_rounded, 'Settings', 'Account', () => context.push('/lawyer/settings')),
      ],
    );
  }
}

class _LiveBanner extends StatelessWidget {
  const _LiveBanner();

  @override
  Widget build(BuildContext context) {
    final on = context.watch<LawyerController>().available;
    return Material(
      color: on ? AppColors.successSoft : AppColors.warningSoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/lawyer/availability'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: (on ? AppColors.success : AppColors.warning).withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: on ? const Color(0xFF15803D) : AppColors.warning,
                child: Icon(on ? Icons.bolt_rounded : Icons.bedtime_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      on ? 'You are Live!' : 'You are Offline',
                      style: TextStyle(
                        fontFamily: AppText.display,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: on ? const Color(0xFF166534) : AppColors.warning,
                      ),
                    ),
                    Text(
                      on ? 'Clients can now chat, call or video call you.' : 'Clients can’t book you right now.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
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

class _EarningsCard extends StatelessWidget {
  const _EarningsCard();

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    final today = lawyer.earnedToday;
    final yesterday = lawyer.earnedYesterday;
    final change = yesterday > 0 ? ((today - yesterday) / yesterday * 100).round() : null;

    return LCard(
      onTap: () => context.push('/lawyer/earnings'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Today's Earnings", style: TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                const SizedBox(height: 4),
                Text(Fmt.money(today), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                if (change == null)
                  Text('Nothing earned yesterday to compare', style: TextStyle(fontSize: 12, color: AppColors.inkFaint))
                else
                  Row(
                    children: [
                      Icon(
                        change >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 15,
                        color: change >= 0 ? AppColors.success : AppColors.danger,
                      ),
                      Text(
                        ' ${change.abs()}% from yesterday',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: change >= 0 ? const Color(0xFF15803D) : AppColors.danger,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          WeekBars(days: lawyer.week, height: 56, compact: true),
        ],
      ),
    );
  }
}

/// Seven gold bars, today solid. Heights are relative to the week's best day.
class WeekBars extends StatelessWidget {
  const WeekBars({super.key, required this.days, this.height = 120, this.compact = false});

  final List<DayEarning> days;
  final double height;
  final bool compact;

  static const _labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final max = days.fold<int>(0, (m, d) => d.amount > m ? d.amount : m);
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final d in days)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 2.5 : 4),
            child: Tooltip(
              message: '${_labels[d.day.weekday - 1]}: ${Fmt.money(d.amount)}',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: compact ? 9 : 26,
                    height: max == 0 || d.amount == 0 ? 3 : (height * d.amount / max).clamp(6, height).toDouble(),
                    decoration: BoxDecoration(
                      color: d.amount == 0
                          ? AppColors.ink.withValues(alpha: 0.08)
                          : d.isToday
                              ? AppColors.accent
                              : AppColors.accent.withValues(alpha: 0.45),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 6),
                    Text(
                      _labels[d.day.weekday - 1],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: d.isToday ? FontWeight.w700 : FontWeight.w500,
                        color: d.isToday ? AppColors.ink : AppColors.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.tone, required this.value, required this.label, this.onTap});

  final IconData icon;
  final Color tone;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: LCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Column(
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: tone, size: 20),
            ),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: 11, height: 1.2, color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodaySchedule extends StatelessWidget {
  const _TodaySchedule();

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<LawyerController>().today;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          title: "Today's Schedule",
          icon: Icons.calendar_month_outlined,
          action: 'History',
          onAction: () => context.go('/lawyer/consultations'),
        ),
        if (sessions.isEmpty)
          const EmptyCard(
            icon: Icons.event_available_outlined,
            title: 'No sessions yet today',
            message: 'Everything you take today lines up here.',
          )
        else
          for (final s in sessions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LCard(
                padding: const EdgeInsets.all(12),
                onTap: () => context.push('/lawyer/client/${s.userId}'),
                child: Row(
                  children: [
                    SizedBox(
                      width: 62,
                      child: Text(
                        Fmt.time(s.happenedAt),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Container(width: 1, height: 40, color: AppColors.border),
                    const SizedBox(width: 12),
                    Avatar(name: s.userName, size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.userName.isEmpty ? 'Client' : s.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          TypePill(type: s.type, suffix: s.talkedMinutes > 0 ? '· ${s.talkedMinutes} mins' : null),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        sessionStatusChip(s),
                        if (s.charged) ...[
                          const SizedBox(height: 4),
                          Text('+${Fmt.money(s.price)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF15803D))),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _StayOnlineBand extends StatelessWidget {
  const _StayOnlineBand();

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primaryLight]),
      ),
      child: Row(
        children: [
          const Icon(Icons.balance_rounded, color: AppColors.accent, size: 40),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Help People. Uphold Justice.',
                  style: TextStyle(fontFamily: AppText.display, fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                SizedBox(height: 2),
                Text('Your expertise can change lives.', style: TextStyle(fontSize: 12.5, color: Colors.white70)),
              ],
            ),
          ),
          if (!lawyer.available)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.primaryDark),
              onPressed: () => toggleOnline(context, true),
              child: const Text('Go Online'),
            ),
        ],
      ),
    );
  }
}

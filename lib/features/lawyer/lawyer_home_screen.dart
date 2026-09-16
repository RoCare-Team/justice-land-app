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

    return HeaderStatusBand(
      // The header runs up under the status bar, and once it scrolls away the
      // rows behind it would pass under the clock and the signal bars. The
      // band carries the header's own colours so there is no seam across the
      // top of the page when nothing has scrolled yet.
      gradient: const LinearGradient(
        colors: [AppColors.primaryLight, AppColors.primary],
      ),
      child: RefreshIndicator(
        onRefresh: lawyer.refreshAll,
        // Keep the spinner clear of the band.
        edgeOffset: MediaQuery.paddingOf(context).top,
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
                // No live/offline banner here. The switch in the header above
                // already says which one you are, and says it where you change
                // it; repeating it in a card underneath was the same fact
                // twice on one screen. Availability itself is still a tap away
                // from the rate tiles, Profile and Settings.
                const _PerformanceSummary(),
                const SizedBox(height: 14),
                const _QuickActions(),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: AppText.display, fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              // Availability sits with the other controls rather than under the
              // greeting: it is the one thing on this header a lawyer reaches
              // for repeatedly, and the greeting is not a place to put a
              // control.
              const OnlineSwitch(onDark: true),
              const SizedBox(width: 4),
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
                  child: Avatar(
                    name: advocate?.name ?? '',
                    photo: advocate?.photo,
                    size: 42,
                    online: lawyer.available,
                    onDark: true,
                  ),
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
        ],
      ),
    );
  }
}

/// The online/offline switch as a compact pill — on the navy header and on
/// the availability screen alike.
///
/// The track is drawn here rather than taken from Material's [Switch], which
/// carries a 48dp tap target of its own and made this pill tall enough to
/// crowd the greeting above it. The whole pill is the tap target instead, so
/// the control got smaller without getting harder to hit.
class OnlineSwitch extends StatelessWidget {
  const OnlineSwitch({super.key, this.onDark = false});

  final bool onDark;

  static const Duration _swing = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    final on = lawyer.available;
    final busy = lawyer.savingAvailability;
    final tint = on ? const Color(0xFF15803D) : AppColors.inkMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: busy ? null : () => toggleOnline(context, !on),
        child: AnimatedContainer(
          duration: _swing,
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: on
                ? AppColors.successSoft
                : Colors.white.withValues(alpha: onDark ? 0.92 : 1.0),
            borderRadius: BorderRadius.circular(999),
            border: onDark ? null : Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                on ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: tint,
                ),
              ),
              const SizedBox(width: 8),
              // The spinner takes the track's exact footprint, so the pill does
              // not jump while the server is being told.
              SizedBox(
                width: 34,
                height: 18,
                child: busy
                    ? Center(
                        child: SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tint,
                          ),
                        ),
                      )
                    : _track(on),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _track(bool on) {
    return AnimatedContainer(
      duration: _swing,
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: on ? AppColors.success : AppColors.ink.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: _swing,
        curve: Curves.easeOut,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 14,
          height: 14,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
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

/// What a lawyer charges, per channel, under one heading.
///
/// Three loose tiles read as three buttons; the heading and the card say what
/// they actually are — this lawyer's rates — and the price is what the eye
/// should land on, so it is set larger than the channel it belongs to.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final advocate = context.watch<AuthController>().advocate;

    return LCard(
      onTap: () => context.push('/lawyer/availability'),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Communication Channels',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppText.display,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Says what tapping the card does; the rates are set on the
              // availability screen, not here.
              Text(
                'Edit rates',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.inkFaint),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: AppColors.border),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _channel(Icons.chat_rounded, 'Chat', advocate?.chatRate ?? 0),
                _rule(),
                _channel(Icons.call_rounded, 'Audio Call', advocate?.audioRate ?? 0),
                _rule(),
                _channel(Icons.videocam_rounded, 'Video Call', advocate?.videoRate ?? 0),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _channel(IconData icon, String label, int perMinute) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: AppColors.primary),
          const SizedBox(height: 8),
          if (perMinute <= 0)
            Text(
              'Off',
              style: TextStyle(
                fontFamily: AppText.display,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.inkFaint,
              ),
            )
          else
            // The amount carries the weight; the unit rides small beside it, so
            // "₹100" is what reads across the row rather than "/min" three
            // times over.
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  Fmt.money(perMinute),
                  style: const TextStyle(
                    fontFamily: AppText.display,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
                Text(
                  '/min',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _rule() => VerticalDivider(
        width: 1,
        thickness: 1,
        color: AppColors.border,
      );
}

/// Today's earnings, consultations done and requests waiting — on one card.
///
/// These were an earnings card and a row of three tiles: four boxes for what
/// is really three numbers a lawyer checks together. One of the tiles was a
/// star rating with no reviews behind it, which for a new lawyer is a box that
/// says nothing and cannot be acted on. Side by side the three figures can be
/// read against each other, which is the only reason to look at them at once.
class _PerformanceSummary extends StatelessWidget {
  const _PerformanceSummary();

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();

    return LCard(
      onTap: () => context.push('/lawyer/earnings'),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Performance Summary',
                  style: TextStyle(
                    fontFamily: AppText.display,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // The week at a glance, beside the heading rather than under a
              // figure — it belongs to all three numbers, not just the money.
              WeekBars(days: lawyer.week, height: 30, compact: true),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: AppColors.border),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _figure(Fmt.money(lawyer.earnedToday), "Today's\nEarnings", AppColors.accent),
                _rule(),
                _figure('${lawyer.paid.length}', 'Completed\nConsultations', AppColors.ink),
                _rule(),
                _figure('${lawyer.pending.length}', 'Pending\nRequests', AppColors.ink),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _figure(String value, String label, Color tone) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppText.display,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: tone,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.3, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _rule() => VerticalDivider(
        width: 1,
        thickness: 1,
        color: AppColors.border,
      );
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

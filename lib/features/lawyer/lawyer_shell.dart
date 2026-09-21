import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/consultation.dart';
import '../../state/lawyer_controller.dart';
import 'lawyer_widgets.dart';

typedef _Tab = ({String path, IconData icon, IconData active, String label, bool badge});

/// The lawyer app's frame: its own bottom bar, and the ringing sheet that
/// comes up when a new request arrives.
///
/// Nothing from the client app is reachable from here — the router sends a
/// signed-in lawyer back to these tabs from anywhere else.
class LawyerShell extends StatefulWidget {
  const LawyerShell({super.key, required this.child});

  final Widget child;

  @override
  State<LawyerShell> createState() => _LawyerShellState();
}

class _LawyerShellState extends State<LawyerShell> {
  static const List<_Tab> _tabs = [
    (path: '/lawyer', icon: Icons.home_outlined, active: Icons.home_rounded, label: 'Home', badge: false),
    (path: '/lawyer/requests', icon: Icons.notifications_none_rounded, active: Icons.notifications_rounded, label: 'Requests', badge: true),
    (path: '/lawyer/consultations', icon: Icons.event_note_outlined, active: Icons.event_note_rounded, label: 'Consultations', badge: false),
    (path: '/lawyer/messages', icon: Icons.chat_bubble_outline_rounded, active: Icons.chat_bubble_rounded, label: 'Messages', badge: false),
    (path: '/lawyer/profile', icon: Icons.person_outline_rounded, active: Icons.person_rounded, label: 'Profile', badge: false),
  ];

  late final AppLifecycleListener _lifecycle;
  LawyerController? _lawyer;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    // No presence heartbeat from a phone in someone's pocket.
    _lifecycle = AppLifecycleListener(
      onResume: () => _lawyer?.setPaused(false),
      onPause: () => _lawyer?.setPaused(true),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lawyer = context.read<LawyerController>();
    if (!identical(lawyer, _lawyer)) {
      _lawyer?.removeListener(_maybeRing);
      _lawyer = lawyer..addListener(_maybeRing);
    }
  }

  @override
  void dispose() {
    _lawyer?.removeListener(_maybeRing);
    _lifecycle.dispose();
    super.dispose();
  }

  /// Rings for a request that arrived while the lawyer is on one of the tabs.
  /// Over a live chat or call the tab's badge and the Home card carry it
  /// instead — a sheet over a running consultation would be in the way.
  void _maybeRing() {
    if (_sheetOpen || !mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final request = _lawyer?.takeAnnouncement();
    if (request == null) return;
    _sheetOpen = true;
    showModalBottomSheet<RequestAnswer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IncomingRequestSheet(session: request),
    ).then((answer) async {
      _sheetOpen = false;
      // Acted on from the shell once the sheet is gone: the sheet's own context
      // dies with it, and opening the session from underneath a closing sheet
      // would leave the sheet attached to the wrong page.
      if (!mounted || answer == null) return;
      if (answer == RequestAnswer.accept) {
        await acceptAndOpen(context, request);
      } else {
        await declineRequest(context, request);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final pending = context.select<LawyerController, int>((l) => l.pending.length);
    var index = _tabs.indexWhere((t) => t.path == location);
    if (index < 0) index = 0;

    return Scaffold(
      backgroundColor: AppColors.muted,
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(color: AppColors.ink.withValues(alpha: 0.07), blurRadius: 18, offset: const Offset(0, -3)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(child: _tab(_tabs[i], i == index, _tabs[i].badge ? pending : 0)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(_Tab tab, bool selected, int badge) {
    final color = selected ? AppColors.accent : AppColors.ink.withValues(alpha: 0.45);
    return InkWell(
      onTap: () => context.go(tab.path),
      child: Stack(
        children: [
          if (selected)
            Positioned(
              top: 0,
              left: 18,
              right: 18,
              child: Container(
                height: 3,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(3)),
                ),
              ),
            ),
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: badge > 0,
                  label: Text('$badge'),
                  backgroundColor: AppColors.danger,
                  child: Icon(selected ? tab.active : tab.icon, size: 24, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.primary : AppColors.ink.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum RequestAnswer { accept, decline }

/// The ringing sheet: who, what kind of session, what it pays, Accept/Decline.
/// Pops with the lawyer's answer; the shell carries it out.
class IncomingRequestSheet extends StatefulWidget {
  const IncomingRequestSheet({super.key, required this.session});

  final Consultation session;

  @override
  State<IncomingRequestSheet> createState() => _IncomingRequestSheetState();
}

class _IncomingRequestSheetState extends State<IncomingRequestSheet> {
  Timer? _ring;
  int _rings = 0;

  @override
  void initState() {
    super.initState();
    _buzz();
    // Rings like a phone for up to a minute, then waits quietly.
    _ring = Timer.periodic(const Duration(seconds: 3), (_) {
      _rings++;
      if (_rings > 20) {
        _ring?.cancel();
        return;
      }
      _buzz();
    });
  }

  void _buzz() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  @override
  void dispose() {
    _ring?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    final s = widget.session;
    // Gone from the inbox: the client cancelled, or it was answered elsewhere.
    final stillWaiting = lawyer.pending.any((c) => c.id == s.id);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryLight, AppColors.primaryDark],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(999)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 8, color: AppColors.success),
                            SizedBox(width: 6),
                            Text('Incoming request', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(Fmt.timeAgo(s.createdAt), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 3)),
                    child: CircleAvatar(
                      radius: 42,
                      backgroundColor: Colors.white,
                      child: Text(
                        Fmt.initial(s.userName),
                        style: const TextStyle(fontFamily: AppText.display, fontSize: 34, fontWeight: FontWeight.w700, color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    s.userName.isEmpty ? 'Client' : s.userName,
                    style: const TextStyle(fontFamily: AppText.display, fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.isVideo
                        ? 'wants a video call with you'
                        : s.isAudio
                            ? 'wants to call you'
                            : 'wants to chat with you',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  _fact(typeIcon(s.type), s.isVideo ? 'Video' : s.isAudio ? 'Audio' : 'Chat', 'Type'),
                  _fact(Icons.currency_rupee_rounded, Fmt.rate(s.rate), 'Your rate'),
                  _fact(Icons.timer_outlined, s.maxMinutes > 0 ? '${s.maxMinutes} min' : '—', 'Up to'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                stillWaiting
                    ? 'You are paid for every minute it runs, credited when it ends.'
                    : 'This request is no longer waiting.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: stillWaiting ? AppColors.inkMuted : AppColors.danger),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _roundButton(
                    color: AppColors.danger,
                    icon: Icons.close_rounded,
                    label: 'Decline',
                    onTap: () => Navigator.pop(
                      context,
                      stillWaiting ? RequestAnswer.decline : null,
                    ),
                  ),
                  _roundButton(
                    color: AppColors.success,
                    icon: Icons.check_rounded,
                    label: 'Accept',
                    onTap: stillWaiting
                        ? () => Navigator.pop(context, RequestAnswer.accept)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fact(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
        ],
      ),
    );
  }

  Widget _roundButton({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Column(
      children: [
        Material(
          color: onTap == null ? color.withValues(alpha: 0.4) : color,
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              height: 64,
              width: 64,
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

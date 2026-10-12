import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../voice/voice_search_sheet.dart';

/// "Find your lawyer" — the spoken way in, for a signed-in client.
///
/// Shown once per launch as an animated dialog; after that it lives on the
/// home screen as [FindLawyerCard], so it is never more than a tap away.
class FindLawyerDialog extends StatelessWidget {
  const FindLawyerDialog({super.key});

  static Future<void> show(BuildContext context) async {
    final choice = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Find your lawyer',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (_, __, ___) => const FindLawyerDialog(),
      transitionBuilder: (_, animation, __, child) {
        final curve =
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
              scale: Tween(begin: 0.8, end: 1.0).animate(curve), child: child),
        );
      },
    );
    if (!context.mounted) return;
    if (choice == 'voice') VoiceSearchSheet.open(context);
    if (choice == 'browse') context.go('/lawyers');
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primaryLight, AppColors.primaryDark],
                  ),
                ),
                child: const Column(
                  children: [
                    _PulsingMic(size: 72),
                    SizedBox(height: 16),
                    Text(
                      'Find your lawyer',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Describe your legal problem — in English or Hindi.\nWe will find the right lawyer for you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13.5, height: 1.4, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context, 'voice'),
                      icon: const Icon(Icons.mic_rounded),
                      label: const Text('Describe your problem'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'browse'),
                      icon: const Icon(Icons.gavel_rounded, size: 18),
                      label: const Text('Browse lawyers'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Later'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The same prompt, floating on the home screen's right edge.
///
/// It rolls out from the right edge across the screen, stays open for three
/// seconds, then rolls back into a small tab on the right. Open or folded, a
/// tap opens voice search. The roll plays once per launch; after that Home
/// shows it folded.
///
/// The tab can be dragged anywhere on Home. While held it is a round mic;
/// let go, it leaps to the nearer side edge and sticks there as a tab again,
/// and stays there for the rest of the launch.
class FindLawyerCard extends StatefulWidget {
  const FindLawyerCard({super.key});

  static bool _played = false;

  /// Where the user dragged it to — the tab's top-left. Null while it is
  /// still where it started on the right edge.
  static Offset? _position;

  /// Which edge it was last stuck to.
  static bool _onLeft = false;

  @override
  State<FindLawyerCard> createState() => _FindLawyerCardState();
}

class _FindLawyerCardState extends State<FindLawyerCard>
    with TickerProviderStateMixin {
  static const _height = 46.0;
  static const _folded = 50.0;
  static const _stayOpen = Duration(seconds: 3);

  late final AnimationController _roll = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
    reverseDuration: const Duration(milliseconds: 650),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _roll,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  Timer? _timer;

  /// The leap to the edge after a drag: [_snapX] carries it across, and
  /// [_stick] goes from 0 (round, in hand) to 1 (flush against the edge).
  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..addListener(_onSnap);
  Animation<double>? _snapX;
  double _stick = 1;

  @override
  void initState() {
    super.initState();
    if (FindLawyerCard._played) return;
    _timer = Timer(const Duration(milliseconds: 400), _play);
  }

  /// Waits until nothing covers Home — at launch the "Find your lawyer"
  /// dialog is usually still up — so the roll is actually seen.
  Future<void> _play() async {
    if (!mounted) return;
    // Home sits in the tab shell's own navigator, and dialogs open on the
    // root one above it — so both have to be clear.
    final covered = !(ModalRoute.of(context)?.isCurrent ?? false) ||
        Navigator.of(context, rootNavigator: true).canPop();
    if (covered) {
      _timer = Timer(const Duration(milliseconds: 500), _play);
      return;
    }
    FindLawyerCard._played = true;
    await _roll.forward();
    if (!mounted) return;
    _timer = Timer(_stayOpen, () {
      if (mounted) _roll.reverse();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _roll.dispose();
    _snap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final pos = FindLawyerCard._position;
        final drag = GestureDetector(
          onPanStart: (_) => _startDrag(size),
          onPanUpdate: (d) => _drag(d.delta, size),
          onPanEnd: (_) => _stickToEdge(size),
          child: pos == null ? _docked(size.width - 16) : _tab(context),
        );
        return Stack(
          children: [
            if (pos == null)
              Positioned(
                  left: 16, right: 0, top: size.height * 0.45, child: drag)
            else
              Positioned(left: pos.dx, top: pos.dy, child: drag),
          ],
        );
      },
    );
  }

  /// Picking the tab up stops the roll and folds it to the round mic, which
  /// then follows the finger.
  void _startDrag(Size size) {
    _timer?.cancel();
    _roll.stop();
    _roll.value = 0;
    _snap.stop();
    _snapX = null;
    FindLawyerCard._played = true;
    setState(() {
      _stick = 0;
      FindLawyerCard._position ??=
          Offset(size.width - _folded, size.height * 0.45);
    });
  }

  /// Kept inside Home, clear of the status bar and the floating tab bar.
  void _drag(Offset delta, Size size) {
    final padding = MediaQuery.paddingOf(context);
    final next = FindLawyerCard._position! + delta;
    setState(() {
      FindLawyerCard._position = Offset(
        next.dx.clamp(0.0, size.width - _height),
        next.dy.clamp(padding.top,
            math.max(padding.top, size.height - padding.bottom - _height)),
      );
    });
  }

  /// Let go, it leaps to whichever side edge is nearer — overshooting a
  /// little and settling, like a child jumping into an outstretched arm.
  void _stickToEdge(Size size) {
    final from = FindLawyerCard._position!;
    final left = from.dx + _height / 2 < size.width / 2;
    FindLawyerCard._onLeft = left;
    _snapX = Tween(begin: from.dx, end: left ? 0.0 : size.width - _folded)
        .animate(CurvedAnimation(parent: _snap, curve: Curves.easeOutBack));
    _snap.forward(from: 0);
  }

  void _onSnap() {
    final x = _snapX;
    if (x == null) return;
    setState(() {
      FindLawyerCard._position = Offset(x.value, FindLawyerCard._position!.dy);
      _stick = Curves.easeOut.transform((_snap.value / 0.6).clamp(0.0, 1.0));
    });
  }

  /// Round while held; flush against its edge, rounded only on the inside,
  /// once it has stuck.
  Widget _tab(BuildContext context) {
    const inner = Radius.circular(23);
    final outer = Radius.circular(23 * (1 - _stick));
    return Material(
      color: AppColors.primary,
      elevation: 6,
      shadowColor: AppColors.primaryDark.withValues(alpha: 0.5),
      borderRadius: FindLawyerCard._onLeft
          ? BorderRadius.horizontal(left: outer, right: inner)
          : BorderRadius.horizontal(left: inner, right: outer),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        width: _height + (_folded - _height) * _stick,
        height: _height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryLight, AppColors.primaryDark],
          ),
        ),
        child: InkWell(
          onTap: () => VoiceSearchSheet.open(context),
          child: const Center(child: _PulsingMic(size: 34)),
        ),
      ),
    );
  }

  /// On the right edge, where it starts: the tab that rolls open.
  Widget _docked(double full) {
    return SizedBox(
      height: _height,
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final t = _t.value;
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: _folded + (full - _folded) * t,
              height: _height,
              child: Material(
                color: AppColors.primary,
                elevation: 6,
                shadowColor: AppColors.primaryDark.withValues(alpha: 0.5),
                // Flush against the screen's right edge, like a tab.
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(23),
                ),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primaryLight, AppColors.primaryDark],
                    ),
                  ),
                  child: InkWell(
                    onTap: () => VoiceSearchSheet.open(context),
                    // Laid out at full width and clipped, so the content is
                    // uncovered as the roll's edge moves rather than squeezed.
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: full,
                      maxWidth: full,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 7, right: 8),
                        child: Row(
                          children: [
                            // Turns as it travels, like the end of a roll.
                            Transform.rotate(
                              angle: -t * 4 * math.pi,
                              child: const _PulsingMic(size: 34),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Opacity(
                                opacity: ((t - 0.55) / 0.45).clamp(0.0, 1.0),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Find your lawyer',
                                      maxLines: 1,
                                      style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white),
                                    ),
                                    SizedBox(height: 1),
                                    Text(
                                      'Describe your problem — we find the lawyer',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: Colors.white.withValues(alpha: 0.8)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A gold microphone with a ring breathing out of it.
class _PulsingMic extends StatefulWidget {
  const _PulsingMic({required this.size});

  final double size;

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: 0.7 + 0.45 * _pulse.value,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent
                      .withValues(alpha: 0.45 * (1 - _pulse.value)),
                ),
              ),
            ),
            child!,
          ],
        ),
        child: Container(
          width: size * 0.7,
          height: size * 0.7,
          decoration: const BoxDecoration(
              color: AppColors.accent, shape: BoxShape.circle),
          child: Icon(Icons.mic_rounded,
              size: size * 0.38, color: AppColors.primaryDark),
        ),
      ),
    );
  }
}

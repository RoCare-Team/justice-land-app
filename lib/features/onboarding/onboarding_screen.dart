import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';

/// The four things Justiceland does, shown once on a first launch.
///
/// It says the same thing the website's hero says — find a verified advocate,
/// compare, consult privately — because someone who installs the app after
/// reading the site should not meet a different promise. Nothing here is
/// fetched: an intro that needs the network is an intro that can fail.
///
/// Seen once and never again. The flag lives in SharedPreferences rather than
/// on the account, because it is a fact about this install, not about a person:
/// it must hold for a visitor who never signs in, and it must not follow
/// someone onto a phone they have never opened the app on.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Set once the visitor has been through it.
  static const String seenKey = 'jl_onboarding_seen';

  /// Whether the intro still has to be shown. A storage failure answers
  /// "already seen" rather than trapping someone in an intro they cannot get
  /// past — the app is perfectly usable without it.
  static Future<bool> isPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(seenKey) ?? false);
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(seenKey, true);
    } catch (_) {
      // Private mode or a full disk. Showing the intro twice is a small cost;
      // failing to start is not.
    }
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Slide {
  const _Slide({
    required this.title,
    required this.body,
    required this.points,
    required this.art,
  });

  final String title;
  final String body;
  final List<({IconData icon, String label})> points;
  final IconData art;
}

const List<_Slide> _slides = [
  _Slide(
    title: 'Get the right legal help.\nPrivately.',
    body: 'Consult verified advocates without revealing your identity.',
    art: Icons.shield_outlined,
    points: [
      (icon: Icons.verified_user_outlined, label: 'Find verified lawyers'),
      (icon: Icons.compare_arrows_rounded, label: 'Compare & choose'),
      (icon: Icons.lock_outline_rounded, label: 'Consult privately'),
      (icon: Icons.videocam_outlined, label: 'Chat, call or video'),
    ],
  ),
  _Slide(
    title: 'Every advocate here\nis verified.',
    body:
        'Bar Council enrolment, courts and practice areas are what each lawyer '
        'has entered about their own practice. Anything not supplied is left '
        'blank rather than filled in for them.',
    art: Icons.workspace_premium_outlined,
    points: [
      (icon: Icons.gavel_rounded, label: 'Bar Council enrolment on the profile'),
      (icon: Icons.account_balance_outlined, label: 'The courts they appear in'),
      (icon: Icons.star_outline_rounded, label: 'Reviews from real consultations'),
    ],
  ),
  _Slide(
    title: 'Pay for the minutes\nyou use.',
    body:
        'Every lawyer states their per-minute rate up front. The clock starts '
        'when you connect, and a request nobody answers costs nothing.',
    art: Icons.account_balance_wallet_outlined,
    points: [
      (icon: Icons.schedule_rounded, label: 'Billed by the minute, not by package'),
      (icon: Icons.currency_rupee_rounded, label: 'Rate shown before you start'),
      (icon: Icons.block_outlined, label: 'Unanswered requests are free'),
    ],
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _slides.length - 1;

  Future<void> _finish() async {
    await OnboardingScreen.markSeen();
    // Not straight to the directory: the two people this app serves want
    // different things from it, and asking once here is cheaper than a home
    // screen that tries to be useful to both.
    if (mounted) context.go('/role');
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 4),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    'Skip',
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _slideView(_slides[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _slides.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 6,
                          width: i == _index ? 22 : 6,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? AppColors.primary
                                : AppColors.primary.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(_isLast ? 'Get Started' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slideView(_Slide slide) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A tinted panel standing in for the illustration. It carries the
          // brand's own navy and gold rather than a stock drawing, so the
          // screen belongs to this product even before any art is added.
          AspectRatio(
            aspectRatio: 1.45,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withOpacity(0.08),
                    AppColors.accent.withOpacity(0.14),
                  ],
                ),
              ),
              child: Center(
                child: Icon(slide.art, size: 88, color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 26),
          Text(
            slide.title,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 27),
          ),
          const SizedBox(height: 10),
          Text(
            slide.body,
            style: TextStyle(fontSize: 14.5, height: 1.55, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 22),
          for (final point in slide.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(point.icon, size: 19, color: AppColors.primary),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      point.label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
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

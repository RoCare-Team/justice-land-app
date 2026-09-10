import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// Which of the two products the visitor came for.
///
/// JusticeLand is one app serving two people whose journeys share almost
/// nothing: a client browses lawyers and books a consultation, a lawyer builds
/// a profile and takes them. Asking once, here, is cheaper than a home screen
/// that tries to be useful to both and is cluttered for each.
///
/// Choosing "user" does NOT sign anybody in. The directory is public — the
/// website lets anyone browse and asks for a number only when they book — so
/// this hands them straight to the home screen. Only the lawyer side needs an
/// account before there is anything to see, and that is where it leads.
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.muted,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Full height where there is room, scrollable where there is not,
            // so the Login line sits at the bottom on a tall phone and is
            // still reachable on a short one instead of being pushed off.
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Welcome to',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.ink.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'JusticeLand',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choose how you want to continue',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppColors.ink.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 36),

                        _RoleCard(
                          art: const _RoleArt(
                            tint: AppColors.primary,
                            badge: Icons.search_rounded,
                          ),
                          title: 'I am a User',
                          blurb: 'Get legal help from verified lawyers',
                          // Straight to the directory. The listing is public,
                          // and asking for a number before showing anything is
                          // how you lose someone who came to look first.
                          onTap: () => context.go('/'),
                        ),
                        const SizedBox(height: 16),
                        _RoleCard(
                          art: const _RoleArt(
                            tint: AppColors.accent,
                            badge: Icons.gavel_rounded,
                          ),
                          title: 'I am a Lawyer',
                          blurb: 'Join as a lawyer and help people',
                          // A lawyer has nothing to see until they have a
                          // profile, so this one does begin with an account.
                          onTap: () => context.go('/advocate/register'),
                        ),

                        const Spacer(),
                        const SizedBox(height: 24),
                        // One link, and it opens the client sign-in because
                        // that is who most returning visitors are. The lawyer
                        // door is on that screen too, under "Are you a
                        // lawyer?", so neither choice is a dead end.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Already have an account?',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: AppColors.ink.withValues(alpha: 0.55),
                              ),
                            ),
                            TextButton(
                              onPressed: () => context.push('/login'),
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Login',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.art,
    required this.title,
    required this.blurb,
    required this.onTap,
  });

  final Widget art;
  final String title;
  final String blurb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.ink.withValues(alpha: 0.07)),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              art,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      blurb,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.ink.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 20,
                color: AppColors.ink.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The artwork on a role card.
///
/// Drawn rather than shipped as an image. The mockup shows two illustrated
/// portraits; this project carries no illustration assets, and inventing
/// stock photographs of people is not something the app should ship — so the
/// art is built from the brand's own shapes, tinted navy for the client and
/// gold for the lawyer. Swapping either for a real illustration later is a
/// one-widget change.
class _RoleArt extends StatelessWidget {
  const _RoleArt({required this.tint, required this.badge});

  final Color tint;

  /// The mark in the corner that says which of the two this is: a magnifier
  /// for someone looking, a gavel for someone practising.
  final IconData badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 82,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 76,
            height: 82,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tint.withValues(alpha: 0.20),
                  tint.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: const Alignment(0, 0.2),
              child: Icon(Icons.person_rounded, size: 44, color: tint),
            ),
          ),
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.12),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Icon(badge, size: 15, color: tint),
            ),
          ),
        ],
      ),
    );
  }
}

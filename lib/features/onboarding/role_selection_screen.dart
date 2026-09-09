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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'Welcome to',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.ink.withValues(alpha: 0.55),
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                'JusticeLand',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose how you want to continue',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.ink.withValues(alpha: 0.5),
                    ),
              ),
              const SizedBox(height: 32),

              _RoleCard(
                icon: Icons.person_search_rounded,
                title: 'I am a User',
                blurb: 'Get legal help from verified lawyers',
                onTap: () => context.go('/'),
              ),
              const SizedBox(height: 14),
              _RoleCard(
                icon: Icons.gavel_rounded,
                title: 'I am a Lawyer',
                blurb: 'Join as a lawyer and help people',
                onTap: () => context.go('/advocate/register'),
              ),

              const Spacer(),
              // One line, two destinations. Which login a returning visitor
              // wants depends on which of the two they are, and the only
              // honest way to ask that is the choice they just made — so this
              // sends clients to theirs and says so.
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
                    child: const Text('Log in'),
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

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.blurb,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String blurb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.ink.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, size: 26, color: AppColors.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
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

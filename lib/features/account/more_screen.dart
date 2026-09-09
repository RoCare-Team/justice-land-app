import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../../state/auth_controller.dart';

/// Everything that is neither a task nor a setting: the policies, the way to
/// reach a person, and the way out.
///
/// The policy pages are the website's own, opened in a browser rather than
/// copied into the app. They are legal text that changes without an app
/// release, and a stale copy of terms shipped in a binary is worse than a link.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _Group(
            children: [
              _Item(
                icon: Icons.shield_outlined,
                label: 'Privacy & Security',
                onTap: () => _openOnWeb(context, '/privacy'),
              ),
              _Item(
                icon: Icons.help_outline_rounded,
                label: 'Help & Support',
                onTap: () => context.push('/contact'),
              ),
              _Item(
                icon: Icons.info_outline_rounded,
                label: 'About Justiceland',
                onTap: () => _openOnWeb(context, '/about'),
              ),
              _Item(
                icon: Icons.description_outlined,
                label: 'Terms & Conditions',
                onTap: () => _openOnWeb(context, '/terms'),
              ),
              _Item(
                icon: Icons.gavel_rounded,
                label: 'Disclaimer',
                onTap: () => _openOnWeb(context, '/disclaimer'),
              ),
              _Item(
                icon: Icons.currency_rupee_rounded,
                label: 'Refund Policy',
                onTap: () => _openOnWeb(context, '/refund'),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // A lawyer's own entrance. Signed in as one it is their dashboard;
          // signed out it is the invitation to list a practice, which is what
          // the website's header offers in the same spot.
          _Group(
            children: [
              if (auth.isAdvocate)
                _Item(
                  icon: Icons.dashboard_outlined,
                  label: 'Advocate Dashboard',
                  onTap: () => context.go('/dashboard'),
                )
              else ...[
                _Item(
                  icon: Icons.balance_rounded,
                  label: 'Register your practice',
                  onTap: () => context.push('/advocate/register'),
                ),
                _Item(
                  icon: Icons.login_rounded,
                  label: 'Lawyer sign in',
                  onTap: () => context.push('/advocate/login'),
                ),
              ],
            ],
          ),

          if (auth.isSignedIn) ...[
            const SizedBox(height: 14),
            _Group(
              children: [
                _Item(
                  icon: Icons.logout_rounded,
                  label: 'Logout',
                  tone: AppColors.danger,
                  onTap: () => _confirmLogout(context, auth),
                ),
              ],
            ),
          ],

          const SizedBox(height: 26),
          Center(
            child: Column(
              children: [
                Text(
                  AppConfig.appName,
                  style: TextStyle(
                    fontFamily: AppText.display,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Version ${AppConfig.version}',
                  style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openOnWeb(BuildContext context, String path) async {
    final url = Uri.parse('${AppConfig.baseUrl}$path');
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      Toast.error(context, 'Could not open $path.');
    }
  }

  Future<void> _confirmLogout(BuildContext context, AuthController auth) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You can sign back in with the same mobile number. Your '
          'consultations and wallet stay on the account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (yes != true) return;
    await auth.signOut();
    if (context.mounted) context.go('/');
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 48, color: AppColors.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tone ?? AppColors.inkMuted),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: tone ?? AppColors.ink,
                ),
              ),
            ),
            if (tone == null)
              Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

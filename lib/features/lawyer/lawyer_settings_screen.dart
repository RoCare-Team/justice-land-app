import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../services/dashboard_service.dart';
import '../../state/auth_controller.dart';
import 'lawyer_widgets.dart';

/// Signs the lawyer out after asking. Shared by Profile and Settings.
Future<void> confirmLawyerLogout(BuildContext context) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Log out?'),
      content: const Text(
        'You will stop receiving consultation requests on this phone until you '
        'sign back in with your mobile number.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  await context.read<AuthController>().signOut();
  if (context.mounted) context.go('/advocate/login');
}

class LawyerSettingsScreen extends StatelessWidget {
  const LawyerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final advocate = context.watch<AuthController>().advocate;

    return LawyerPage(
      title: 'Settings',
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomGutter(context)),
        children: [
          _group([
            _item(context, Icons.person_outline_rounded, 'Account Settings', () => context.push('/dashboard/profile')),
            _item(context, Icons.event_available_outlined, 'Availability', () => context.push('/lawyer/availability')),
            _item(context, Icons.currency_rupee_rounded, 'Consultation Fees', () => context.push('/dashboard/profile')),
            _item(context, Icons.account_balance_wallet_outlined, 'Earnings', () => context.push('/lawyer/earnings')),
            _item(context, Icons.notifications_none_rounded, 'Notifications', () => context.push('/lawyer/notifications')),
          ]),
          const SizedBox(height: 14),
          _group([
            if (advocate != null && advocate.isPublished)
              _item(context, Icons.open_in_new_rounded, 'View Public Profile',
                  () => _openWeb(context, '/lawyers/${advocate.profilePath}')),
            _item(context, Icons.help_outline_rounded, 'Help & Support', () => context.push('/contact')),
            _item(context, Icons.privacy_tip_outlined, 'Privacy Policy', () => _openWeb(context, '/privacy')),
            _item(context, Icons.description_outlined, 'Terms & Conditions', () => _openWeb(context, '/terms')),
          ]),
          const SizedBox(height: 14),
          _group([
            _item(context, Icons.logout_rounded, 'Logout', () => confirmLawyerLogout(context), tone: AppColors.danger),
            _item(context, Icons.delete_forever_outlined, 'Delete account', () => _confirmDelete(context), tone: AppColors.danger),
          ]),
          const SizedBox(height: 22),
          Center(
            child: Text(
              '${AppConfig.appName} for Lawyers · Version ${AppConfig.version}',
              style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(List<Widget> children) {
    return LCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 56, color: AppColors.border),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String label, VoidCallback onTap, {Color? tone}) {
    return ListTile(
      leading: Icon(icon, color: tone ?? AppColors.primary),
      title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: tone ?? AppColors.ink)),
      trailing: tone == null ? Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint) : null,
      onTap: onTap,
    );
  }

  Future<void> _openWeb(BuildContext context, String path) async {
    final opened = await launchUrl(Uri.parse('${AppConfig.baseUrl}$path'), mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) Toast.error(context, 'Could not open $path.');
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently closes your lawyer account and removes you from the '
          'directory. It cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    try {
      await context.read<DashboardService>().deleteAccount();
      if (!context.mounted) return;
      await context.read<AuthController>().signOut();
      if (context.mounted) context.go('/');
    } on ApiException catch (e) {
      if (context.mounted) Toast.error(context, e.message);
    }
  }
}

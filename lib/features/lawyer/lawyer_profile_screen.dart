import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/verified_badge.dart';
import '../../state/auth_controller.dart';
import '../../state/lawyer_controller.dart';
import 'lawyer_settings_screen.dart' show confirmLawyerLogout;
import 'lawyer_widgets.dart';
import 'profile_completion_card.dart';

/// The lawyer's own profile, as the practice is set up — and the way into
/// everything that manages it.
class LawyerProfileScreen extends StatelessWidget {
  const LawyerProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final advocate = context.watch<AuthController>().advocate;
    final lawyer = context.watch<LawyerController>();
    if (advocate == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(
        title: const Text('My Profile'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/dashboard/profile'),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<AuthController>().refresh(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomGutter(context)),
          children: [
            LCard(
              child: Column(
                children: [
                  Avatar(name: advocate.name, photo: advocate.photo, size: 88, online: lawyer.available),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          'Adv. ${advocate.name.replaceFirst(RegExp(r'^Adv\.?\s*', caseSensitive: false), '')}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: AppText.display, fontSize: 21, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  advocate.verified ? const VerifiedBadge() : const VerificationPendingBadge(),
                  if (advocate.legalCareId.isNotEmpty)
                    Text(advocate.legalCareId, style: TextStyle(fontSize: 12, letterSpacing: 0.5, color: AppColors.inkFaint)),
                  const SizedBox(height: 6),
                  if (advocate.reviews > 0)
                    RatingStars(rating: advocate.rating, reviews: advocate.reviews, size: 16)
                  else
                    Text('No reviews yet', style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint)),
                  const SizedBox(height: 10),
                  if (!advocate.isPublished)
                    const NoticeBanner(
                      tone: ChipTone.warning,
                      icon: Icons.hourglass_top_rounded,
                      message: 'Under review — your profile goes public once approved.',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const ProfileCompletionCard(),
            const SizedBox(height: 12),
            LCard(
              child: Column(
                children: [
                  _detail('Bar Council ID', advocate.barCouncilNumber),
                  _detail(
                    'In-person consultation',
                    advocate.consultationFee > 0
                        ? '${Fmt.money(advocate.consultationFee)} per visit'
                        : 'Not offered',
                  ),
                  _detail('Experience', Fmt.experience(advocate.experience)),
                  _detail('Languages', advocate.languages.join(', ')),
                  _detail('Location', [advocate.city, advocate.state].where((s) => s.isNotEmpty).join(', ')),
                ],
              ),
            ),
            if (advocate.specializations.isNotEmpty) ...[
              const SizedBox(height: 12),
              LCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Specialization', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    ChipWrap(children: [for (final s in advocate.specializations) Tag(label: s, tone: AppColors.primary)]),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            LCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Consultation Fees', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  _fee(Icons.chat_bubble_outline_rounded, 'Chat Consultation', advocate.chatRate),
                  _fee(Icons.call_outlined, 'Audio Consultation', advocate.audioRate),
                  _fee(Icons.videocam_outlined, 'Video Consultation', advocate.videoRate),
                ],
              ),
            ),
            const SizedBox(height: 12),
            LCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _link(context, Icons.verified_user_outlined, 'Verification & practice areas', '/lawyer/onboarding'),
                  _link(context, Icons.inbox_outlined, 'Client Queries', '/lawyer/queries'),
                  _link(context, Icons.workspace_premium_outlined, 'My Plan', '/lawyer/plan'),
                  _link(context, Icons.account_balance_wallet_outlined, 'Earnings', '/lawyer/earnings'),
                  _link(context, Icons.toggle_on_outlined, 'Availability', '/lawyer/availability'),
                  _link(context, Icons.notifications_none_rounded, 'Notifications', '/lawyer/notifications'),
                  _link(context, Icons.settings_outlined, 'Settings', '/lawyer/settings'),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded, color: AppColors.danger),
                    title: const Text('Logout', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                    onTap: () => confirmLawyerLogout(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted))),
          Flexible(
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fee(IconData icon, String label, int rate) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
          Text(
            rate > 0 ? Fmt.rate(rate) : 'Not offered',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: rate > 0 ? AppColors.ink : AppColors.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _link(BuildContext context, IconData icon, String label, String route) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
      onTap: () => context.push(route),
    );
  }
}

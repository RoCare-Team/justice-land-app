import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../state/auth_controller.dart';
import '../../state/lawyer_controller.dart';
import 'lawyer_home_screen.dart' show OnlineSwitch;
import 'lawyer_widgets.dart';

/// Availability: the online switch, which channels are on and at what rate,
/// and the office hours on the profile.
///
/// A channel is "on" when it has a rate — that is the platform's own rule, so
/// turning one off or changing its price happens in the profile editor where
/// the rates live, rather than through a second, disagreeing set of toggles.
class LawyerAvailabilityScreen extends StatelessWidget {
  const LawyerAvailabilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    final advocate = context.watch<AuthController>().advocate;
    final on = lawyer.available;

    return LawyerPage(
      title: 'Availability',
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomGutter(context)),
        children: [
          LCard(
            child: Row(
              children: [
                Icon(on ? Icons.check_circle_rounded : Icons.do_not_disturb_on_outlined,
                    color: on ? AppColors.success : AppColors.inkFaint, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        on ? 'You are Online' : 'You are Offline',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: on ? const Color(0xFF15803D) : AppColors.ink),
                      ),
                      Text(
                        on ? 'You can receive new consultations.' : 'New requests are refused until you switch on.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
                const OnlineSwitch(),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionTitle(
            title: 'Consultation Types',
            action: 'Edit rates',
            onAction: () => context.push('/dashboard/profile'),
          ),
          LCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _channel(Icons.chat_bubble_outline_rounded, 'Chat Consultation', advocate?.chatRate ?? 0),
                Divider(height: 1, indent: 56, color: AppColors.border),
                _channel(Icons.call_outlined, 'Audio Call', advocate?.audioRate ?? 0),
                Divider(height: 1, indent: 56, color: AppColors.border),
                _channel(Icons.videocam_outlined, 'Video Call', advocate?.videoRate ?? 0),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Audio calls ring on your registered mobile number, not in the app.',
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
          const SizedBox(height: 18),
          SectionTitle(
            title: 'Office Hours',
            action: 'Edit',
            onAction: () => context.push('/dashboard/profile'),
          ),
          if (advocate == null || advocate.officeTiming.isEmpty)
            const EmptyCard(
              icon: Icons.schedule_rounded,
              title: 'No office hours added',
              message: 'Add them in your profile so clients know when to visit.',
            )
          else
            LCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  for (final h in advocate.officeTiming)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(h.day, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                          Text(
                            h.open ? h.hours : 'Closed',
                            style: TextStyle(fontSize: 13.5, color: h.open ? AppColors.ink : AppColors.danger),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _channel(IconData icon, String label, int rate) {
    final offered = rate > 0;
    return ListTile(
      leading: Icon(icon, color: offered ? AppColors.primary : AppColors.inkFaint),
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(offered ? Fmt.rate(rate) : 'Not offered — no rate set',
          style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
      trailing: Icon(
        offered ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
        color: offered ? AppColors.primary : AppColors.inkFaint,
      ),
    );
  }
}

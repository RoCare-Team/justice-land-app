import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import 'onboarding_controller.dart';
import 'onboarding_shell.dart';

/// Step 1 — Bar Council ID and the two documents the team checks before a
/// profile goes live. Nothing here is shown to clients.
class StepVerification extends StatelessWidget {
  const StepVerification({super.key});

  Future<void> _pick(BuildContext context, OnboardingController c, String kind) async {
    if (c.uploadingKind.isNotEmpty) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final file = picked?.files.single;
    if (file == null || file.path == null || !context.mounted) return;
    if (file.size > OnboardingController.maxDocBytes) {
      Toast.error(context, 'That file is over 5 MB. Please choose a smaller one.');
      return;
    }
    final problem = await c.uploadDoc(kind: kind, path: file.path!, name: file.name);
    if (problem != null && context.mounted) Toast.error(context, problem);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OnboardingController>();

    return OnboardingShell(
      step: 0,
      title: 'Professional Verification',
      subtitle: 'Verify your credentials to start accepting clients',
      headerAction: const OnbLaterButton(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          _whyCard(),
          const SizedBox(height: 14),
          OnbCard(
            title: 'Bar Council Details',
            children: [
              OnbField(
                label: 'Bar Council ID *',
                controller: c.barCouncil,
                hint: 'e.g., D/1234/2015',
                textCapitalization: TextCapitalization.characters,
                padBottom: 0,
              ),
            ],
          ),
          OnbCard(
            title: 'Document Upload',
            children: [
              for (var i = 0; i < OnboardingController.docKinds.length; i++) ...[
                if (i > 0) Divider(height: 26, color: AppColors.border),
                _DocRow(
                  doc: OnboardingController.docKinds[i],
                  uploaded: c.docs[OnboardingController.docKinds[i].kind]?.fileName,
                  busy: c.uploadingKind == OnboardingController.docKinds[i].kind,
                  onTap: () => _pick(context, c, OnboardingController.docKinds[i].kind),
                ),
              ],
            ],
          ),
          const NoticeBanner(
            tone: ChipTone.warning,
            icon: Icons.schedule_rounded,
            message: 'Verification usually takes 24–48 hours. You\'ll be notified once approved.',
          ),
          const SizedBox(height: 14),
          OnbMessages(controller: c),
        ],
      ),
      primaryLabel: 'Continue',
      busy: c.saving,
      onPrimary: c.canContinueVerification ? c.continueVerification : null,
    );
  }

  Widget _whyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.verified_user_outlined, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Why verification?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
                const SizedBox(height: 4),
                Text(
                  'We verify every lawyer to keep trust and quality on the platform, so clients '
                  'connect with genuine legal professionals. Your documents are never shown to clients.',
                  style: TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.primary.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({required this.doc, required this.uploaded, required this.busy, required this.onTap});

  final OnboardingDoc doc;
  final String? uploaded;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = uploaded != null;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: busy ? null : onTap,
      child: Row(
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: done ? AppColors.successSoft : AppColors.muted,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              done ? Icons.check_circle_rounded : doc.icon,
              color: done ? AppColors.success : AppColors.inkMuted,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  busy
                      ? 'Uploading…'
                      : done
                          ? uploaded!
                          : 'PDF, JPG or PNG (max 5 MB)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: done ? AppColors.success : AppColors.inkFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(13),
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Icon(done ? Icons.refresh_rounded : Icons.file_upload_outlined, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

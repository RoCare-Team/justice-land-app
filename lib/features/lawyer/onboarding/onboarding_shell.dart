import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import 'onboarding_controller.dart';

/// "Later" in the header: leave onboarding and finish from the profile. Kept so a
/// lawyer without their documents to hand is never trapped on the first step.
class OnbLaterButton extends StatelessWidget {
  const OnbLaterButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () async {
        final controller = context.read<OnboardingController>();
        if (controller.saving) return;
        await controller.skipAll();
        if (!context.mounted) return;
        Toast.show(context, 'You can finish this any time from your profile.');
        context.go('/lawyer');
      },
      style: TextButton.styleFrom(foregroundColor: Colors.white70),
      child: const Text('Later', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }
}

/// The step's failure (red) and neutral note, when there is one.
class OnbMessages extends StatelessWidget {
  const OnbMessages({super.key, required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      children: [
        if (c.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: NoticeBanner(tone: ChipTone.danger, icon: Icons.error_outline_rounded, message: c.error),
          ),
        if (c.notice.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: NoticeBanner(tone: ChipTone.neutral, message: c.notice),
          ),
      ],
    );
  }
}

/// The frame every onboarding step sits in: a navy gradient header with the
/// step's title and a five-segment progress bar, the step's own scrolling body,
/// and a sticky bottom bar with the primary button.
class OnboardingShell extends StatelessWidget {
  const OnboardingShell({
    super.key,
    required this.step,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.busy = false,
    this.onBack,
    this.headerAction,
    this.secondaryLabel,
    this.onSecondary,
    this.primaryIcon,
  });

  /// 0-based index of this step.
  final int step;
  final String title;
  final String subtitle;
  final Widget body;
  final String primaryLabel;

  /// Null disables the button — the step is not valid yet.
  final VoidCallback? onPrimary;
  final bool busy;
  final IconData? primaryIcon;

  /// Null hides the back arrow (the first step has nowhere to go back to).
  final VoidCallback? onBack;
  final Widget? headerAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.muted,
      // The header is navy, so the status bar's icons have to be the light ones —
      // the theme's default is dark, which would print the clock and battery
      // dark-on-navy. Same as the lawyer home, which does it in HeaderStatusBand.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Column(
          children: [
            _Header(
              step: step,
              title: title,
              subtitle: subtitle,
              onBack: onBack,
              action: headerAction,
            ),
            Expanded(child: body),
            _BottomBar(
              label: primaryLabel,
              icon: primaryIcon,
              onPressed: onPrimary,
              busy: busy,
              secondaryLabel: secondaryLabel,
              onSecondary: onSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.action,
  });

  final int step;
  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        // The lawyer home's own header: same gradient, same corner.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    if (onBack != null)
                      IconButton(
                        onPressed: onBack,
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                        constraints: const BoxConstraints(minWidth: 40),
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      ),
                    const Spacer(),
                    if (action != null) action!,
                  ],
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: AppText.display,
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(fontSize: 14.5, height: 1.4, color: Colors.white.withValues(alpha: 0.78)),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (var i = 0; i < OnboardingController.stepCount; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: i <= step ? AppColors.accent : Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.busy,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrimaryButton(label: label, icon: icon, busy: busy, onPressed: onPressed),
              if (secondaryLabel != null)
                TextButton(
                  onPressed: busy ? null : onSecondary,
                  child: Text(
                    secondaryLabel!,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A white rounded card with an optional heading — the step's basic surface.
class OnbCard extends StatelessWidget {
  const OnbCard({super.key, required this.children, this.title, this.subtitle, this.margin});

  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      // The theme's card: 18px corners, a hairline border, no shadow.
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Text(
              title!,
              style: const TextStyle(fontFamily: AppText.display, fontSize: 19, fontWeight: FontWeight.w700),
            ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.inkMuted)),
          ],
          if (title != null || subtitle != null) const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// A labelled text field. A trailing `*` in [label] is drawn in red, like the
/// mock-ups.
class OnbField extends StatelessWidget {
  const OnbField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.digitsOnly = false,
    this.helper,
    this.helperColor,
    this.suffix,
    this.padBottom = 14,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLength;
  final bool digitsOnly;
  final String? helper;
  final Color? helperColor;
  final Widget? suffix;
  final double padBottom;

  @override
  Widget build(BuildContext context) {
    final required = label.endsWith('*');
    final text = required ? label.substring(0, label.length - 1).trimRight() : label;
    return Padding(
      padding: EdgeInsets.only(bottom: padBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: text,
              children: [
                if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.danger)),
              ],
            ),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            maxLength: maxLength,
            inputFormatters: digitsOnly ? [_DigitsOnly()] : null,
            decoration: InputDecoration(hintText: hint, counterText: '', suffixIcon: suffix),
          ),
          if (helper != null && helper!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(helper!, style: TextStyle(fontSize: 12.5, height: 1.35, color: helperColor ?? AppColors.inkFaint)),
          ],
        ],
      ),
    );
  }
}

class _DigitsOnly extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits == newValue.text) return newValue;
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

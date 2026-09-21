import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import 'onboarding_controller.dart';
import 'onboarding_shell.dart';

/// Step 4 — where consultation earnings are paid. Can be skipped and finished
/// later from the earnings screen; the account number is sealed on the server.
class StepEarnings extends StatelessWidget {
  const StepEarnings({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OnboardingController>();
    final saved = c.savedAccount;

    String? warn(String text, bool valid, String message) =>
        text.trim().isEmpty || valid ? null : message;

    return OnboardingShell(
      step: 3,
      title: 'Earnings Setup',
      subtitle: 'Where should we send your consultation payments?',
      onBack: c.canGoBack ? c.back : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.successSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.success, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bank-level Security', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        'Your details are encrypted and securely stored. We only use this to deposit your earnings.',
                        style: TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (saved != null)
            OnbCard(
              children: [
                Row(
                  children: [
                    Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: AppColors.successSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Bank account added', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(
                            '${saved.holderName} · ${saved.bankName.isEmpty ? 'Bank' : saved.bankName} ••••${saved.accountLast4}',
                            style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            OnbCard(
              children: [
                Row(
                  children: [
                    Container(
                      height: 46,
                      width: 46,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.account_balance_rounded, color: AppColors.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Bank Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('For direct NEFT/RTGS transfers', style: TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                OnbField(
                  label: 'Account Holder Name *',
                  controller: c.holder,
                  hint: 'As per bank records',
                  textCapitalization: TextCapitalization.words,
                ),
                OnbField(
                  label: 'Bank Name *',
                  controller: c.bankName,
                  hint: 'E.g., HDFC Bank',
                  textCapitalization: TextCapitalization.words,
                ),
                OnbField(
                  label: 'Account Number *',
                  controller: c.accountNumber,
                  hint: 'Enter 9–18 digit number',
                  keyboardType: TextInputType.number,
                  digitsOnly: true,
                  maxLength: 18,
                  helper: warn(c.accountNumber.text, Validators.isAccountNumber(c.accountNumber.text),
                      'Account numbers are 9 to 18 digits.'),
                  helperColor: AppColors.danger,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: OnbField(
                        label: 'IFSC Code *',
                        controller: c.ifsc,
                        hint: 'E.g., HDFC0001...',
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 11,
                        helper: warn(c.ifsc.text, Validators.isIfsc(c.ifsc.text), '11 characters, like HDFC0001234.'),
                        helperColor: AppColors.danger,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OnbField(
                        label: 'PAN Number *',
                        controller: c.pan,
                        hint: 'E.g., ABCDE1234F',
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 10,
                        helper: warn(c.pan.text, Validators.isPan(c.pan.text), '10 characters, like ABCDE1234F.'),
                        helperColor: AppColors.danger,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.muted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: AppColors.inkMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Name on PAN card and Bank Account must match.',
                          style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.inkMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          OnbMessages(controller: c),
        ],
      ),
      primaryLabel: saved != null ? 'CONTINUE' : 'SAVE & CONTINUE',
      busy: c.saving,
      onPrimary: c.canContinueEarnings ? c.continueEarnings : null,
      secondaryLabel: 'Skip for now',
      onSecondary: c.skipEarnings,
    );
  }
}

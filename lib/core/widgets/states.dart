import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';

/// The four things a screen can be showing besides content: loading, empty,
/// broken, and done. Having them in one place is why every screen in the app
/// handles all four — a screen that only draws the happy path is the one that
/// shows a blank white rectangle when the network drops.

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            height: 28,
            width: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: TextStyle(color: AppColors.inkMuted, fontSize: 14)),
          ],
        ],
      ),
    );
  }
}

/// Skeleton rows. Used where the shape of what is coming is known — a list of
/// lawyer cards — because a grey outline of the real thing reads as "nearly
/// there" while a spinner reads as "stuck".
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 5, this.height = 120});

  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: AppColors.ink.withOpacity(0.06),
        highlightColor: AppColors.ink.withOpacity(0.02),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

/// Something went wrong, with a way out of it.
///
/// [isNetwork] changes the wording rather than the layout: "check your
/// connection" is actionable, "server error" is not, and telling someone the
/// wrong one wastes their time.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.isNetwork = false,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool isNetwork;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 56,
          width: 56,
          decoration: BoxDecoration(
            color: AppColors.dangerSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isNetwork ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
            color: AppColors.danger,
            size: 26,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          isNetwork ? 'No connection' : 'Something went wrong',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.inkMuted, fontSize: 13.5, height: 1.5),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ],
    );

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32, vertical: compact ? 24 : 48),
        child: content,
      ),
    );
  }
}

/// Nothing here — and, where it helps, something to do about it.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_rounded,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 60,
              width: 60,
              decoration: BoxDecoration(
                color: AppColors.ink.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: AppColors.inkFaint),
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkMuted, fontSize: 13.5, height: 1.5),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// The end of a flow that worked — registration, a top-up, a sent enquiry.
class SuccessView extends StatelessWidget {
  const SuccessView({
    super.key,
    required this.title,
    this.message,
    this.primaryAction,
    this.secondaryAction,
    this.icon = Icons.check_circle_rounded,
  });

  final String title;
  final String? message;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 76,
              width: 76,
              decoration: const BoxDecoration(
                color: AppColors.successSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppColors.success),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (message != null) ...[
              const SizedBox(height: 10),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkMuted, fontSize: 14, height: 1.55),
              ),
            ],
            if (primaryAction != null) ...[
              const SizedBox(height: 28),
              SizedBox(width: double.infinity, child: primaryAction!),
            ],
            if (secondaryAction != null) ...[
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: secondaryAction!),
            ],
          ],
        ),
      ),
    );
  }
}

/// A short, non-blocking message. Kept as one helper so tone stays consistent:
/// red is reserved for something that actually failed.
class Toast {
  const Toast._();

  static void show(BuildContext context, String message) =>
      _show(context, message, AppColors.secondary, Icons.info_outline_rounded);

  static void success(BuildContext context, String message) =>
      _show(context, message, AppColors.success, Icons.check_circle_outline_rounded);

  static void error(BuildContext context, String message) =>
      _show(context, message, AppColors.danger, Icons.error_outline_rounded);

  static void _show(
    BuildContext context,
    String message,
    Color background,
    IconData icon,
  ) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: background,
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }
}

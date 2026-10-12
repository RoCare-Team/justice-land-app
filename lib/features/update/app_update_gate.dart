import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../services/app_update_service.dart';

/// Asks the server whether this build should be updated (GET /api/app/version)
/// and, when it should, says so over the whole app:
///
/// * `force` — a full screen with only an Update button. The build is no
///   longer supported, so nothing else in the app can be used until it is
///   updated.
/// * `optional` — a card with Update and Later. Later hides it only until
///   the user next comes back to the app: every launch, and every return from
///   another app, asks again.
///
/// Checked on launch and whenever the app comes back to the foreground.
/// Whether to force an update is decided in the admin panel, not here. Wraps the app (MaterialApp.builder); the app stays
/// the first child of the same Stack, so it is never rebuilt from scratch.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child, this.service});

  final Widget child;

  /// For tests; the app's own ApiClient otherwise.
  final AppUpdateService? service;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  late final AppUpdateService _service =
      widget.service ?? AppUpdateService(context.read<ApiClient>());
  late final AppLifecycleListener _lifecycle;

  AppUpdate? _update;

  /// Later was pressed since the user last came back to the app.
  bool _laterThisVisit = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    unawaited(_check());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Back from another app (or the home screen): an optional update asks
  /// again straight away, from what is already known, while the server is
  /// asked afresh.
  void _onResume() {
    if (_laterThisVisit) setState(() => _laterThisVisit = false);
    unawaited(_check());
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final update = await _service.check();
      // No answer keeps whatever was known: an update that was forced a
      // minute ago is still forced when the network drops.
      if (update != null && mounted) setState(() => _update = update);
    } finally {
      _checking = false;
    }
  }

  void _later() => setState(() => _laterThisVisit = true);

  Future<void> _openStore() async {
    final url = _update?.storeUrl ?? '';
    final uri = Uri.tryParse(url.isNotEmpty ? url : _fallbackStoreUrl);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('AppUpdateGate: could not open the store: $e');
    }
  }

  static String get _fallbackStoreUrl => defaultTargetPlatform ==
          TargetPlatform.iOS
      ? 'https://apps.apple.com/'
      : 'https://play.google.com/store/apps/details?id=com.justiceland.care';

  @override
  Widget build(BuildContext context) {
    final update = _update;
    final kind = update?.kind ?? UpdateKind.none;
    final showOptional = kind == UpdateKind.optional && !_laterThisVisit;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (kind == UpdateKind.force)
          Positioned.fill(
              child: _ForceUpdate(update: update!, onUpdate: _openStore))
        else if (showOptional)
          Positioned.fill(
              child: _OptionalUpdate(
                  update: update!, onUpdate: _openStore, onLater: _later)),
      ],
    );
  }
}

/// Nothing to do in the app until it is updated.
class _ForceUpdate extends StatelessWidget {
  const _ForceUpdate({required this.update, required this.onUpdate});

  final AppUpdate update;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.primary,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                height: 88,
                width: 88,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.system_update_rounded,
                    color: AppColors.accent, size: 44),
              ),
              const SizedBox(height: 28),
              Text(
                update.title.isNotEmpty ? update.title : 'Update required',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                update.message.isNotEmpty
                    ? update.message
                    : 'This version of ${AppConfig.appName} is no longer supported. '
                        'Update to keep using it.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: Colors.white70, height: 1.5),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onUpdate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Update now',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                update.latestVersion.isNotEmpty
                    ? 'You have ${AppConfig.version} · Latest ${update.latestVersion}'
                    : 'You have ${AppConfig.version}',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A new version, when the user has a moment.
class _OptionalUpdate extends StatelessWidget {
  const _OptionalUpdate(
      {required this.update, required this.onUpdate, required this.onLater});

  final AppUpdate update;
  final VoidCallback onUpdate;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.system_update_rounded,
                          color: AppColors.accent, size: 32),
                      const SizedBox(height: 14),
                      Text(
                        update.title.isNotEmpty
                            ? update.title
                            : 'Update available',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        update.message.isNotEmpty
                            ? update.message
                            : update.latestVersion.isNotEmpty
                                ? 'Version ${update.latestVersion} of ${AppConfig.appName} is ready to install.'
                                : 'A new version of ${AppConfig.appName} is ready to install.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.secondaryLight,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                              onPressed: onLater, child: const Text('Later')),
                          const SizedBox(width: 8),
                          FilledButton(
                              onPressed: onUpdate, child: const Text('Update')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

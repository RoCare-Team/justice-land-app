import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../routing/app_router.dart';
import '../../state/audio_call.dart';

/// The green "call in progress" strip across the top of the whole app while
/// an audio consultation is running and its screen is not showing — the way
/// back to the call after leaving it with back or the arrow, like WhatsApp's.
///
/// Wraps the app (MaterialApp.builder). Its tree never changes shape whether
/// the strip shows or not, so the router beneath is never rebuilt from
/// scratch when a call starts or ends.
class ActiveCallBar extends StatelessWidget {
  const ActiveCallBar({super.key, required this.child});

  final Widget child;

  static final _idle = ValueNotifier<int>(0);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioCall?>(
      valueListenable: AudioCall.current,
      child: child,
      builder: (context, call, app) => ListenableBuilder(
        listenable: call ?? _idle,
        child: app,
        builder: (context, app) {
          final session = call?.session.session;
          final show = call != null && !call.onScreen && session != null && session.status.isLive;
          final media = MediaQuery.of(context);
          return Column(
            children: [
              if (show) _Strip(call: call) else const SizedBox.shrink(),
              Expanded(
                child: MediaQuery(
                  // The strip already sits under the status bar.
                  data: show ? media.removePadding(removeTop: true) : media,
                  child: app!,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.call});

  final AudioCall call;

  @override
  Widget build(BuildContext context) {
    final session = call.session.session!;
    final name = call.isAdvocate ? session.userName : session.advocateName;
    final status = call.connected
        ? Fmt.clock(session.elapsed)
        : call.connecting
            ? 'Connecting…'
            : 'Call paused';

    return Material(
      color: const Color(0xFF15803D),
      child: InkWell(
        onTap: () => AppRouter.instance?.push('/consultation/${call.consultationId}/audio'),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.call_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${name.isEmpty ? 'Consultation' : name} · $status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Tap to return',
                  style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

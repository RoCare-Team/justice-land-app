import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/consultation.dart';
import '../../services/consultation_service.dart';
import '../../state/audio_call.dart';
import '../../state/auth_controller.dart';
import '../../state/session_controller.dart';
import 'session_shell.dart';

/// An audio consultation.
///
/// A view of the running [AudioCall]: the call itself lives outside this
/// screen, so going back — the phone's button or the arrow — leaves it
/// running, and the app-wide bar (ActiveCallBar) brings this screen back.
/// A voice call over the internet, not a phone call: neither side's real
/// number is ever involved.
class AudioCallScreen extends StatefulWidget {
  const AudioCallScreen({super.key, required this.consultationId, this.acceptOnOpen = false});

  final String consultationId;

  /// Opened by the lawyer's Accept: the call sends the accept itself, so the
  /// screen shows at once instead of after the server answers.
  final bool acceptOnOpen;

  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen> {
  late final AudioCall _call;

  @override
  void initState() {
    super.initState();
    _call = AudioCall.open(
      context.read<ConsultationService>(),
      widget.consultationId,
      isAdvocate: context.read<AuthController>().isAdvocate,
      acceptOnOpen: widget.acceptOnOpen,
    )..attach();
  }

  @override
  void dispose() {
    // After this frame: the call may close with it (a request still waiting,
    // or a consultation already over), and this tree still listens to it.
    final call = _call;
    WidgetsBinding.instance.addPostFrameCallback((_) => call.detach());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SessionController>.value(
      value: _call.session,
      child: ListenableBuilder(
        listenable: _call,
        builder: (context, _) => _AudioCallView(call: _call),
      ),
    );
  }
}

class _AudioCallView extends StatelessWidget {
  const _AudioCallView({required this.call});

  final AudioCall call;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final session = controller.session;
    final isAdvocate = call.isAdvocate;

    if (controller.loading && session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audio consultation')),
        body: const LoadingView(label: 'Opening the session…'),
      );
    }

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audio consultation')),
        body: ErrorView(
          message: controller.error ?? 'This consultation could not be opened.',
          onRetry: controller.reload,
        ),
      );
    }

    if (!session.status.isLive) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audio consultation')),
        body: Column(
          children: [
            SessionHeader(session: session, viewerIsAdvocate: isAdvocate),
            Expanded(
              child: session.status.isWaiting
                  ? PendingPanel(
                      session: session,
                      viewerIsAdvocate: isAdvocate,
                      busy: controller.sending,
                      onAccept: controller.accept,
                      onReject: controller.reject,
                      onCancel: () async {
                        await controller.cancel();
                        if (context.mounted) context.pop();
                      },
                    )
                  : EndedPanel(session: session, viewerIsAdvocate: isAdvocate),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _stage(context, session, isAdvocate)),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _topBar(context, session, isAdvocate),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _controls(context, session, isAdvocate, controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stage(BuildContext context, Consultation session, bool isAdvocate) {
    if (call.error.isNotEmpty) {
      return Container(
        color: AppColors.secondary,
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mic_off_rounded, size: 46, color: Colors.white54),
              const SizedBox(height: 16),
              Text(
                call.error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: call.retry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (!call.ready) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Preparing microphone…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    final otherName = isAdvocate ? session.userName : session.advocateName;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                if ((call.connecting || call.reconnecting) && !call.connected)
                  SizedBox(
                    height: 116,
                    width: 116,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                Avatar(name: otherName, size: 96),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              otherName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              call.connected
                  ? 'On call'
                  : call.reconnecting
                      ? 'Reconnecting…'
                      // Both sides join on their own now — the client rings
                      // as soon as the lawyer accepts, the lawyer answers the
                      // ring — so there is nothing to wait on but the line.
                      : (isAdvocate || call.connecting)
                          ? 'Connecting…'
                          : 'Ready when you are.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, height: 1.5),
            ),
            const SizedBox(height: 26),
            if (!isAdvocate && !call.connecting && !call.connected && !call.reconnecting)
              FilledButton.icon(
                onPressed: call.startCall,
                icon: const Icon(Icons.call_rounded),
                label: const Text('Start audio call'),
              )
            else if ((call.connecting || call.reconnecting || isAdvocate) && !call.connected)
              const SizedBox(
                height: 26,
                width: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white54),
              ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, Consultation session, bool isAdvocate) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAdvocate ? session.userName : session.advocateName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  session.awaitingCallClock
                      ? 'Connecting…'
                      : session.isResume
                          ? 'Free resume · ${Fmt.clock(session.elapsed)}'
                          : Fmt.clock(session.elapsed),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(
    BuildContext context,
    Consultation session,
    bool isAdvocate,
    SessionController controller,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleButton(
            icon: call.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            active: call.micOn,
            onTap: call.toggleMic,
          ),
          _circleButton(
            icon: call.speakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
            active: call.speakerOn,
            onTap: call.toggleSpeaker,
          ),
          _circleButton(
            icon: Icons.call_end_rounded,
            active: true,
            danger: true,
            onTap: () async {
              await call.hangUp();
              if (!context.mounted) return;
              // Hanging up the call does not end the consultation — the
              // session is still live and still billing until someone ends it.
              if (await confirmEndSession(context, session) && context.mounted) {
                await endSessionOrExplain(context, controller);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return Material(
      color: danger
          ? AppColors.danger
          : active
              ? Colors.white24
              : Colors.white10,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          height: 58,
          width: 58,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

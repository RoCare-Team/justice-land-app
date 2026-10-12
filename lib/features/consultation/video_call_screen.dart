import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/consultation.dart';
import '../../services/consultation_service.dart';
import '../../state/auth_controller.dart';
import '../../state/session_controller.dart';
import '../../state/video_call.dart';
import 'chat_thread.dart';
import 'session_shell.dart';

/// A video consultation.
///
/// A view of the running [VideoCall]: the call itself lives outside this
/// screen, so going back — the phone's button or the arrow — leaves it
/// running in a small floating window over the rest of the app
/// (VideoCallBubble), and a tap on that window brings this screen back.
class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key, required this.consultationId, this.acceptOnOpen = false});

  final String consultationId;

  /// Opened by the lawyer's Accept: the call sends the accept itself, so the
  /// screen shows at once instead of after the server answers.
  final bool acceptOnOpen;

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  late final VideoCall _call;

  @override
  void initState() {
    super.initState();
    _call = VideoCall.open(
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
        builder: (context, _) => _VideoCallView(call: _call),
      ),
    );
  }
}

class _VideoCallView extends StatelessWidget {
  const _VideoCallView({required this.call});

  final VideoCall call;

  /// Back to wherever the call was opened from; the call carries on in the
  /// floating window. Opened with nothing underneath (a notification, the
  /// lawyer's Accept), home is underneath instead.
  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(call.isAdvocate ? '/lawyer' : '/');
    }
  }

  /// The chat, the way WhatsApp does it: the chat screen takes this screen's
  /// place and the call shrinks into the floating window over it (this
  /// screen going away is what puts the call there). Came here from that
  /// chat (its camera button, or the window): just go back down to it.
  void _openChat(BuildContext context) {
    final chat = '/consultation/${call.consultationId}/chat';
    final matches = GoRouter.of(context).routerDelegate.currentConfiguration.matches;
    final below = matches.length > 1 ? matches[matches.length - 2].matchedLocation : '';
    if (below.startsWith(chat) && context.canPop()) {
      context.pop();
    } else {
      context.pushReplacement('$chat?call=1');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final session = controller.session;
    final isAdvocate = call.isAdvocate;

    if (controller.loading && session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Video consultation')),
        body: const LoadingView(label: 'Opening the session…'),
      );
    }

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Video consultation')),
        body: ErrorView(
          message: controller.error ?? 'This consultation could not be opened.',
          onRetry: controller.reload,
        ),
      );
    }

    if (!session.status.isLive) {
      return Scaffold(
        appBar: AppBar(title: const Text('Video consultation')),
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

    return PopScope(
      // The phone's back button: the same as the arrow, so it can also leave
      // a call that was opened with nothing underneath it.
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.secondary,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: _stage(session, isAdvocate)),
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
                child: _controls(context, session, controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stage(Consultation session, bool isAdvocate) {
    if (call.error.isNotEmpty) {
      return Container(
        color: AppColors.secondary,
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, size: 46, color: Colors.white54),
              const SizedBox(height: 16),
              Text(
                call.error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.5),
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
            Text('Preparing camera…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (!call.connected && !call.connecting) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(
                name: isAdvocate ? session.userName : session.advocateName,
                size: 88,
              ),
              const SizedBox(height: 18),
              Text(
                isAdvocate ? session.userName : session.advocateName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                // Both sides join on their own; nothing to wait on but the line.
                (isAdvocate || call.autoStarted) ? 'Connecting…' : 'Ready when you are.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, height: 1.5),
              ),
              const SizedBox(height: 26),
              if (!isAdvocate && !call.autoStarted)
                FilledButton.icon(
                  onPressed: call.startCall,
                  icon: const Icon(Icons.videocam_rounded),
                  label: const Text('Start video call'),
                )
              else if (session.call?.isRinging ?? false) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => call.answer(accept: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      icon: const Icon(Icons.call_end_rounded, size: 18),
                      label: const Text('Decline'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => call.answer(accept: true),
                      icon: const Icon(Icons.videocam_rounded),
                      label: const Text('Answer'),
                    ),
                  ],
                ),
              ] else
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

    return Stack(
      children: [
        Positioned.fill(
          child: call.connected
              ? RTCVideoView(
                  call.remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 14),
                      Text('Connecting…', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
        ),
        Positioned(
          right: 14,
          bottom: 130,
          child: Container(
            height: 168,
            width: 118,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white24),
              color: Colors.black54,
            ),
            child: call.cameraOn
                ? RTCVideoView(
                    call.localRenderer,
                    mirror: call.frontCamera,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : const Center(
                    child: Icon(Icons.videocam_off_rounded, color: Colors.white54),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _topBar(BuildContext context, Consultation session, bool isAdvocate) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.65), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Keep the call in a small window',
            onPressed: () => _leave(context),
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

  Widget _controls(BuildContext context, Consultation session, SessionController controller) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.75), Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleButton(
            icon: call.speakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
            label: call.speakerOn ? 'Speaker on' : 'Speaker off',
            active: call.speakerOn,
            onTap: call.toggleSpeaker,
          ),
          _circleButton(
            icon: call.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            label: call.micOn ? 'Mute' : 'Unmute',
            active: call.micOn,
            onTap: call.toggleMic,
          ),
          _circleButton(
            icon: call.cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            label: call.cameraOn ? 'Turn camera off' : 'Turn camera on',
            active: call.cameraOn,
            onTap: call.toggleCamera,
          ),
          _circleButton(
            icon: Icons.cameraswitch_rounded,
            label: 'Switch camera',
            active: true,
            onTap: call.switchCamera,
          ),
          // Chat during the call — send a document without hanging up.
          if (session.status.isLive)
            InCallChatButton(
              viewerIsAdvocate: call.isAdvocate,
              size: 54,
              onOpen: () => _openChat(context),
            ),
          _circleButton(
            icon: Icons.call_end_rounded,
            label: 'End call',
            active: true,
            danger: true,
            onTap: () async {
              await call.hangUp();
              if (!context.mounted) return;
              // Hanging up the video does not end the consultation — the
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
    required String label,
    required bool active,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
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
              height: 54,
              width: 54,
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

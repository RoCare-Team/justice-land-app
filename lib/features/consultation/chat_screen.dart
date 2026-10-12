import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/consultation.dart';
import '../../routing/app_router.dart';
import '../../services/consultation_service.dart';
import '../../state/auth_controller.dart';
import '../../state/session_controller.dart';
import 'chat_thread.dart';
import 'session_shell.dart';

/// A live chat consultation.
///
/// Both participants use this same screen — the only differences are who can
/// accept and who can cancel, which the shared panels handle. Messages are
/// re-read from the server on every poll rather than appended locally, so the
/// thread on both phones is the one the server actually stored.
class ChatScreen extends StatelessWidget {
  const ChatScreen({
    super.key,
    required this.consultationId,
    this.acceptOnOpen = false,
    this.duringCall = false,
  });

  final String consultationId;

  /// Opened by the lawyer's Accept: the screen sends the accept itself, so it
  /// shows at once instead of after the server answers.
  final bool acceptOnOpen;

  /// Opened from a video call's Chat button: the call goes on in the floating
  /// window above this screen, as in WhatsApp, so leaving here is just going
  /// back — no "leave the chat?" question — and the header's camera button
  /// returns to the call instead of ending the session.
  final bool duringCall;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          SessionController(context.read<ConsultationService>(), consultationId)
            ..start(acceptFirst: acceptOnOpen),
      child: _ChatView(duringCall: duringCall),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView({required this.duringCall});

  final bool duringCall;

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final auth = context.watch<AuthController>();
    final session = controller.session;
    final isAdvocate = auth.isAdvocate;

    if (controller.loading && session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live chat')),
        body: const LoadingView(label: 'Opening the session…'),
      );
    }

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live chat')),
        body: ErrorView(
          message: controller.error ?? 'This consultation could not be opened.',
          onRetry: controller.reload,
        ),
      );
    }

    // An upload in flight adds a bubble at the bottom too.
    final shown = session.messages.length +
        controller.pendingTexts.length +
        (controller.uploadingName == null ? 0 : 1);
    if (shown != _lastCount) {
      _lastCount = shown;
      _scrollToEnd();
    }

    if (widget.duringCall) {
      return PopScope(
        // Opened in place of the call screen, possibly with nothing beneath
        // (a call opened from a notification): back then goes home.
        canPop: context.canPop(),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) context.go(isAdvocate ? '/lawyer' : '/');
        },
        child: _scaffold(context, session, isAdvocate, controller),
      );
    }

    return PopScope(
      // Leaving does not end the session — it keeps running and billing, which
      // is why the client is told rather than silently charged.
      canPop: !session.status.isLive,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave the chat?'),
            content: const Text(
              'The session stays live and keeps billing while you are away. '
              'End it if you are finished.',
              style: TextStyle(height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Leave it running'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () async {
                  Navigator.of(context).pop(false);
                  if (await confirmEndSession(context, session) && context.mounted) {
                    await endSessionOrExplain(context, controller);
                  }
                },
                child: const Text('End session'),
              ),
            ],
          ),
        );
        if ((leave ?? false) && context.mounted) context.pop();
      },
      child: _scaffold(context, session, isAdvocate, controller),
    );
  }

  Widget _scaffold(
    BuildContext context,
    Consultation session,
    bool isAdvocate,
    SessionController controller,
  ) {
    final active = session.status == ConsultationStatus.active;
    final lowBalance = active && session.endsAt != null && session.remaining.inMinutes < 2;
    return Scaffold(
      backgroundColor: active ? chatWallpaper : AppColors.muted,
      appBar: _ChatAppBar(
        session: session,
        viewerIsAdvocate: isAdvocate,
        actions: [
          if (session.status.isLive && widget.duringCall)
            IconButton(
              tooltip: 'Back to the video call',
              onPressed: () => AppRouter.instance?.push('/consultation/${session.id}/video'),
              icon: const Icon(Icons.videocam_rounded),
            )
          else if (session.status.isLive)
            IconButton(
              tooltip: 'End session',
              onPressed: controller.sending
                  ? null
                  : () async {
                      if (await confirmEndSession(context, session) && context.mounted) {
                        await endSessionOrExplain(context, controller);
                      }
                    },
              icon: const Icon(Icons.call_end_rounded),
              color: const Color(0xFFFF8A80),
            ),
        ],
      ),
      body: Column(
        children: [
          // The full session card only while waiting or once over; a running
          // chat keeps its timer in the header and gives the room to messages.
          if (!active) SessionHeader(session: session, viewerIsAdvocate: isAdvocate),
          if (lowBalance)
            SessionTicker(
              builder: (context) => Container(
                width: double.infinity,
                color: AppColors.dangerSoft,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_bottom_rounded, size: 15, color: AppColors.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isAdvocate
                            ? 'Client\'s balance runs out in ${Fmt.clock(session.remaining)}'
                            : 'Your balance runs out in ${Fmt.clock(session.remaining)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: switch (session.status) {
              ConsultationStatus.pending => PendingPanel(
                  session: session,
                  viewerIsAdvocate: isAdvocate,
                  busy: controller.sending,
                  onAccept: controller.accept,
                  onReject: controller.reject,
                  onCancel: () async {
                    await controller.cancel();
                    if (context.mounted) context.pop();
                  },
                ),
              ConsultationStatus.active => _messages(session, isAdvocate, controller),
              _ => EndedPanel(session: session, viewerIsAdvocate: isAdvocate),
            },
          ),
          if (session.status.isLive) const ChatComposer(),
        ],
      ),
    );
  }

  Widget _messages(Consultation session, bool isAdvocate, SessionController controller) {
    return ChatMessageList(
      messages: session.messages,
      viewerIsAdvocate: isAdvocate,
      controller: _scroll,
      uploadingName: controller.uploadingName,
      uploadProgress: controller.uploadProgress,
      pending: controller.pendingTexts,
      empty: EmptyView(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'The floor is yours',
        message: isAdvocate
            ? 'Say hello — the client is waiting. Use the paperclip to share a document.'
            : 'Describe your matter, or attach the notice or document it is about. The clock is running, so be direct.',
      ),
    );
  }
}

/// WhatsApp's chat header: the other person's picture and name, and under it
/// how long the session has run.
class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ChatAppBar({
    required this.session,
    required this.viewerIsAdvocate,
    this.actions = const [],
  });

  final Consultation session;
  final bool viewerIsAdvocate;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final name = viewerIsAdvocate ? session.userName : session.advocateName;
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,
      title: Row(
        children: [
          Avatar(
            name: name,
            photo: viewerIsAdvocate ? null : session.advocatePhoto,
            size: 38,
            onDark: true,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name.isEmpty ? (viewerIsAdvocate ? 'Client' : 'Advocate') : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                if (session.status.isLive)
                  SessionTicker(builder: (context) => _subtitle(_liveLabel()))
                else
                  _subtitle(session.status.label),
              ],
            ),
          ),
        ],
      ),
      actions: actions,
    );
  }

  String _liveLabel() {
    if (session.status != ConsultationStatus.active) return session.status.label;
    final clock = Fmt.clock(session.elapsed);
    return session.isResume ? 'Free resume · $clock' : 'Live · $clock';
  }

  Widget _subtitle(String text) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.white70,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      );
}

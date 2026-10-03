import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../../models/consultation.dart';
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
  const ChatScreen({super.key, required this.consultationId, this.acceptOnOpen = false});

  final String consultationId;

  /// Opened by the lawyer's Accept: the screen sends the accept itself, so it
  /// shows at once instead of after the server answers.
  final bool acceptOnOpen;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          SessionController(context.read<ConsultationService>(), consultationId)
            ..start(acceptFirst: acceptOnOpen),
      child: const _ChatView(),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView();

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
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Live chat'),
          actions: [
            if (session.status.isLive)
              TextButton.icon(
                onPressed: controller.sending
                    ? null
                    : () async {
                        if (await confirmEndSession(context, session) && context.mounted) {
                          await endSessionOrExplain(context, controller);
                        }
                      },
                icon: const Icon(Icons.call_end_rounded, size: 18),
                label: const Text('End'),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              ),
          ],
        ),
        body: Column(
          children: [
            SessionHeader(session: session, viewerIsAdvocate: isAdvocate),
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
                ConsultationStatus.active => ColoredBox(
                    // The website's chat backdrop, so the bubbles read the same.
                    color: const Color(0xFFF4F6FA),
                    child: _messages(session, isAdvocate, controller),
                  ),
                _ => EndedPanel(session: session, viewerIsAdvocate: isAdvocate),
              },
            ),
            if (session.status.isLive) const ChatComposer(),
          ],
        ),
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

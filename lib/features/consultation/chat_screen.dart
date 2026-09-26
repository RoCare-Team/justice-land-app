import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/states.dart';
import '../../models/consultation.dart';
import '../../services/consultation_service.dart';
import '../../state/auth_controller.dart';
import '../../state/session_controller.dart';
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
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _input.dispose();
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

  Future<void> _send(SessionController controller) async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final ok = await controller.sendMessage(text);
    if (!ok && mounted) {
      // Put the text back rather than losing what they typed.
      _input.text = text;
      Toast.error(context, controller.error ?? 'Could not send the message.');
      controller.clearError();
    }
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

    if (session.messages.length != _lastCount) {
      _lastCount = session.messages.length;
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
                ConsultationStatus.active => _messages(session, isAdvocate),
                _ => EndedPanel(session: session, viewerIsAdvocate: isAdvocate),
              },
            ),
            if (session.status.isLive) _composer(controller),
          ],
        ),
      ),
    );
  }

  Widget _messages(Consultation session, bool isAdvocate) {
    if (session.messages.isEmpty) {
      return EmptyView(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'The floor is yours',
        message: isAdvocate
            ? 'Say hello — the client is waiting.'
            : 'Describe your matter. The clock is running, so be direct.',
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      itemCount: session.messages.length,
      itemBuilder: (context, index) {
        final message = session.messages[index];
        final mine = isAdvocate ? !message.fromUser : message.fromUser;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: mine ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
              border: mine ? null : Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: mine ? Colors.white : AppColors.inkStrong,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Fmt.time(message.at),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: mine ? Colors.white70 : AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _composer(SessionController controller) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                maxLines: 4,
                minLines: 1,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Write a message',
                  counterText: '',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onSubmitted: (_) => _send(controller),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: controller.sending ? null : () => _send(controller),
                child: Container(
                  height: 46,
                  width: 46,
                  alignment: Alignment.center,
                  child: controller.sending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

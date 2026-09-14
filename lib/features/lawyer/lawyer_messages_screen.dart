import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/consultation.dart';
import '../../services/consultation_service.dart';
import '../../state/lawyer_controller.dart';
import 'lawyer_widgets.dart';

/// Every client the lawyer has spoken to, WhatsApp-style: last line, when, and
/// a way into the conversation.
class LawyerMessagesScreen extends StatelessWidget {
  const LawyerMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    final threads = lawyer.clients;

    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(title: const Text('Messages'), automaticallyImplyLeading: false),
      body: RefreshIndicator(
        onRefresh: lawyer.refreshAll,
        child: !lawyer.historyLoaded && threads.isEmpty
            ? const SkeletonList(count: 6, height: 72)
            : threads.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: const [
                      EmptyCard(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'No conversations yet',
                        message: 'Stay online — when a client chats or calls you, they are listed here.',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(0, 8, 0, bottomGutter(context)),
                    itemCount: threads.length,
                    separatorBuilder: (_, __) => Divider(height: 1, indent: 80, color: AppColors.border),
                    itemBuilder: (context, i) => _ThreadRow(thread: threads[i]),
                  ),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread});

  final ClientThread thread;

  String get _preview {
    final last = thread.lastMessage;
    if (last != null) return '${last.from == 'advocate' ? 'You: ' : ''}${last.text}';
    final s = thread.latest;
    return switch (s.status) {
      ConsultationStatus.active => '${s.type.label} in progress',
      ConsultationStatus.pending => 'Waiting for you to accept',
      ConsultationStatus.rejected => 'You declined this request',
      ConsultationStatus.cancelled => 'Client cancelled the request',
      ConsultationStatus.ended =>
        s.talkedMinutes > 0 ? '${s.type.label} ended · ${s.talkedMinutes} mins' : '${s.type.label} ended',
    };
  }

  @override
  Widget build(BuildContext context) {
    final live = thread.sessions.where((s) => s.status.isLive).toList();
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: () {
          // A chat that is still running opens live; anything else opens the
          // saved conversation.
          if (live.isNotEmpty) return openSession(context, live.first);
          final session = thread.threadSession;
          if (session != null) {
            context.push('/lawyer/transcript/${session.id}?name=${Uri.encodeComponent(thread.userName)}');
          } else {
            context.push('/lawyer/client/${thread.userId}');
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Avatar(name: thread.userName, size: 50, online: live.isNotEmpty ? true : null),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            thread.userName.isEmpty ? 'Client' : thread.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          _when(thread.lastMessage?.at ?? thread.lastAt),
                          style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (thread.lastMessage == null) ...[
                          Icon(typeIcon(thread.latest.type), size: 14, color: AppColors.inkFaint),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            _preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                          ),
                        ),
                        if (live.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          const StatusChip(label: 'Live', tone: ChipTone.success),
                        ] else if (thread.messages > 0) ...[
                          const SizedBox(width: 6),
                          CountBadge(count: thread.messages, color: AppColors.primaryLight),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _when(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    if (day == today) return Fmt.time(local);
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return Fmt.date(local);
  }
}

/// A finished conversation, read-only. New messages need a live session.
class TranscriptScreen extends StatefulWidget {
  const TranscriptScreen({super.key, required this.consultationId, this.name = ''});

  final String consultationId;
  final String name;

  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends State<TranscriptScreen> {
  List<ChatMessage>? _messages;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await context.read<ConsultationService>().transcript(widget.consultationId);
      if (mounted) setState(() => _messages = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Avatar(name: widget.name, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name.isEmpty ? 'Client' : widget.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  Text('Saved conversation', style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _error != null
          ? ErrorView(message: _error!.message, isNetwork: _error!.isNetwork, onRetry: _load)
          : messages == null
              ? const LoadingView()
              : messages.isEmpty
                  ? const EmptyView(icon: Icons.chat_bubble_outline_rounded, title: 'No messages', message: 'This consultation had no chat messages.')
                  : Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            itemCount: messages.length,
                            itemBuilder: (_, i) => _Bubble(message: messages[i]),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            color: AppColors.surface,
                            child: Text(
                              'This conversation has ended. New messages happen in a live consultation.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.from == 'advocate';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
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
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.text,
              style: TextStyle(fontSize: 14, height: 1.4, color: mine ? Colors.white : AppColors.ink),
            ),
            const SizedBox(height: 2),
            Text(
              Fmt.time(message.at),
              style: TextStyle(fontSize: 10, color: mine ? Colors.white60 : AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

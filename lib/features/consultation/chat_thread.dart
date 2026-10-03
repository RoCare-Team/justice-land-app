import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/states.dart';
import '../../models/consultation.dart';
import '../../state/session_controller.dart';

/// The chat of a consultation — message list and composer — shared by the
/// chat screen and the chat sheet that opens over a video or audio call, so a
/// document sent mid-call is the same message, in the same thread.
///
/// Files: PDFs, photos, Word, Excel and text up to 10 MB, the same list the
/// website accepts. Photos preview in the bubble (downloaded through the API
/// client, which has the sign-in cookie); everything else opens in the phone's
/// browser or viewer through the message's signed link.

const _docExtensions = [
  'pdf', 'doc', 'docx', 'odt', 'rtf', 'xls', 'xlsx', 'csv', 'txt',
  'jpg', 'jpeg', 'png', 'webp', 'heic',
];

/// The list of messages, plus a bubble for a file still uploading.
class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.viewerIsAdvocate,
    this.controller,
    this.uploadingName,
    this.uploadProgress = 0,
    this.pending = const [],
    this.empty,
    this.showIntro = true,
  });

  final List<ChatMessage> messages;
  final bool viewerIsAdvocate;
  final ScrollController? controller;
  final String? uploadingName;
  final double uploadProgress;

  /// Texts sent but not yet confirmed — drawn as this side's bubbles with a
  /// clock until the server has them.
  final List<String> pending;
  final Widget? empty;

  /// The "Private consultation · billed per minute" pill at the top, as on
  /// the website.
  final bool showIntro;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty && pending.isEmpty && uploadingName == null) {
      return empty ?? const SizedBox.shrink();
    }
    final intro = showIntro ? 1 : 0;
    final count = intro + messages.length + pending.length + (uploadingName == null ? 0 : 1);
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: count,
      itemBuilder: (context, i) {
        if (showIntro && i == 0) return const _IntroPill();
        final index = i - intro;
        if (index >= messages.length + pending.length) {
          return _UploadingBubble(name: uploadingName!, progress: uploadProgress);
        }
        if (index >= messages.length) {
          final p = index - messages.length;
          // Pending ones follow on from whatever this side sent last.
          final grouped = p > 0 ||
              (messages.isNotEmpty &&
                  (viewerIsAdvocate ? !messages.last.fromUser : messages.last.fromUser));
          return _Bubble(
            message: ChatMessage(id: 'pending-$p', from: '', text: pending[p]),
            mine: true,
            grouped: grouped,
            sending: true,
          );
        }
        final message = messages[index];
        final mine = viewerIsAdvocate ? !message.fromUser : message.fromUser;
        final day = _dayLabel(message.at);
        final prevDay = index > 0 ? _dayLabel(messages[index - 1].at) : null;
        final newDay = day != null && day != prevDay;
        // Consecutive lines from one side sit closer, like any messenger.
        final grouped = !newDay && index > 0 && messages[index - 1].from == message.from;
        return Column(
          children: [
            if (newDay) _DaySeparator(label: day),
            _Bubble(message: message, mine: mine, grouped: grouped),
          ],
        );
      },
    );
  }

  static String? _dayLabel(DateTime? at) {
    if (at == null) return null;
    final local = at.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(local.year, local.month, local.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return Fmt.date(local);
  }
}

class _IntroPill extends StatelessWidget {
  const _IntroPill();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 12, color: AppColors.inkFaint),
            const SizedBox(width: 5),
            Text(
              'Private consultation · billed per minute',
              style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    this.grouped = false,
    this.sending = false,
  });
  final ChatMessage message;
  final bool mine;

  /// Follows a message from the same side: tighter gap, no tail corner.
  final bool grouped;

  /// Not yet confirmed by the server — faded, with a clock instead of a tick.
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment;
    final caption = message.caption;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: sending ? 0.75 : 1,
        child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: EdgeInsets.only(top: grouped ? 2 : 8),
        padding: attachment == null
            ? const EdgeInsets.fromLTRB(13, 8, 11, 6)
            : const EdgeInsets.all(5),
        decoration: _bubbleDecoration(mine, grouped: grouped),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachment != null) AttachmentView(attachment: attachment, mine: mine),
            Padding(
              padding: attachment == null
                  ? EdgeInsets.zero
                  : const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Column(
                crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (caption.isNotEmpty)
                    Text(
                      caption,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: mine ? Colors.white : AppColors.inkStrong,
                      ),
                    ),
                  if (caption.isNotEmpty) const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!sending)
                        Text(
                          Fmt.time(message.at),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: mine ? Colors.white70 : AppColors.inkFaint,
                          ),
                        ),
                      // Clock until the server has it, then a tick — the
                      // same as the website.
                      if (mine) ...[
                        const SizedBox(width: 3),
                        Icon(
                          sending ? Icons.schedule_rounded : Icons.done_rounded,
                          size: 13,
                          color: Colors.white70,
                        ),
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
}

/// Rounded all round, with a small "tail" corner on the first bubble of a run
/// — the corner on the sender's side, as on the website.
BoxDecoration _bubbleDecoration(bool mine, {bool grouped = false}) => BoxDecoration(
      color: mine ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
        bottomLeft: Radius.circular(!mine && !grouped ? 6 : 18),
        bottomRight: Radius.circular(mine && !grouped ? 6 : 18),
      ),
      border: mine ? null : Border.all(color: AppColors.border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ],
    );

/// The file inside a bubble: a picture for photos, a tappable card for the rest.
class AttachmentView extends StatelessWidget {
  const AttachmentView({super.key, required this.attachment, required this.mine});
  final ChatAttachment attachment;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage && attachment.url.isNotEmpty) {
      return _ImagePreview(attachment: attachment);
    }
    final icon = attachment.isPdf
        ? Icons.picture_as_pdf_rounded
        : const ['xls', 'xlsx', 'csv'].contains(attachment.extension)
            ? Icons.table_chart_rounded
            : Icons.description_rounded;
    return Material(
      color: mine ? Colors.white.withValues(alpha: 0.12) : AppColors.muted,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openAttachment(context, attachment),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 40,
                width: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: mine
                      ? Colors.white.withValues(alpha: 0.15)
                      : attachment.isPdf
                          ? AppColors.dangerSoft
                          : AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: mine ? Colors.white : attachment.isPdf ? AppColors.danger : AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: mine ? Colors.white : AppColors.inkStrong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${attachment.sizeLabel} · ${attachment.extension.toUpperCase()} · Tap to open',
                      style: TextStyle(
                        fontSize: 11,
                        color: mine ? Colors.white70 : AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: mine ? Colors.white70 : AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens a file in the phone's browser / viewer via its signed link — the
/// app's sign-in cookie does not travel with it, the signature does.
Future<void> openAttachment(BuildContext context, ChatAttachment a) async {
  final path = a.signedUrl.isNotEmpty ? a.signedUrl : a.url;
  final uri = Uri.parse(path.startsWith('http') ? path : '${AppConfig.baseUrl}$path');
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) Toast.error(context, 'Could not open the file.');
}

/// Photo bytes, kept for the life of the app so scrolling back up and every
/// 2-second poll do not download the same picture again.
final Map<String, Future<Uint8List?>> _imageCache = {};

Future<Uint8List?> _loadImage(ChatAttachment a) {
  return _imageCache.putIfAbsent(a.id, () async {
    final bytes = await ApiClient.instance.bytes(a.url);
    if (bytes == null) {
      // Let a later attempt retry instead of caching the failure.
      Future.microtask(() => _imageCache.remove(a.id));
      return null;
    }
    return Uint8List.fromList(bytes);
  });
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.attachment});
  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _loadImage(attachment),
      builder: (context, snap) {
        final bytes = snap.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 220,
            height: 220,
            child: bytes != null
                ? GestureDetector(
                    onTap: () => _showFullImage(context, attachment, bytes),
                    child: Image.memory(bytes, fit: BoxFit.cover),
                  )
                : Container(
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: snap.connectionState == ConnectionState.done
                        ? TextButton.icon(
                            onPressed: () => openAttachment(context, attachment),
                            icon: const Icon(Icons.image_rounded),
                            label: const Text('Open photo'),
                          )
                        : const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                  ),
          ),
        );
      },
    );
  }
}

void _showFullImage(BuildContext context, ChatAttachment a, Uint8List bytes) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(a.name, style: const TextStyle(fontSize: 14)),
          actions: [
            IconButton(
              tooltip: 'Open / download',
              onPressed: () => openAttachment(context, a),
              icon: const Icon(Icons.download_rounded),
            ),
          ],
        ),
        body: Center(
          child: InteractiveViewer(maxScale: 5, child: Image.memory(bytes)),
        ),
      ),
    ),
  );
}

class _UploadingBubble extends StatelessWidget {
  const _UploadingBubble({required this.name, required this.progress});
  final String name;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: _bubbleDecoration(true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.upload_file_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                minHeight: 4,
                backgroundColor: Colors.white24,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sending… ${(progress * 100).round()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// The text field, the paperclip and the send button.
///
/// Reads the [SessionController] above it, so it works the same in the chat
/// screen and inside the in-call sheet.
class ChatComposer extends StatefulWidget {
  const ChatComposer({super.key});

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
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

  Future<void> _attach(SessionController controller) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_rounded, color: AppColors.primary),
              title: const Text('Document'),
              subtitle: const Text('PDF, Word, Excel or text — up to 10 MB'),
              onTap: () => Navigator.of(context).pop('file'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
              title: const Text('Photo from gallery'),
              onTap: () => Navigator.of(context).pop('gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: AppColors.primary),
              title: const Text('Take a photo'),
              subtitle: const Text('Of a notice, an order, any paper'),
              onTap: () => Navigator.of(context).pop('camera'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    String? path;
    String? name;
    int size = 0;
    try {
      if (choice == 'file') {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: _docExtensions,
        );
        final file = picked?.files.single;
        path = file?.path;
        name = file?.name;
        size = file?.size ?? 0;
      } else {
        final file = await ImagePicker().pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          // A legible document photo at a fraction of the camera's size —
          // it goes up over mobile data, mid-consultation.
          maxWidth: 2000,
          imageQuality: 80,
        );
        if (file != null) {
          path = file.path;
          name = file.name;
          size = await file.length();
        }
      }
    } catch (_) {
      if (mounted) Toast.error(context, 'Could not open the picker. Check the app permissions.');
      return;
    }

    if (path == null || name == null || !mounted) return;
    final problem = await controller.sendAttachment(path: path, name: name, size: size);
    if (problem != null && mounted) Toast.error(context, problem);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final uploading = controller.uploadingName != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Attach a document or photo',
              onPressed: uploading ? null : () => _attach(controller),
              icon: const Icon(Icons.attach_file_rounded),
              color: AppColors.inkMuted,
            ),
            Expanded(
              child: TextField(
                controller: _input,
                maxLines: 4,
                minLines: 1,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.muted,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                  ),
                ),
                onSubmitted: (_) => _send(controller),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                // Never blocked by a message in flight: it already shows in
                // the thread with its clock, so the next one can follow.
                onTap: () => _send(controller),
                child: const SizedBox(
                  height: 46,
                  width: 46,
                  child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chat as a sheet over a running call — to send a document without
/// hanging up. The call keeps going underneath; dragging it down returns to it.
Future<void> showInCallChat(BuildContext context, {required bool viewerIsAdvocate}) {
  final controller = context.read<SessionController>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.muted,
    builder: (sheetContext) => ChangeNotifierProvider.value(
      value: controller,
      child: Padding(
        // Keep the composer above the keyboard.
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.72,
          child: _InCallChat(viewerIsAdvocate: viewerIsAdvocate),
        ),
      ),
    ),
  );
}

class _InCallChat extends StatefulWidget {
  const _InCallChat({required this.viewerIsAdvocate});
  final bool viewerIsAdvocate;

  @override
  State<_InCallChat> createState() => _InCallChatState();
}

class _InCallChatState extends State<_InCallChat> {
  final _scroll = ScrollController();
  int _lastCount = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final session = controller.session;
    final messages = session?.messages ?? const <ChatMessage>[];
    final count = messages.length +
        controller.pendingTexts.length +
        (controller.uploadingName == null ? 0 : 1);
    if (count != _lastCount) {
      _lastCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    final other = widget.viewerIsAdvocate ? session?.userName : session?.advocateName;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.chat_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chat with ${other ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    Text(
                      'Send documents and photos — the call stays on',
                      style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ChatMessageList(
            messages: messages,
            viewerIsAdvocate: widget.viewerIsAdvocate,
            controller: _scroll,
            uploadingName: controller.uploadingName,
            uploadProgress: controller.uploadProgress,
            pending: controller.pendingTexts,
            showIntro: false,
            empty: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nothing here yet. Tap the paperclip to send a PDF or a photo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.inkFaint),
                ),
              ),
            ),
          ),
        ),
        if (session?.status.isLive ?? false) const ChatComposer(),
      ],
    );
  }
}

/// The round "Chat" button for a call's control bar, with a badge counting
/// messages from the other side since the sheet was last opened.
class InCallChatButton extends StatefulWidget {
  const InCallChatButton({super.key, required this.viewerIsAdvocate, this.size = 58});
  final bool viewerIsAdvocate;
  final double size;

  @override
  State<InCallChatButton> createState() => _InCallChatButtonState();
}

class _InCallChatButtonState extends State<InCallChatButton> {
  int? _seen;

  int _theirs(SessionController c) {
    final messages = c.session?.messages ?? const <ChatMessage>[];
    return messages.where((m) => widget.viewerIsAdvocate ? m.fromUser : !m.fromUser).length;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final theirs = _theirs(controller);
    // History already there when the call opened is not "new".
    _seen ??= theirs;
    final unread = (theirs - _seen!).clamp(0, 99);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white24,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () async {
              setState(() => _seen = theirs);
              await showInCallChat(context, viewerIsAdvocate: widget.viewerIsAdvocate);
              if (mounted) setState(() => _seen = _theirs(context.read<SessionController>()));
            },
            child: Container(
              height: widget.size,
              width: widget.size,
              alignment: Alignment.center,
              child: const Icon(Icons.chat_rounded, color: Colors.white, size: 24),
            ),
          ),
        ),
        if (unread > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}

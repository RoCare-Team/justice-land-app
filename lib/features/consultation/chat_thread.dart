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
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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

/// The chat's colours — WhatsApp's light palette, so the thread reads the way
/// people already expect a chat to: a warm backdrop, white bubbles for the
/// other side, pale green for this one.
const chatWallpaper = Color(0xFFEFEAE2);
const _mineColor = Color(0xFFD9FDD3);
const _theirsColor = Colors.white;
const _textColor = Color(0xFF111B21);
const _metaColor = Color(0xFF667781);

class _IntroPill extends StatelessWidget {
  const _IntroPill();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 2, 24, 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3C4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 11, color: Color(0xFF54656F)),
            SizedBox(width: 5),
            Flexible(
              child: Text(
                'Private consultation · billed per minute',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: Color(0xFF54656F)),
              ),
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
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 1, offset: Offset(0, 1))],
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Color(0xFF54656F)),
      ),
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

  /// Not yet confirmed by the server — a clock instead of a tick.
  final bool sending;

  /// Time and tick, in the bubble's bottom-right corner.
  Widget _meta() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!sending)
          Text(
            Fmt.time(message.at),
            style: const TextStyle(fontSize: 11, color: _metaColor),
          ),
        // Clock until the server has it, then a tick — the same as the
        // website.
        if (mine) ...[
          const SizedBox(width: 3),
          Icon(
            sending ? Icons.schedule_rounded : Icons.done_rounded,
            size: 14,
            color: _metaColor,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment;
    final caption = message.caption;
    // Room kept at the end of the last line for the time, so short messages
    // stay one line with the time beside them, as in WhatsApp.
    final metaWidth = (sending ? 0.0 : 52.0) + (mine ? 18.0 : 0.0);

    final Widget body;
    if (attachment == null) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(9, 6, 8, 5),
        child: Stack(
          children: [
            Text.rich(
              TextSpan(
                text: caption,
                children: [WidgetSpan(child: SizedBox(width: metaWidth, height: 12))],
              ),
              style: const TextStyle(fontSize: 14.5, height: 1.3, color: _textColor),
            ),
            Positioned(right: 0, bottom: 0, child: _meta()),
          ],
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AttachmentView(attachment: attachment, mine: mine),
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 4, 4, 1),
              child: caption.isEmpty
                  ? Align(alignment: Alignment.centerRight, child: _meta())
                  : Stack(
                      children: [
                        Text.rich(
                          TextSpan(
                            text: caption,
                            children: [WidgetSpan(child: SizedBox(width: metaWidth, height: 12))],
                          ),
                          style: const TextStyle(fontSize: 14.5, height: 1.3, color: _textColor),
                        ),
                        Positioned(right: 0, bottom: 0, child: _meta()),
                      ],
                    ),
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: attachment == null
              ? MediaQuery.of(context).size.width * 0.8
              : 268,
        ),
        margin: EdgeInsets.only(
          top: grouped ? 2 : 6,
          left: mine ? 48 : 0,
          right: mine ? 0 : 48,
        ),
        decoration: _bubbleDecoration(mine, grouped: grouped),
        child: body,
      ),
    );
  }
}

/// Small rounded corners, with the sharp "tail" corner at the top on the
/// sender's side for the first bubble of a run — WhatsApp's shape.
BoxDecoration _bubbleDecoration(bool mine, {bool grouped = false}) => BoxDecoration(
      color: mine ? _mineColor : _theirsColor,
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(!mine && !grouped ? 2 : 10),
        topRight: Radius.circular(mine && !grouped ? 2 : 10),
        bottomLeft: const Radius.circular(10),
        bottomRight: const Radius.circular(10),
      ),
      boxShadow: const [
        BoxShadow(color: Color(0x1A000000), blurRadius: 1, offset: Offset(0, 1)),
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
    final tint = attachment.isPdf
        ? AppColors.danger
        : const ['xls', 'xlsx', 'csv'].contains(attachment.extension)
            ? const Color(0xFF15803D)
            : AppColors.info;
    return Material(
      color: Colors.black.withValues(alpha: mine ? 0.05 : 0.04),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => openAttachment(context, attachment),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(
                height: 38,
                width: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 22, color: tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: _textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${attachment.extension.toUpperCase()} · ${attachment.sizeLabel}',
                      style: const TextStyle(fontSize: 11.5, color: _metaColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.download_rounded, size: 20, color: _metaColor),
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
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 260,
            height: 260,
            child: bytes != null
                ? GestureDetector(
                    onTap: () => _showFullImage(context, attachment, bytes),
                    // Decoded at the size it is shown, not the camera's full
                    // resolution — a few of these would otherwise hold tens of
                    // megabytes.
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      cacheWidth: (260 * MediaQuery.devicePixelRatioOf(context)).round(),
                    ),
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
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 7),
        decoration: _bubbleDecoration(true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.upload_file_rounded, color: _metaColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _textColor, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                minHeight: 3,
                backgroundColor: Colors.black12,
                color: const Color(0xFF15803D),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sending… ${(progress * 100).round()}%',
              style: const TextStyle(color: _metaColor, fontSize: 11),
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

  /// The paperclip: WhatsApp's row of round icons.
  Future<void> _attach(SessionController controller) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachOption(
                icon: Icons.insert_drive_file_rounded,
                label: 'Document',
                color: const Color(0xFF7F66FF),
                onTap: () => Navigator.of(context).pop('file'),
              ),
              _AttachOption(
                icon: Icons.photo_camera_rounded,
                label: 'Camera',
                color: const Color(0xFFFF2E74),
                onTap: () => Navigator.of(context).pop('camera'),
              ),
              _AttachOption(
                icon: Icons.photo_rounded,
                label: 'Gallery',
                color: const Color(0xFFC861FA),
                onTap: () => Navigator.of(context).pop('gallery'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _pick(controller, choice);
  }

  Future<void> _pick(SessionController controller, String choice) async {
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14000000), blurRadius: 1, offset: Offset(0, 1)),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        maxLines: 5,
                        minLines: 1,
                        maxLength: 2000,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(fontSize: 15.5, color: _textColor),
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(color: _metaColor),
                          counterText: '',
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        onSubmitted: (_) => _send(controller),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Attach a document or photo',
                      onPressed: uploading ? null : () => _attach(controller),
                      icon: Transform.rotate(
                        angle: -0.6,
                        child: const Icon(Icons.attach_file_rounded),
                      ),
                      color: _metaColor,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: 'Take a photo',
                      onPressed: uploading ? null : () => _pick(controller, 'camera'),
                      icon: const Icon(Icons.photo_camera_rounded),
                      color: _metaColor,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                // Never blocked by a message in flight: it already shows in
                // the thread with its clock, so the next one can follow.
                onTap: () => _send(controller),
                child: const SizedBox(
                  height: 48,
                  width: 48,
                  child: Icon(Icons.send_rounded, color: Colors.white, size: 21),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: color,
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12.5, color: _metaColor)),
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
    backgroundColor: chatWallpaper,
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
  const InCallChatButton({super.key, required this.viewerIsAdvocate, this.size = 58, this.onOpen});
  final bool viewerIsAdvocate;
  final double size;

  /// Opens the chat instead of the sheet — the video call opens the full
  /// chat screen and shrinks itself into the floating window.
  final VoidCallback? onOpen;

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
              if (widget.onOpen != null) {
                widget.onOpen!();
                return;
              }
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

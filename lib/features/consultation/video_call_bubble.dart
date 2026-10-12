import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/platform/pip.dart';
import '../../core/utils/formatters.dart';
import '../../routing/app_router.dart';
import '../../state/video_call.dart';

/// A running video consultation, over the rest of the app.
///
/// Left with back or the arrow, the call keeps going in a small window the
/// lawyer or client can drag anywhere while they use the rest of Justiceland,
/// the way WhatsApp's does; a tap brings the full call screen back. When the
/// app itself is in Android's picture-in-picture window (home was pressed
/// during the call), the whole window shows the other person instead of
/// whichever screen happened to be open.
///
/// Wraps the app (MaterialApp.builder). The app stays the first child of the
/// same Stack whether or not a call is running, so the router beneath is
/// never rebuilt from scratch when a call starts or ends.
class VideoCallBubble extends StatelessWidget {
  const VideoCallBubble({super.key, required this.child});

  final Widget child;

  static final _idle = ValueNotifier<int>(0);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoCall?>(
      valueListenable: VideoCall.current,
      child: child,
      builder: (context, call, app) => ListenableBuilder(
        listenable: call ?? _idle,
        child: app,
        builder: (context, app) => ValueListenableBuilder<bool>(
          valueListenable: Pip.active,
          child: app,
          builder: (context, inPip, app) {
            final live = call != null && call.isLive;
            return Stack(
              fit: StackFit.passthrough,
              children: [
                app!,
                if (live && inPip)
                  Positioned.fill(child: _PipView(call: call))
                else if (live && !call.onScreen)
                  _Bubble(call: call),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Android's picture-in-picture window: just the other person, nothing to tap.
class _PipView extends StatelessWidget {
  const _PipView({required this.call});

  final VideoCall call;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: call.connected
          ? RTCVideoView(
              call.remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          : const Center(
              child: Text(
                'Connecting…',
                style: TextStyle(color: Colors.white70, fontSize: 12, decoration: TextDecoration.none),
              ),
            ),
    );
  }
}

class _Bubble extends StatefulWidget {
  const _Bubble({required this.call});

  final VideoCall call;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  static const _size = Size(112, 160);
  static const _margin = 12.0;

  /// Where the window sits, top-left corner. Null until first laid out: it
  /// starts at the top right, clear of the status bar.
  Offset? _position;

  /// While a finger moves the window, it follows without easing.
  bool _dragging = false;

  /// Kept to the screen, clear of the status and navigation bars.
  Offset _clamp(Offset p, Size screen, EdgeInsets safe) {
    final maxX = screen.width - _size.width - _margin;
    final maxY = screen.height - _size.height - safe.bottom - _margin;
    return Offset(
      p.dx.clamp(_margin, maxX < _margin ? _margin : maxX),
      p.dy.clamp(safe.top + _margin, maxY < safe.top + _margin ? safe.top + _margin : maxY),
    );
  }

  /// Let go: to whichever side is nearer, so it never covers the middle.
  Offset _snap(Offset p, Size screen, EdgeInsets safe) {
    final left = p.dx + _size.width / 2 < screen.width / 2;
    return _clamp(Offset(left ? _margin : screen.width, p.dy), screen, safe);
  }

  void _open() => AppRouter.instance?.push('/consultation/${widget.call.consultationId}/video');

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final safe = media.padding;
    final position = _clamp(
      _position ?? Offset(screen.width - _size.width - _margin, safe.top + 72),
      screen,
      safe,
    );

    final call = widget.call;
    final session = call.session.session;
    final name = session == null ? '' : (call.isAdvocate ? session.userName : session.advocateName);
    final status = !call.connected
        ? 'Connecting…'
        : session == null || session.awaitingCallClock
            ? ''
            : Fmt.clock(session.elapsed);

    return AnimatedPositioned(
      // Moves with the finger while dragging; eases to the side when let go.
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      left: position.dx,
      top: position.dy,
      width: _size.width,
      height: _size.height,
      child: Semantics(
        button: true,
        label: 'Video call${name.isEmpty ? '' : ' with $name'}. Tap to return to the call.',
        child: GestureDetector(
          onTap: _open,
          onPanStart: (_) => setState(() => _dragging = true),
          onPanUpdate: (d) => setState(() => _position = _clamp(position + d.delta, screen, safe)),
          onPanEnd: (_) => setState(() {
            _dragging = false;
            _position = _snap(position, screen, safe);
          }),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF0B1F3A)),
                  if (call.connected)
                    RTCVideoView(
                      call.remoteRenderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  else
                    Center(
                      child: Icon(
                        Icons.videocam_rounded,
                        color: Colors.white.withOpacity(0.6),
                        size: 30,
                      ),
                    ),
                  if (status.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xB3000000), Color(0x00000000)],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 14, 8, 7),
                          child: Row(
                            children: [
                              if (!call.micOn) ...[
                                const Icon(Icons.mic_off_rounded, color: Colors.white, size: 13),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.none,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

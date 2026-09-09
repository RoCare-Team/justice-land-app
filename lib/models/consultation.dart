import 'json.dart';

/// The five states a consultation moves through, exactly as the backend
/// defines them. Nothing else is a valid status, and the transitions are the
/// server's to make — the app asks (`accept`, `reject`, `cancel`, `end`) and
/// re-reads what the server decided.
enum ConsultationStatus {
  pending,
  active,
  ended,
  rejected,
  cancelled;

  static ConsultationStatus parse(String? raw) {
    switch (raw) {
      case 'active':
        return ConsultationStatus.active;
      case 'ended':
        return ConsultationStatus.ended;
      case 'rejected':
        return ConsultationStatus.rejected;
      case 'cancelled':
        return ConsultationStatus.cancelled;
      default:
        return ConsultationStatus.pending;
    }
  }

  String get wire => name;

  /// Wording matches the website's status chips.
  String get label {
    switch (this) {
      case ConsultationStatus.pending:
        return 'Not answered';
      case ConsultationStatus.active:
        return 'Ongoing';
      case ConsultationStatus.ended:
        return 'Completed';
      case ConsultationStatus.rejected:
        return 'Declined';
      case ConsultationStatus.cancelled:
        return 'Cancelled';
    }
  }

  bool get isLive => this == ConsultationStatus.active;
  bool get isWaiting => this == ConsultationStatus.pending;
  bool get isOver => this == ConsultationStatus.ended ||
      this == ConsultationStatus.rejected ||
      this == ConsultationStatus.cancelled;
}

/// The channel a session runs on. Each bills from its own rate and opens its
/// own screen; leftover time on one never comes back as another.
enum ConsultationType {
  chat,
  audio,
  video;

  static ConsultationType parse(String? raw) {
    switch (raw) {
      case 'audio':
        return ConsultationType.audio;
      case 'video':
        return ConsultationType.video;
      default:
        return ConsultationType.chat;
    }
  }

  String get wire => name;

  String get label {
    switch (this) {
      case ConsultationType.chat:
        return 'Live Chat';
      case ConsultationType.audio:
        return 'Audio Call';
      case ConsultationType.video:
        return 'Video Call';
    }
  }
}

class Consultation {
  const Consultation({
    required this.id,
    required this.userId,
    required this.userName,
    required this.advocateId,
    required this.advocateName,
    required this.rate,
    required this.maxMinutes,
    required this.minutes,
    required this.price,
    required this.type,
    required this.status,
    required this.isResume,
    required this.messages,
    required this.call,
    this.createdAt,
    this.startedAt,
    this.endsAt,
    this.remainingMs,
    this.advocatePhoto = '',
    this.advocateProfilePath = '',
    this.charged = false,
    this.resumeLeftoverSeconds = 0,
  });

  final String id;
  final String userId;

  /// 'Anonymous' when the client has that preference on — the lawyer never
  /// sees the real name in that case, and neither should this screen.
  final String userName;

  final String advocateId;
  final String advocateName;

  /// ₹ per minute this session bills at, fixed when it was created.
  final int rate;

  /// The ceiling the wallet could cover at booking time.
  final int maxMinutes;

  /// What was actually billed. Both stay 0 until the session ends.
  final int minutes;
  final int price;

  final ConsultationType type;
  final ConsultationStatus status;

  /// A free reconnection of leftover time. Labelled as such rather than "₹0".
  final bool isResume;

  final List<ChatMessage> messages;
  final CallState? call;

  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? endsAt;

  /// Server-computed milliseconds left, read at the moment of the response.
  final int? remainingMs;

  // Extras the history endpoint adds for rendering a list row.
  final String advocatePhoto;
  final String advocateProfilePath;
  final bool charged;
  final int resumeLeftoverSeconds;

  bool get isChat => type == ConsultationType.chat;
  bool get isVideo => type == ConsultationType.video;
  bool get isAudio => type == ConsultationType.audio;

  /// Leftover time can be claimed free for 24 hours after the session ended.
  bool get hasClaimableLeftover => resumeLeftoverSeconds > 0;

  /// The live countdown. Recomputed from `endsAt` rather than trusting
  /// `remainingMs`, which was already stale by the time it arrived.
  Duration get remaining {
    final end = endsAt;
    if (end == null) {
      final ms = remainingMs;
      return ms == null ? Duration.zero : Duration(milliseconds: ms);
    }
    final left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Minutes consumed so far, for the live cost meter. Rounded up, because a
  /// started minute is a billed minute — the same way the server settles it.
  int get elapsedMinutes {
    final start = startedAt;
    if (start == null) return 0;
    final seconds = DateTime.now().difference(start).inSeconds;
    if (seconds <= 0) return 0;
    return (seconds / 60).ceil();
  }

  /// What this session has run up so far. A resume is free, so it stays ₹0.
  int get runningCost => isResume ? 0 : elapsedMinutes * rate;

  factory Consultation.fromJson(Map<String, dynamic> j) => Consultation(
        id: J.id(j['id'] ?? j['_id']),
        userId: J.id(j['userId']),
        userName: J.str(j['userName']),
        advocateId: J.id(j['advocateId']),
        advocateName: J.str(j['advocateName']),
        rate: J.int$(j['rate']),
        maxMinutes: J.int$(j['maxMinutes']),
        minutes: J.int$(j['minutes']),
        price: J.int$(j['price']),
        type: ConsultationType.parse(J.str(j['type'], 'chat')),
        status: ConsultationStatus.parse(J.str(j['status'], 'pending')),
        isResume: J.flag(j['isResume']),
        messages: J.models(j['messages'], ChatMessage.fromJson),
        call: j['call'] == null ? null : CallState.fromJson(J.map(j['call'])),
        createdAt: J.date(j['createdAt']),
        startedAt: J.date(j['startedAt']),
        endsAt: J.date(j['endsAt']),
        remainingMs: j['remainingMs'] == null ? null : J.int$(j['remainingMs']),
        advocatePhoto: J.str(j['advocatePhoto']),
        advocateProfilePath: J.str(j['advocateProfilePath']),
        charged: J.flag(j['charged']),
        resumeLeftoverSeconds: J.int$(j['resumeLeftoverSeconds']),
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.from,
    required this.text,
    this.at,
  });

  final String id;

  /// 'user' or 'advocate' — which side of the conversation wrote it.
  final String from;

  final String text;
  final DateTime? at;

  bool get fromUser => from == 'user';

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: J.id(j['id'] ?? j['_id']),
        from: J.str(j['from']),
        text: J.str(j['text']),
        at: J.date(j['at']),
      );
}

/// The WebRTC handshake state for a video call inside a live consultation.
///
/// Only the signalling passes through the server — offer, answer, ICE
/// candidates. Once the two peers connect, audio and video go directly
/// between them.
class CallState {
  const CallState({
    required this.id,
    required this.status,
    required this.offer,
    required this.answer,
    required this.candidates,
    required this.cursor,
    this.startedAt,
    this.endedAt,
    this.endedReason = '',
  });

  final String id;

  /// 'idle' | 'ringing' | 'connected' | 'ended' | 'rejected'
  final String status;

  /// SDP, as the string the peer connection produced.
  final String offer;
  final String answer;

  /// ICE candidates newer than the `since` cursor we asked with.
  final List<String> candidates;

  /// Feed position to send as `since` on the next poll, so candidates are not
  /// replayed on every tick.
  final int cursor;

  final DateTime? startedAt;
  final DateTime? endedAt;
  final String endedReason;

  bool get isRinging => status == 'ringing';
  bool get isConnected => status == 'connected';
  bool get isOver => status == 'ended' || status == 'rejected';
  bool get isIdle => status.isEmpty || status == 'idle';

  factory CallState.fromJson(Map<String, dynamic> j) => CallState(
        id: J.str(j['id'] ?? j['callId']),
        status: J.str(j['status'], 'idle'),
        offer: J.str(j['offer']),
        answer: J.str(j['answer']),
        candidates: J.strList(j['candidates']),
        cursor: J.int$(j['cursor'] ?? j['since']),
        startedAt: J.date(j['startedAt']),
        endedAt: J.date(j['endedAt']),
        endedReason: J.str(j['endedReason'] ?? j['reason']),
      );
}

/// Leftover time from an earlier session that can be reconnected free, offered
/// by /api/consultations/resumable for 24 hours after the session ended.
class ResumableSession {
  const ResumableSession({
    required this.id,
    required this.seconds,
    required this.type,
    required this.advocateName,
    this.endedAt,
  });

  final String id;
  final int seconds;
  final ConsultationType type;
  final String advocateName;
  final DateTime? endedAt;

  factory ResumableSession.fromJson(Map<String, dynamic> j) => ResumableSession(
        id: J.id(j['id'] ?? j['_id']),
        seconds: J.int$(j['seconds'] ?? j['leftoverSeconds'] ?? j['remainingSeconds']),
        type: ConsultationType.parse(J.str(j['type'], 'chat')),
        advocateName: J.str(j['advocateName']),
        endedAt: J.date(j['endedAt']),
      );
}

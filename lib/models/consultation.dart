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
    this.discount,
    required this.messages,
    required this.call,
    this.createdAt,
    this.startedAt,
    this.endsAt,
    this.remainingMs,
    this.clockSkewMs = 0,
    this.callClockStarted = false,
    this.advocatePhoto = '',
    this.advocateProfilePath = '',
    this.charged = false,
    this.resumeLeftoverSeconds = 0,
    this.talkedMinutes = 0,
    this.messagesCount = 0,
    this.lastMessage,
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

  /// A discount JusticeLand granted on this session, applied when it settles.
  /// Null on almost every session — most are charged in full.
  final SessionDiscount? discount;

  final List<ChatMessage> messages;
  final CallState? call;

  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? endsAt;

  /// An audio or video session is billed from the moment its call actually
  /// connects, not from the lawyer's Accept. False while the call is still
  /// ringing or connecting, and the clock and cost meter stay off until then.
  final bool callClockStarted;

  /// Server-computed milliseconds left, read at the moment of the response.
  final int? remainingMs;

  /// How far the server's clock is ahead of this phone's, in milliseconds,
  /// worked out when the response was read (`endsAt − remainingMs` is the
  /// server's "now"). The live figures below run on the server's clock, so a
  /// phone set a few minutes out does not show a timer that started before
  /// the lawyer accepted, or a balance that runs out early.
  final int clockSkewMs;

  /// "Now" on the server's clock.
  DateTime get _serverNow => DateTime.now().add(Duration(milliseconds: clockSkewMs));

  // Extras the history endpoint adds for rendering a list row.
  final String advocatePhoto;
  final String advocateProfilePath;
  final bool charged;
  final int resumeLeftoverSeconds;

  /// Minutes the two actually spent connected (history rows only).
  final int talkedMinutes;

  /// How many chat lines the session holds, and the latest of them — what the
  /// lawyer's Messages list previews without loading every transcript.
  final int messagesCount;
  final ChatMessage? lastMessage;

  /// When this session counts as having happened: the clock start, else the
  /// booking. Earnings and "today" are counted on this.
  DateTime? get happenedAt => startedAt ?? createdAt;

  bool get isChat => type == ConsultationType.chat;
  bool get isVideo => type == ConsultationType.video;
  bool get isAudio => type == ConsultationType.audio;

  /// An audio or video session that has been accepted but whose call has not
  /// connected yet. Nothing is being billed, so the clock and cost meter read
  /// zero and screens say "Connecting…" instead of counting.
  bool get awaitingCallClock =>
      (isAudio || isVideo) && status == ConsultationStatus.active && !callClockStarted;

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
    final left = end.difference(_serverNow);
    return left.isNegative ? Duration.zero : left;
  }

  /// How long the session has run, counted from the moment the lawyer
  /// accepted (for an audio or video call, the moment the call connected) —
  /// never from the booking. Zero while the request is still waiting, and it stops at the
  /// session's end rather than running on past it. The website's live chat
  /// and call timers count the same way.
  Duration get elapsed {
    if (awaitingCallClock) return Duration.zero;
    final start = startedAt;
    if (start == null) return Duration.zero;
    var until = _serverNow;
    final end = endsAt;
    if (end != null && until.isAfter(end)) until = end;
    final ran = until.difference(start);
    return ran.isNegative ? Duration.zero : ran;
  }

  /// Minutes consumed so far, for labels. Rounded up for display only — the
  /// bill itself is per second (see [runningCost]).
  int get elapsedMinutes {
    final seconds = elapsed.inSeconds;
    if (seconds <= 0) return 0;
    return (seconds / 60).ceil();
  }

  /// The opening seconds that are never billed — connecting takes a moment.
  /// Same as FREE_SECONDS on the server.
  static const int freeSeconds = 10;

  /// What this session has run up so far, second by second after the free
  /// opening — the same sum the server settles with. A resume stays ₹0.
  ///
  /// A discount comes off here rather than at the end: this figure is shown on
  /// screen as what the session is costing, and one that is quietly half wrong
  /// until the bill arrives is worse than no figure at all.
  double get runningCost {
    if (isResume) return 0;
    final billable = elapsed.inSeconds - freeSeconds;
    if (billable <= 0) return 0;
    final full = (billable * rate / 60 * 100).round() / 100;
    return discount?.applyTo(full) ?? full;
  }

  /// The same sum before any discount, for showing what was struck through.
  double get fullCost {
    if (isResume) return 0;
    final billable = elapsed.inSeconds - freeSeconds;
    if (billable <= 0) return 0;
    return (billable * rate / 60 * 100).round() / 100;
  }

  factory Consultation.fromJson(Map<String, dynamic> j) {
    final endsAt = J.date(j['endsAt']);
    final remainingMs = j['remainingMs'] == null ? null : J.int$(j['remainingMs']);
    // The server stamped `remainingMs` against its own clock, so endsAt minus
    // it is the server's time at the response. Only read while the session is
    // still counting — a finished one reports 0 left and says nothing about now.
    var skew = 0;
    if (endsAt != null && remainingMs != null && remainingMs > 0) {
      final serverNow = endsAt.millisecondsSinceEpoch - remainingMs;
      skew = serverNow - DateTime.now().millisecondsSinceEpoch;
      // More than a day out is bad data, not a bad clock.
      if (skew.abs() > const Duration(days: 1).inMilliseconds) skew = 0;
    }
    return Consultation(
        clockSkewMs: skew,
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
        discount: SessionDiscount.fromJson(j['discount']),
        messages: J.models(j['messages'], ChatMessage.fromJson),
        call: j['call'] == null ? null : CallState.fromJson(J.map(j['call'])),
        createdAt: J.date(j['createdAt']),
        startedAt: J.date(j['startedAt']),
        endsAt: endsAt,
        callClockStarted: J.flag(j['callClockStarted']),
        remainingMs: remainingMs,
        advocatePhoto: J.str(j['advocatePhoto']),
        advocateProfilePath: J.str(j['advocateProfilePath']),
        charged: J.flag(j['charged']),
        resumeLeftoverSeconds: J.int$(j['resumeLeftoverSeconds']),
        talkedMinutes: J.int$(j['talkedMinutes']),
        messagesCount: j['messagesCount'] != null
            ? J.int$(j['messagesCount'])
            : J.mapList(j['messages']).length,
        lastMessage: j['lastMessage'] is Map
            ? ChatMessage.fromJson(J.map(j['lastMessage']))
            : null,
      );
  }
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

  /// The server calls an answered call 'active'; 'connected' is read the same.
  bool get isConnected => status == 'active' || status == 'connected';
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

/// A discount an admin granted on one session.
///
/// Mirrors what the website sends on the session: the shape of the discount
/// and a ready-made label, so the app never has to word "50% off" itself and
/// can never word it differently from the panel that granted it.
class SessionDiscount {
  const SessionDiscount({
    required this.kind,
    required this.value,
    required this.label,
    required this.note,
  });

  /// 'percent' or 'flat'.
  final String kind;
  final double value;

  /// "50% off" / "₹100 off", as the server wrote it.
  final String label;
  final String note;

  /// A bill with this discount taken off, never below zero.
  double applyTo(double amount) {
    if (amount <= 0 || value <= 0) return amount <= 0 ? 0 : amount;
    final off = kind == 'flat' ? value : amount * value / 100;
    final left = amount - (off > amount ? amount : off);
    return (left * 100).round() / 100;
  }

  static SessionDiscount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = J.map(raw);
    final value = J.dbl(map['value']);
    if (value <= 0) return null;
    return SessionDiscount(
      kind: J.str(map['kind'], 'percent'),
      value: value,
      label: J.str(map['label']),
      note: J.str(map['note']),
    );
  }
}

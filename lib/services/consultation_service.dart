import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/consultation.dart';
import '../models/json.dart';

/// The consultation lifecycle, spoken to the same endpoints the web client
/// uses.
///
/// Every transition is the server's to make. The app asks — accept, reject,
/// cancel, end — and then renders whatever came back. It never advances a
/// session locally and hopes the server agrees, because the money is settled
/// on those transitions.
class ConsultationService {
  ConsultationService(this._api);

  final ApiClient _api;

  // ── Booking ──────────────────────────────────────────────────────────────

  /// Books a consultation on one channel.
  ///
  /// Nothing is charged here. The session opens PENDING at the lawyer's
  /// per-minute rate, and the bill is the minutes it actually runs. The
  /// booking is refused up front only when the wallet cannot cover a single
  /// minute — better to say so now than to cut a client off thirty seconds in.
  ///
  /// Throws [ApiException] with `isInsufficientBalance` when the wallet is too
  /// low, or `isAdvocateOffline` when the lawyer has switched off.
  Future<Consultation> book({
    required String advocateId,
    required ConsultationType type,
  }) async {
    final data = await _api.post(Endpoints.consultationCreate, body: {
      'advocateId': advocateId,
      'type': type.wire,
    });
    return Consultation.fromJson(J.map(J.map(data)['session']));
  }

  /// Reconnects leftover time from an earlier session — free, no new charge.
  /// Each channel only sees its own leftover: phone minutes never come back as
  /// a chat.
  Future<Consultation> resume({
    required String advocateId,
    required String fromSessionId,
  }) async {
    final data = await _api.post(Endpoints.consultationCreate, body: {
      'advocateId': advocateId,
      'resumeFrom': fromSessionId,
    });
    return Consultation.fromJson(J.map(J.map(data)['session']));
  }

  /// Is there leftover time with this lawyer that can be claimed right now?
  Future<ResumableSession?> resumable({
    required String advocateId,
    required ConsultationType type,
  }) async {
    final data = await _api.get(Endpoints.resumable, query: {
      'advocateId': advocateId,
      'type': type.wire,
    });
    final raw = J.map(data)['resumable'];
    if (raw == null) return null;
    return ResumableSession.fromJson(J.map(raw));
  }

  // ── Reading ──────────────────────────────────────────────────────────────

  /// Polls one session. For an audio consultation this is also what tracks the
  /// phone call: the server asks the telephony provider whether it was
  /// answered or hung up and moves the session to match.
  Future<Consultation> read(String id) async {
    final data = await _api.get(Endpoints.consultation(id));
    return Consultation.fromJson(J.map(J.map(data)['session']));
  }

  /// The lawyer's live inbox — pending requests and anything active.
  ///
  /// Calling this is also the presence heartbeat: a lawyer whose app is
  /// polling is a lawyer who is online. That is why the dashboard keeps it
  /// running rather than fetching once.
  Future<List<Consultation>> inbox() async {
    final data = await _api.get(Endpoints.consultationInbox);
    return J.models(J.map(data)['sessions'], Consultation.fromJson);
  }

  /// The signed-in participant's own consultation history.
  ///
  /// Same route as the inbox with `scope=mine`, which is the server's own
  /// distinction: without it you get the lawyer's live feed, with it you get
  /// whichever history belongs to whoever is signed in.
  Future<List<Consultation>> history() async {
    final data = await _api.get(
      Endpoints.consultationInbox,
      query: Endpoints.consultationHistoryQuery,
    );
    return J.models(J.map(data)['consultations'], Consultation.fromJson);
  }

  /// The saved transcript of an ended session.
  Future<List<ChatMessage>> transcript(String id) async {
    final data = await _api.get(Endpoints.consultationTranscript(id));
    final map = J.map(data);
    return J.models(map['messages'] ?? data, ChatMessage.fromJson);
  }

  // ── Transitions ──────────────────────────────────────────────────────────

  /// Lawyer accepts a pending request. This is where the clock starts.
  Future<Consultation> accept(String id) => _act(id, 'accept');

  /// Lawyer declines. Nothing is charged.
  Future<Consultation> reject(String id) => _act(id, 'reject');

  /// Client withdraws a request the lawyer has not answered yet.
  Future<Consultation> cancel(String id) => _act(id, 'cancel');

  /// Either side hangs up. The server bills the minutes actually used and
  /// records whatever is left over, which the client can reclaim free for the
  /// next 24 hours.
  Future<Consultation> end(String id) => _act(id, 'end');

  Future<Consultation> _act(String id, String action) async {
    final data = await _api.patch(
      Endpoints.consultation(id),
      body: {'action': action},
    );
    return Consultation.fromJson(J.map(J.map(data)['session']));
  }

  /// Removes the consultation from the caller's own list. The other
  /// participant's history and the money ledger are untouched.
  Future<void> hide(String id) async {
    await _api.delete(Endpoints.consultation(id));
  }

  // ── Chat ─────────────────────────────────────────────────────────────────

  /// Posts a message into a live session and returns the session with it
  /// appended, so the thread stays the server's version rather than a local
  /// guess that might not have landed.
  Future<Consultation> sendMessage(String id, String text) async {
    final data = await _api.post(
      Endpoints.consultationMessages(id),
      body: {'text': text},
    );
    return Consultation.fromJson(J.map(J.map(data)['session']));
  }

  // ── Video call signalling ────────────────────────────────────────────────
  // Only the handshake goes through the server. Once the two peers connect,
  // audio and video flow directly between the devices.

  /// Reads the other side's description and any ICE candidates newer than
  /// [since].
  Future<CallState> callState(String id, {int since = 0}) async {
    final data = await _api.get(
      Endpoints.consultationCall(id),
      query: {'since': since},
    );
    return CallState.fromJson(J.map(data));
  }

  /// The client rings — same direction as the booking itself.
  Future<CallState> startCall(String id) => _call(id, {'action': 'start'});

  /// The lawyer answers the ring.
  Future<CallState> answerCall(String id, {required bool accept}) =>
      _call(id, {'action': accept ? 'accept' : 'reject'});

  /// Either side hangs up. `failed` distinguishes a connection that never came
  /// up from a deliberate hang-up.
  Future<CallState> endCall(String id, {bool failed = false}) =>
      _call(id, {'action': 'end', 'reason': failed ? 'failed' : 'hangup'});

  /// Pushes one piece of the handshake: an offer, an answer, or a candidate.
  Future<CallState> signal(
    String id, {
    required String callId,
    String? offer,
    String? answer,
    String? candidate,
  }) =>
      _call(id, {
        'action': 'signal',
        'callId': callId,
        if (offer != null) 'offer': offer,
        if (answer != null) 'answer': answer,
        if (candidate != null) 'candidate': candidate,
      });

  Future<CallState> _call(String id, Map<String, dynamic> body) async {
    final data = await _api.post(Endpoints.consultationCall(id), body: body);
    final map = J.map(data);
    return CallState.fromJson(J.map(map['call'] ?? map));
  }

  /// STUN/TURN servers for the peer connection. A call across mobile networks
  /// usually needs the TURN relay, so this is fetched rather than hardcoded.
  Future<List<Map<String, dynamic>>> iceServers() async {
    final data = await _api.get(Endpoints.webrtcIce);
    final map = J.map(data);
    final servers = map['iceServers'] ?? map['servers'] ?? data;
    return J.mapList(servers);
  }
}

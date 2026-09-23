import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../core/network/api_exception.dart';
import '../models/account.dart';
import '../models/consultation.dart';
import '../services/consultation_service.dart';
import '../services/dashboard_service.dart';
import '../services/push_service.dart';
import 'auth_controller.dart';

/// One client's sessions with this lawyer, folded together.
class ClientThread {
  ClientThread({required this.userId, required this.userName});

  final String userId;
  String userName;

  /// Newest first.
  final List<Consultation> sessions = [];

  Consultation get latest => sessions.first;
  int get earned => sessions.where((s) => s.charged).fold(0, (sum, s) => sum + s.price);
  int get minutes => sessions.fold(0, (sum, s) => sum + s.talkedMinutes);
  int get messages => sessions.fold(0, (sum, s) => sum + s.messagesCount);
  bool get isLive => sessions.any((s) => s.status.isLive);
  bool get isWaiting => sessions.any((s) => s.status.isWaiting);
  DateTime? get lastAt => latest.happenedAt;

  /// The newest line anyone wrote across every session with this client.
  ChatMessage? get lastMessage {
    for (final s in sessions) {
      if (s.lastMessage != null) return s.lastMessage;
    }
    return null;
  }

  /// A session with chat lines — any one opens the pair's whole transcript.
  Consultation? get threadSession {
    for (final s in sessions) {
      if (s.messagesCount > 0) return s;
    }
    return null;
  }
}

/// One bar of the weekly earnings chart.
typedef DayEarning = ({DateTime day, int amount, bool isToday});

/// The signed-in lawyer's live workspace, shared by every lawyer screen.
///
/// Starts itself when a lawyer signs in and stops when they sign out, so a
/// client's session never polls a lawyer inbox. The inbox poll is also the
/// presence heartbeat the server records, which is why it runs for as long as
/// the lawyer is in the app rather than only while one screen is open — and
/// why the shell pauses it while the app is in the background.
class LawyerController extends ChangeNotifier {
  LawyerController(this._consults, this._dashboard, this._auth, [this._push]) {
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final ConsultationService _consults;
  final DashboardService _dashboard;
  final AuthController _auth;

  /// Null in tests, and wherever a build has not wired Firebase up yet — see
  /// PushService's own doc comment for how little that changes: the in-app
  /// poll below rings exactly the same either way.
  final PushService? _push;

  Timer? _fastPoll;
  Timer? _slowPoll;
  bool _running = false;
  bool _paused = false;

  List<Consultation> _inbox = [];
  List<Consultation> _history = [];
  Wallet _earnings = Wallet.empty;

  bool _inboxLoaded = false;
  bool _historyLoaded = false;
  bool _earningsLoaded = false;
  ApiException? _error;

  bool _available = false;
  bool _savingAvailability = false;
  final Set<String> _busy = {};

  /// Pending ids already announced, so a request rings once, not every poll.
  final Set<String> _announced = {};
  Consultation? _toAnnounce;

  // ── Reads ────────────────────────────────────────────────────────────────

  List<Consultation> get inbox => _inbox;
  List<Consultation> get history => _history;
  Wallet get earnings => _earnings;
  bool get inboxLoaded => _inboxLoaded;
  bool get historyLoaded => _historyLoaded;
  bool get earningsLoaded => _earningsLoaded;
  ApiException? get error => _error;
  bool get available => _available;
  bool get savingAvailability => _savingAvailability;
  bool isBusy(String id) => _busy.contains(id);

  List<Consultation> get pending => _inbox.where((c) => c.status.isWaiting).toList();
  List<Consultation> get live => _inbox.where((c) => c.status.isLive).toList();

  /// The request the shell should ring for, if one arrived since last asked.
  Consultation? takeAnnouncement() {
    final next = _toAnnounce;
    _toAnnounce = null;
    return next;
  }

  /// Everything seen so far — the live inbox laid over the history, so a
  /// request that just arrived shows up before the next history read.
  List<Consultation> get allSessions {
    final byId = <String, Consultation>{};
    for (final c in _history) {
      byId[c.id] = c;
    }
    for (final c in _inbox) {
      byId[c.id] = c;
    }
    final list = byId.values.toList()
      ..sort((a, b) => (b.happenedAt ?? DateTime(0)).compareTo(a.happenedAt ?? DateTime(0)));
    return list;
  }

  List<Consultation> get paid => _history.where((c) => c.charged).toList();

  /// Clients, newest conversation first.
  List<ClientThread> get clients {
    final byUser = <String, ClientThread>{};
    final order = <ClientThread>[];
    for (final c in allSessions) {
      final key = c.userId.isEmpty ? c.id : c.userId;
      final thread = byUser.putIfAbsent(key, () {
        final t = ClientThread(userId: key, userName: c.userName);
        order.add(t);
        return t;
      });
      thread.sessions.add(c);
    }
    return order;
  }

  ClientThread? client(String userId) {
    for (final t in clients) {
      if (t.userId == userId) return t;
    }
    return null;
  }

  static bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  int earnedOn(DateTime day) => paid
      .where((c) => _sameDay(c.happenedAt?.toLocal(), day))
      .fold(0, (sum, c) => sum + c.price);

  int get earnedToday => earnedOn(DateTime.now());
  int get earnedYesterday => earnedOn(DateTime.now().subtract(const Duration(days: 1)));

  /// Earned, sessions and minutes over the last [days] days (today included).
  ({int earned, int sessions, int minutes}) totalsFor(int days, {int offset = 0}) {
    final today = _dayStart(DateTime.now());
    final from = today.subtract(Duration(days: days - 1 + offset));
    final to = today.subtract(Duration(days: offset)).add(const Duration(days: 1));
    final rows = paid.where((c) {
      final at = c.happenedAt?.toLocal();
      return at != null && !at.isBefore(from) && at.isBefore(to);
    });
    return (
      earned: rows.fold(0, (sum, c) => sum + c.price),
      sessions: rows.length,
      minutes: rows.fold(0, (sum, c) => sum + c.talkedMinutes),
    );
  }

  /// The last seven days, oldest first.
  List<DayEarning> get week {
    final today = _dayStart(DateTime.now());
    return [
      for (var i = 6; i >= 0; i--)
        (
          day: today.subtract(Duration(days: i)),
          amount: earnedOn(today.subtract(Duration(days: i))),
          isToday: i == 0,
        ),
    ];
  }

  List<Consultation> get today =>
      allSessions.where((c) => _sameDay(c.happenedAt?.toLocal(), DateTime.now())).toList()
        ..sort((a, b) => (a.happenedAt ?? DateTime(0)).compareTo(b.happenedAt ?? DateTime(0)));

  // ── Lifecycle ────────────────────────────────────────────────────────────

  void _onAuthChanged() {
    if (_auth.isAdvocate && !_running) {
      _start();
    } else if (!_auth.isAdvocate && _running) {
      _stop();
    }
  }

  void _start() {
    _running = true;
    _available = _auth.advocate?.available ?? false;
    refreshAll();
    _schedule();
    // Not awaited: registering this device for push is a convenience the
    // sign-in itself must never wait on.
    unawaited(_push?.start());
  }

  void _schedule() {
    _fastPoll?.cancel();
    _slowPoll?.cancel();
    if (!_running || _paused) return;
    _fastPoll = Timer.periodic(AppConfig.inboxPoll, (_) => refreshInbox());
    _slowPoll = Timer.periodic(const Duration(seconds: 45), (_) {
      refreshHistory();
      refreshEarnings();
    });
  }

  void _stop() {
    _running = false;
    _fastPoll?.cancel();
    _slowPoll?.cancel();
    _inbox = [];
    _history = [];
    _earnings = Wallet.empty;
    _inboxLoaded = _historyLoaded = _earningsLoaded = false;
    _announced.clear();
    _announceReady = false;
    _toAnnounce = null;
    notifyListeners();
    // A phone signed out here must not go on ringing for the account it just
    // left — see PushService.stop.
    unawaited(_push?.stop());
  }

  /// The app went to the background (or came back). No heartbeat while
  /// nobody is looking, and a fresh read the moment they are.
  void setPaused(bool paused) {
    if (_paused == paused || !_running) return;
    _paused = paused;
    if (!paused) refreshAll();
    _schedule();
  }

  Future<void> refreshAll() => Future.wait([refreshInbox(), refreshHistory(), refreshEarnings()]);

  Future<void> refreshInbox() async {
    try {
      final list = await _consults.inbox();
      if (!_running) return;
      final beforeLive = _inbox.where((c) => c.status.isLive).map((c) => c.id).toSet();
      _inbox = list;
      _inboxLoaded = true;
      _error = null;

      for (final c in list) {
        if (c.status.isWaiting && !_announced.contains(c.id)) {
          _announced.add(c.id);
          // The very first read is not "new" — those were waiting before the
          // app opened, and the Requests tab shows them without a ring.
          if (_announceReady) _toAnnounce ??= c;
        }
      }
      _announceReady = true;

      // A session that just left the live list has settled — its earnings and
      // history row are worth reading now rather than on the slow tick.
      final nowLive = list.where((c) => c.status.isLive).map((c) => c.id).toSet();
      if (beforeLive.difference(nowLive).isNotEmpty) {
        refreshHistory();
        refreshEarnings();
      }
    } on ApiException catch (e) {
      _error = e;
    }
    notifyListeners();
  }

  bool _announceReady = false;

  Future<void> refreshHistory() async {
    try {
      final list = await _consults.history();
      if (!_running) return;
      _history = list;
      _historyLoaded = true;
    } on ApiException catch (e) {
      _error ??= e;
    }
    notifyListeners();
  }

  Future<void> refreshEarnings() async {
    try {
      final wallet = await _dashboard.earnings();
      if (!_running) return;
      _earnings = wallet;
      _earningsLoaded = true;
    } on ApiException {
      // The earnings card simply keeps its last figure.
    }
    notifyListeners();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  /// Accepts a request. Returns the session to open, or throws the server's
  /// reason (the client ran out of balance, someone else got there first).
  Future<Consultation> accept(String id) => _act(id, () => _consults.accept(id));

  Future<Consultation> reject(String id) => _act(id, () => _consults.reject(id));

  Future<Consultation> end(String id) => _act(id, () => _consults.end(id));

  Future<Consultation> _act(String id, Future<Consultation> Function() call) async {
    _busy.add(id);
    notifyListeners();
    try {
      return await call();
    } finally {
      _busy.remove(id);
      await refreshInbox();
      refreshHistory();
    }
  }

  /// The online switch. Optimistic, and put back if the save fails.
  Future<void> setAvailable(bool value) async {
    final before = _available;
    _available = value;
    _savingAvailability = true;
    notifyListeners();
    try {
      _available = await _dashboard.setAvailable(value);
    } on ApiException {
      _available = before;
      rethrow;
    } finally {
      _savingAvailability = false;
      notifyListeners();
    }
  }

  bool _disposed = false;

  /// A read that was in flight when the app tore this down must not notify a
  /// disposed notifier.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _running = false;
    _auth.removeListener(_onAuthChanged);
    _fastPoll?.cancel();
    _slowPoll?.cancel();
    super.dispose();
  }
}

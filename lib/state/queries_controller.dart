import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../models/legal_query.dart';
import '../services/query_service.dart';
import 'auth_controller.dart';

/// The lawyer's client-query board: the open pool, the queries they took, the
/// ones they resolved, and this month's credits.
///
/// Runs only while a lawyer is signed in. Re-reads every minute so the Home
/// card and the tab count follow other lawyers taking queries, and straight
/// after every action so a claimed query leaves the list at once.
class QueriesController extends ChangeNotifier {
  QueriesController(this._service, this._auth) {
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final QueryService _service;
  final AuthController _auth;

  Timer? _poll;
  bool _running = false;

  QueryBoard _board = QueryBoard.empty;
  bool _loaded = false;
  bool _loading = false;
  ApiException? _error;
  final Set<String> _busy = {};

  QueryBoard get board => _board;
  bool get loaded => _loaded;
  bool get loading => _loading;
  ApiException? get error => _error;
  bool isBusy(String id) => _busy.contains(id);

  bool get locked => _board.locked;
  QueryCredits get credits => _board.credits;
  int get openCount => _board.locked ? _board.openTotal : _board.open.length;

  void _onAuthChanged() {
    if (_auth.isAdvocate && !_running) {
      _running = true;
      refresh();
      _poll = Timer.periodic(const Duration(seconds: 60), (_) => refresh(silent: true));
    } else if (!_auth.isAdvocate && _running) {
      _running = false;
      _poll?.cancel();
      _board = QueryBoard.empty;
      _loaded = false;
      _error = null;
      notifyListeners();
    }
  }

  Future<void> refresh({bool silent = false}) async {
    if (!_running) return;
    if (!silent) {
      _loading = true;
      notifyListeners();
    }
    try {
      _board = await _service.board();
      _loaded = true;
      _error = null;
    } on ApiException catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Takes a query for one credit; returns it with the client's contact.
  /// Throws the server's reason — `taken`, `no_plan`, `no_credits`.
  Future<LegalQuery> claim(String id) => _act(id, () => _service.claim(id));

  Future<void> release(String id) => _act<void>(id, () => _service.release(id));

  Future<LegalQuery> resolve(String id, {String note = ''}) =>
      _act(id, () => _service.resolve(id, note: note));

  Future<T> _act<T>(String id, Future<T> Function() call) async {
    _busy.add(id);
    notifyListeners();
    try {
      return await call();
    } finally {
      _busy.remove(id);
      // Refreshed whether it worked or not: a 409 means the pool moved on.
      await refresh(silent: true);
    }
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _running = false;
    _poll?.cancel();
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}

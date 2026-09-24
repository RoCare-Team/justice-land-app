import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/advocate.dart';

/// One lawyer the client has kept, as the device remembers them.
///
/// The name is stored alongside the identifiers so the saved list can be drawn
/// the moment it opens, before any of the profiles have been fetched back.
@immutable
class SavedLawyer {
  const SavedLawyer({required this.id, required this.path, required this.name});

  final String id;

  /// `advocate-manoj-sharma-jusld04` — what the profile endpoint is keyed on.
  final String path;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'name': name};

  static SavedLawyer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}';
    final path = '${raw['path'] ?? ''}';
    if (id.isEmpty || path.isEmpty) return null;
    return SavedLawyer(id: id, path: path, name: '${raw['name'] ?? ''}');
  }
}

/// The heart on a lawyer's card: a shortlist the client keeps while deciding.
///
/// Kept on the device rather than on the server, because the platform has no
/// saved-lawyers endpoint — the website does not offer the feature at all. A
/// shortlist is private, low-stakes and useful straight away, so it is worth
/// having on this one device now; if an endpoint arrives later this controller
/// is the one place that has to change, and the stored list can be uploaded as
/// it is. The consequence to be honest about: it does not follow the client to
/// a new phone, and it survives signing out, which is why nothing in it is
/// more private than a list of public profiles.
class SavedLawyersController extends ChangeNotifier {
  static const _key = 'saved_lawyers_v1';

  List<SavedLawyer> _items = const [];
  bool _loaded = false;

  /// Newest first — the last lawyer saved is the one being thought about.
  List<SavedLawyer> get items => List.unmodifiable(_items);
  int get count => _items.length;
  bool get isLoaded => _loaded;
  bool get isEmpty => _items.isEmpty;

  bool isSaved(String advocateId) =>
      advocateId.isNotEmpty && _items.any((s) => s.id == advocateId);

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _items = decoded
              .map(SavedLawyer.fromJson)
              .whereType<SavedLawyer>()
              .toList(growable: false);
        }
      }
    } catch (_) {
      // Unreadable or from an older shape: an empty shortlist is a fair
      // starting point, and losing it must never stop the app opening.
      _items = const [];
    }
    _loaded = true;
    notifyListeners();
  }

  /// Saves or unsaves, and reports which it did so the screen can say so.
  Future<bool> toggle(Advocate advocate) async {
    final id = advocate.id;
    if (id.isEmpty) return false;
    final saved = isSaved(id);
    if (saved) {
      _items = _items.where((s) => s.id != id).toList(growable: false);
    } else {
      _items = [
        SavedLawyer(id: id, path: advocate.profilePath, name: advocate.name),
        ..._items.where((s) => s.id != id),
      ];
    }
    notifyListeners();
    await _persist();
    return !saved;
  }

  Future<void> remove(String advocateId) async {
    if (!isSaved(advocateId)) return;
    _items = _items.where((s) => s.id != advocateId).toList(growable: false);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_items.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(
          _key,
          jsonEncode(_items.map((s) => s.toJson()).toList()),
        );
      }
    } catch (_) {
      // The list stays in memory for this run; a shortlist is not worth an
      // error dialog over.
    }
  }
}

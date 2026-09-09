import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/content_service.dart';

/// The visitor's chosen location.
///
/// Remembered so nobody is asked twice, and shown in the header — but it does
/// NOT filter the directory on its own. On the website a picked location used
/// to arrive with a 100 km radius already applied, and someone opening the
/// directory from a city with no nearby lawyers was met with "0 lawyers found
/// within 100 km": a filter they never set, hiding every lawyer on the site.
/// Narrowing by distance is the visitor's move to make.
class LocationController extends ChangeNotifier {
  LocationController(this._content);

  final ContentService _content;

  static const String _keyLabel = 'jl_location_label';
  static const String _keyCity = 'jl_location_city';
  static const String _keyLat = 'jl_location_lat';
  static const String _keyLng = 'jl_location_lng';

  String _label = '';
  String _city = '';
  double? _lat;
  double? _lng;
  bool _locating = false;
  String? _error;

  String get label => _label;
  String get city => _city;
  double? get lat => _lat;
  double? get lng => _lng;
  bool get locating => _locating;
  String? get error => _error;
  bool get hasLocation => _lat != null && _lng != null;
  bool get hasCity => _city.isNotEmpty;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _label = prefs.getString(_keyLabel) ?? '';
    _city = prefs.getString(_keyCity) ?? '';
    _lat = prefs.getDouble(_keyLat);
    _lng = prefs.getDouble(_keyLng);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_label.isEmpty && _city.isEmpty) {
      await prefs.remove(_keyLabel);
      await prefs.remove(_keyCity);
      await prefs.remove(_keyLat);
      await prefs.remove(_keyLng);
      return;
    }
    await prefs.setString(_keyLabel, _label);
    await prefs.setString(_keyCity, _city);
    if (_lat != null) await prefs.setDouble(_keyLat, _lat!);
    if (_lng != null) await prefs.setDouble(_keyLng, _lng!);
  }

  /// A city picked from the list — no coordinates, so no distance filtering,
  /// which is exactly right: "lawyers in Kanpur" is a city match, not a radius.
  Future<void> setCity(String city, {String? label}) async {
    _city = city;
    _label = label ?? city;
    _lat = null;
    _lng = null;
    _error = null;
    notifyListeners();
    await _persist();
  }

  /// Uses the device's position, then resolves it to a city so the directory
  /// can filter by name as well as by distance.
  Future<bool> useCurrentLocation() async {
    _locating = true;
    _error = null;
    notifyListeners();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _error = 'Location is switched off on this device. Turn it on, or pick a city.';
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _error = 'Location permission denied. Pick your city instead.';
        return false;
      }
      if (permission == LocationPermission.deniedForever) {
        _error = 'Location is blocked for this app. Enable it in Settings, or pick a city.';
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );
      _lat = position.latitude;
      _lng = position.longitude;
      _label = 'Your location';

      // Best effort — a failed reverse geocode still leaves usable coordinates.
      try {
        final place = await _content.reverseGeocode(_lat!, _lng!);
        final city = place['city'] ?? '';
        if (city.isNotEmpty) {
          _city = city;
          _label = place['label']?.isNotEmpty == true ? place['label']! : city;
        }
      } catch (_) {}

      await _persist();
      return true;
    } catch (e) {
      _error = 'Could not read your location. Pick your city instead.';
      return false;
    } finally {
      _locating = false;
      notifyListeners();
    }
  }

  /// PIN code → city, for people who would rather type than share a position.
  Future<bool> setFromPincode(String pincode) async {
    _locating = true;
    _error = null;
    notifyListeners();
    try {
      final place = await _content.lookupPincode(pincode);
      final city = place['city'] ?? '';
      if (city.isEmpty) {
        _error = 'We could not find that PIN code.';
        return false;
      }
      _city = city;
      _label = '$city ${pincode.trim()}'.trim();
      _lat = null;
      _lng = null;
      await _persist();
      return true;
    } catch (e) {
      _error = 'Could not look up that PIN code.';
      return false;
    } finally {
      _locating = false;
      notifyListeners();
    }
  }

  Future<void> clear() async {
    _label = '';
    _city = '';
    _lat = null;
    _lng = null;
    _error = null;
    notifyListeners();
    await _persist();
  }

  /// Straight-line kilometres to a point, for the "within N km" filter once the
  /// visitor has actually chosen one.
  double? distanceTo(double? otherLat, double? otherLng) {
    if (_lat == null || _lng == null || otherLat == null || otherLng == null) {
      return null;
    }
    return Geolocator.distanceBetween(_lat!, _lng!, otherLat, otherLng) / 1000;
  }
}

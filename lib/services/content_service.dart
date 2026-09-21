import '../core/config/reference_data.dart';
import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/account.dart';
import '../models/json.dart';

/// Cities, practice areas, blogs, testimonials and the contact form — the
/// parts of the site that are the same for everyone.
///
/// These lists barely change between app launches, so they are cached in
/// memory for the session. A pull-to-refresh anywhere they appear passes
/// `force: true` and goes back to the server.
class ContentService {
  ContentService(this._api);

  final ApiClient _api;

  List<City>? _cities;
  List<LegalService>? _services;

  /// One cached read of /api/services, shared by [services], [courts] and
  /// [languages] — they are three parts of one response, and opening the
  /// filter sheet should not fetch it three times.
  Map<String, dynamic>? _reference;

  Future<List<City>> cities({bool force = false}) async {
    final cached = _cities;
    if (cached != null && !force) return cached;
    final data = await _api.get(Endpoints.cities);
    final list = J.models(J.map(data)['cities'], City.fromJson);
    _cities = list;
    return list;
  }

  Future<List<LegalService>> services({bool force = false}) async {
    final cached = _services;
    if (cached != null && !force) return cached;
    final list =
        J.models((await _referenceData(force))['services'], LegalService.fromJson);
    if (list.isNotEmpty) {
      _services = list;
      return list;
    }
    // Offline. The practice areas are the spine of the whole directory, so the
    // screen opens on the list that shipped with the app rather than on an
    // error — without their matters, which only the server knows.
    return RefData.services
        .map((g) => LegalService(
              name: g.name,
              slug: g.slug,
              description: '',
              lawyerCount: 0,
              subServices: const [],
            ))
        .toList(growable: false);
  }

  /// The courts and the languages, which /api/services returns alongside the
  /// practice areas — they are the other two dropdowns on the same filter bar,
  /// so asking for them separately would be three round trips to draw one row.
  ///
  /// The fallback is [RefData], which is generated from the web app's own
  /// `src/data` and verified against it by `tool/check_reference_data.mjs`. It
  /// is a copy of a list, never of a rule: nothing the server decides is
  /// duplicated here, and if the server answers, the server wins.
  Future<List<String>> courts({bool force = false}) async {
    final list = J.strList((await _referenceData(force))['courts']);
    return list.isNotEmpty ? list : RefData.courts;
  }

  Future<List<String>> languages({bool force = false}) async {
    final list = J.strList((await _referenceData(force))['languages']);
    return list.isNotEmpty ? list : RefData.languages;
  }

  Future<Map<String, dynamic>> _referenceData(bool force) async {
    final cached = _reference;
    if (cached != null && !force) return cached;
    try {
      final map = J.map(await _api.get(Endpoints.services));
      _reference = map;
      return map;
    } catch (_) {
      // Offline, or the server is down. Every caller falls back to RefData —
      // a filter sheet that will not open is worse than one built from the
      // list that shipped with the app.
      return const {};
    }
  }

  Future<List<BlogPost>> blogs({int page = 1, String category = ''}) async {
    final data = await _api.get(Endpoints.blogs, query: {
      'page': page,
      if (category.isNotEmpty) 'category': category,
    });
    return J.models(J.map(data)['blogs'] ?? data, BlogPost.fromJson);
  }

  Future<BlogPost> blog(String slug) async {
    final data = await _api.get(Endpoints.blog(slug));
    final map = J.map(data);
    return BlogPost.fromJson(J.map(map['blog'] ?? map));
  }

  Future<List<Testimonial>> testimonials() async {
    final data = await _api.get(Endpoints.testimonials);
    return J.models(J.map(data)['testimonials'] ?? data, Testimonial.fromJson);
  }

  /// Share your experience — a public review of the platform itself.
  Future<void> submitTestimonial({
    required String name,
    required int rating,
    required String text,
    String role = '',
    String city = '',
  }) async {
    await _api.post(Endpoints.testimonials, body: {
      'name': name,
      'rating': rating,
      'text': text,
      if (role.isNotEmpty) 'role': role,
      if (city.isNotEmpty) 'city': city,
    });
  }

  Future<void> submitContact({
    required String name,
    required String email,
    required String phone,
    required String subject,
    required String message,
  }) async {
    await _api.post(Endpoints.contact, body: {
      'name': name,
      'email': email,
      'phone': phone,
      'subject': subject,
      'message': message,
    });
  }

  /// PIN code → city and state, for the location picker.
  Future<Map<String, String>> lookupPincode(String pincode) async {
    final data = await _api.get(Endpoints.pincode, query: {'code': pincode.trim()});
    final map = J.map(data);
    return {
      'city': J.str(map['city']),
      'state': J.str(map['state']),
    };
  }

  /// Coordinates → the nearest known city.
  Future<Map<String, String>> reverseGeocode(double lat, double lng) async {
    final data = await _api.get(Endpoints.geocode, query: {
      'lat': lat,
      'lng': lng,
    });
    final map = J.map(data);
    return {
      'city': J.str(map['city']),
      'state': J.str(map['state']),
      'label': J.str(map['label'] ?? map['city']),
    };
  }
}

import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/advocate.dart';
import '../models/json.dart';

/// Everything the directory asks for, in one filter object. Mirrors the query
/// the web listing builds so the same search returns the same lawyers.
class AdvocateQuery {
  const AdvocateQuery({
    this.query = '',
    this.city = '',
    this.service = '',
    this.subService = '',
    this.court = '',
    this.language = '',
    this.minExperience = 0,
    this.maxFee = 0,
    this.verifiedOnly = false,
    this.availability = '',
    this.sort = 'relevance',
    this.page = 1,
    this.perPage = 20,
  });

  final String query;
  final String city;
  final String service;
  final String subService;
  final String court;

  /// A language the lawyer consults in. One, not a set: someone filtering by
  /// language is looking for the one they are comfortable speaking.
  final String language;

  /// Years in practice, as a floor. 0 means no floor.
  final int minExperience;

  /// A ceiling on the cheapest per-minute rate, in rupees. 0 means no ceiling.
  /// A lawyer who publishes no live rate has no price to compare and is not
  /// kept by this filter — they are someone you have to ask, not someone cheap.
  final int maxFee;

  /// Only lawyers an admin has verified. Off by default: verification is done
  /// by hand, so switching it on can legitimately empty the list.
  final bool verifiedOnly;

  /// '' | 'online' | 'offline'
  final String availability;

  /// 'relevance' | 'rating' | 'experience' | 'fee-low' | 'fee-high'
  final String sort;

  final int page;
  final int perPage;

  bool get hasFilters =>
      query.isNotEmpty ||
      city.isNotEmpty ||
      service.isNotEmpty ||
      subService.isNotEmpty ||
      court.isNotEmpty ||
      language.isNotEmpty ||
      minExperience > 0 ||
      maxFee > 0 ||
      verifiedOnly ||
      availability.isNotEmpty ||
      sort != 'relevance';

  /// How many filters are on, for the badge on the filter button.
  int get activeCount => [
        city.isNotEmpty,
        service.isNotEmpty,
        subService.isNotEmpty,
        court.isNotEmpty,
        language.isNotEmpty,
        minExperience > 0,
        maxFee > 0,
        verifiedOnly,
        availability.isNotEmpty,
      ].where((on) => on).length;

  AdvocateQuery copyWith({
    String? query,
    String? city,
    String? service,
    String? subService,
    String? court,
    String? language,
    int? minExperience,
    int? maxFee,
    bool? verifiedOnly,
    String? availability,
    String? sort,
    int? page,
  }) =>
      AdvocateQuery(
        query: query ?? this.query,
        city: city ?? this.city,
        service: service ?? this.service,
        subService: subService ?? this.subService,
        court: court ?? this.court,
        language: language ?? this.language,
        minExperience: minExperience ?? this.minExperience,
        maxFee: maxFee ?? this.maxFee,
        verifiedOnly: verifiedOnly ?? this.verifiedOnly,
        availability: availability ?? this.availability,
        sort: sort ?? this.sort,
        page: page ?? this.page,
        perPage: perPage,
      );

  /// Only what is actually set. An empty filter is left out rather than sent as
  /// an empty string, so the request reads as what the visitor asked for.
  Map<String, dynamic> toParams() {
    final p = <String, dynamic>{'page': page, 'perPage': perPage};
    if (query.isNotEmpty) p['q'] = query;
    if (city.isNotEmpty) p['city'] = city;
    if (service.isNotEmpty) p['service'] = service;
    if (subService.isNotEmpty) p['subService'] = subService;
    if (court.isNotEmpty) p['court'] = court;
    if (language.isNotEmpty) p['language'] = language;
    if (minExperience > 0) p['minExperience'] = minExperience;
    if (maxFee > 0) p['maxFee'] = maxFee;
    if (verifiedOnly) p['verified'] = 'true';
    if (availability.isNotEmpty) p['availability'] = availability;
    if (sort != 'relevance') p['sort'] = sort;
    return p;
  }
}

/// One page of directory results.
class AdvocatePage {
  const AdvocatePage({
    required this.advocates,
    required this.total,
    required this.page,
    required this.totalPages,
  });

  final List<Advocate> advocates;
  final int total;
  final int page;
  final int totalPages;

  bool get hasMore => page < totalPages;

  static const AdvocatePage empty =
      AdvocatePage(advocates: [], total: 0, page: 1, totalPages: 1);

  factory AdvocatePage.fromJson(Map<String, dynamic> j) => AdvocatePage(
        advocates: J.models(j['advocates'] ?? j['rows'], Advocate.fromJson),
        total: J.int$(j['total']),
        page: J.int$(j['page'], 1),
        totalPages: J.int$(j['totalPages'], 1),
      );
}

/// What /api/advocates/nearby answered, and how firm the match was.
class NearbyAdvocates {
  const NearbyAdvocates({
    required this.scope,
    required this.place,
    required this.total,
    required this.advocates,
  });

  /// 'city' · 'state' · 'nearby' · 'all', weakest last. Anything else is a
  /// scope this build does not know about, and is treated as 'all' — a heading
  /// that overclaims is worse than one that says less than it could.
  final String scope;

  /// The place [scope] refers to: a city or a state name, empty for the rest.
  final String place;
  final int total;
  final List<Advocate> advocates;

  static const NearbyAdvocates empty =
      NearbyAdvocates(scope: 'all', place: '', total: 0, advocates: []);

  bool get isLocal => scope == 'city' || scope == 'state';
  bool get isNear => scope == 'nearby';

  factory NearbyAdvocates.fromJson(Map<String, dynamic> j) => NearbyAdvocates(
        scope: J.str(j['scope'], 'all'),
        place: J.str(j['place']),
        total: J.int$(j['total']),
        advocates: J.models(j['advocates'], Advocate.fromJson),
      );
}

class AdvocateService {
  AdvocateService(this._api);

  final ApiClient _api;

  Future<AdvocatePage> search(AdvocateQuery query) async {
    final data = await _api.get(Endpoints.advocates, query: query.toParams());
    return AdvocatePage.fromJson(J.map(data));
  }

  /// Lawyers where the visitor actually is.
  ///
  /// The same call the website's home page makes once someone allows the
  /// location prompt, and it answers the same way: the visitor's own city if
  /// anyone practises there, then their state, then whoever is within reach of
  /// the coordinates, and only then the directory at large. [NearbyAdvocates.scope]
  /// says which of those answered, so the screen can name the place honestly
  /// instead of putting a city heading over lawyers from three states away.
  Future<NearbyAdvocates> nearby({
    String city = '',
    String state = '',
    double? lat,
    double? lng,
    int limit = 12,
  }) async {
    final data = await _api.get(Endpoints.advocatesNearby, query: {
      if (city.isNotEmpty) 'city': city,
      if (state.isNotEmpty) 'state': state,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'limit': limit,
    });
    return NearbyAdvocates.fromJson(J.map(data));
  }

  /// A single profile, by canonical path (`advocate-manoj-sharma-jusld04`) or
  /// by Justiceland ID.
  Future<Advocate> profile(String idOrPath) async {
    final data = await _api.get(Endpoints.advocate(idOrPath));
    return Advocate.fromJson(J.map(J.map(data)['advocate']));
  }

  /// Which of these lawyers are reachable right now.
  ///
  /// Availability is deliberately not part of the profile response: those
  /// reads are cached, and a "live" flag baked into a cached profile keeps
  /// showing a stale green dot for the whole cache window.
  Future<Set<String>> onlineAmong(List<String> advocateIds) async {
    if (advocateIds.isEmpty) return {};
    final data = await _api.get(
      Endpoints.presence,
      query: {'ids': advocateIds.join(',')},
    );
    final map = J.map(data);
    final online = map['online'];
    if (online is List) return J.strList(online).toSet();
    // Also accepts { "<id>": true } for flexibility.
    return map.entries
        .where((e) => J.flag(e.value))
        .map((e) => e.key)
        .toSet();
  }

  /// Posts a client review onto a lawyer's profile.
  Future<void> submitReview({
    required String legalCareId,
    required String author,
    required int rating,
    required String text,
  }) async {
    await _api.post(
      Endpoints.advocateReviews(legalCareId),
      body: {'author': author, 'rating': rating, 'text': text},
    );
  }

  /// Sends an enquiry to a lawyer. Requires a signed-in session, same as the
  /// contact gate on the web profile.
  Future<void> sendEnquiry({
    required String advocateId,
    required String name,
    required String phone,
    String email = '',
    String preferredDate = '',
    required String message,
  }) async {
    await _api.post(Endpoints.enquiries, body: {
      'advocateId': advocateId,
      'name': name,
      'phone': phone,
      if (email.isNotEmpty) 'email': email,
      if (preferredDate.isNotEmpty) 'preferredDate': preferredDate,
      'message': message,
    });
  }
}

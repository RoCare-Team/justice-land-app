import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/json.dart';
import '../models/legal_query.dart';

/// Client queries — both sides of them.
///
/// Anyone can post one (no session needed). A lawyer reads the pool, takes a
/// query for one credit, and releases or resolves it. Every rule — who can see
/// what, the masking, the credit spend, the one-lawyer-per-query race — is the
/// server's; this only carries the requests.
class QueryService {
  QueryService(this._api);

  final ApiClient _api;

  /// Posts a legal problem. Returns the new query's id.
  Future<String> ask({
    required String name,
    required String phone,
    required String message,
    String email = '',
    String category = '',
    String city = '',
  }) async {
    final data = await _api.post(Endpoints.askQuery, body: {
      'name': name,
      'phone': phone,
      'email': email,
      'category': category,
      'city': city,
      'message': message,
    });
    return J.str(J.map(data)['id']);
  }

  /// The lawyer's board: open pool, their own, resolved, and credits.
  Future<QueryBoard> board({String category = ''}) async {
    final data = await _api.get(
      Endpoints.lawyerQueries,
      query: category.isEmpty ? null : {'category': category},
    );
    return QueryBoard.fromJson(J.map(data));
  }

  /// Takes a query for one credit. Throws with code `taken`, `no_plan` or
  /// `no_credits` when it cannot.
  Future<LegalQuery> claim(String id) => _act(id, {'action': 'claim'});

  /// Puts it back in the pool. The credit is not returned.
  Future<void> release(String id) => _act(id, {'action': 'release'});

  /// Done with — it leaves the pool for every lawyer.
  Future<LegalQuery> resolve(String id, {String note = ''}) =>
      _act(id, {'action': 'resolve', 'note': note});

  Future<LegalQuery> _act(String id, Map<String, dynamic> body) async {
    final data = await _api.patch(Endpoints.lawyerQuery(id), body: body);
    return LegalQuery.fromJson(J.map(J.map(data)['query']));
  }
}

/// Tolerant readers for JSON coming off the API.
///
/// The backend is a Mongo-backed Next.js app: a field can be absent on an
/// older document, a number can arrive as a string, an id can be an ObjectId
/// rendered as `{ $oid: ... }`. Parsing defensively here means one bad record
/// renders with a gap instead of throwing and blanking the whole screen.
class J {
  const J._();

  static String str(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    if (v is String) return v;
    return v.toString();
  }

  static String id(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is Map) {
      final oid = v[r'$oid'];
      if (oid != null) return oid.toString();
      final inner = v['_id'] ?? v['id'];
      if (inner != null) return id(inner);
    }
    return v.toString();
  }

  static int int$(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? num.tryParse(v.toString())?.round() ?? fallback;
  }

  static double dbl(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  static bool flag(dynamic v, [bool fallback = false]) {
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return fallback;
  }

  static DateTime? date(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is Map && v[r'$date'] != null) return date(v[r'$date']);
    return DateTime.tryParse(v.toString());
  }

  static List<String> strList(dynamic v) {
    if (v is! List) return const [];
    return v.where((e) => e != null).map((e) => e.toString()).toList();
  }

  static Map<String, dynamic> map(dynamic v) {
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return const {};
  }

  static List<Map<String, dynamic>> mapList(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map(map).toList();
  }

  /// Maps a JSON list into models, skipping anything that will not parse
  /// rather than losing the whole list to one malformed row.
  static List<T> models<T>(dynamic v, T Function(Map<String, dynamic>) build) {
    final out = <T>[];
    for (final row in mapList(v)) {
      try {
        out.add(build(row));
      } catch (_) {
        continue;
      }
    }
    return out;
  }
}

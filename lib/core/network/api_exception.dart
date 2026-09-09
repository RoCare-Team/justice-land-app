/// A failed API call, carrying enough detail for the UI to react properly.
///
/// The backend does not just return "an error": it returns codes the flow
/// depends on — `insufficient` means show the wallet, `offline` means the
/// lawyer cannot be reached, `expired` means the leftover time is gone. Losing
/// those distinctions would turn precise screens into a generic "try again".
class ApiException implements Exception {
  ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.isNetwork = false,
  });

  /// Human-readable text, safe to show as-is.
  final String message;

  final int? statusCode;

  /// The machine-readable `error` field when the server sends one:
  /// 'insufficient' | 'offline' | 'expired' | 'call-failed' | 'invalid' | …
  final String? code;

  /// True when the request never reached the server (no signal, timeout).
  final bool isNetwork;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;

  /// The user's wallet cannot cover the booking.
  bool get isInsufficientBalance => statusCode == 402 || code == 'insufficient';

  /// The lawyer has switched themselves offline.
  bool get isAdvocateOffline => code == 'offline';

  @override
  String toString() => 'ApiException($statusCode/$code): $message';
}

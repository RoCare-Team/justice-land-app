import 'package:intl/intl.dart';

/// Display helpers that match the website's, so the same session shows the
/// same numbers and dates on both.
class Fmt {
  const Fmt._();

  static final NumberFormat _inr = NumberFormat.decimalPattern('en_IN');

  /// `₹1,558` — Indian grouping, no paise. Rates and wallet balances are whole
  /// rupees; a running bill is not (see [amount]).
  static String money(num? value) => '₹${_inr.format((value ?? 0).round())}';

  /// `₹26.67` — a live bill, which is charged by the second and so lands on
  /// paise. Rounding it to rupees on screen would show a figure the wallet
  /// never moves by. Whole amounts keep their plain form.
  static String amount(num? value) {
    final v = (value ?? 0).toDouble();
    if (v == v.roundToDouble()) return money(v);
    return '₹${v.toStringAsFixed(2)}';
  }

  /// `₹40/min`, the way a rate is written everywhere on the site.
  static String rate(num? perMinute) => '${money(perMinute)}/min';

  /// `18 Aug 2026`
  static String date(dynamic value) {
    final d = _toDate(value);
    if (d == null) return '';
    return DateFormat('d MMM yyyy').format(d);
  }

  /// `18 Aug 2026, 4:05 PM`
  static String dateTime(dynamic value) {
    final d = _toDate(value);
    if (d == null) return '';
    return DateFormat('d MMM yyyy, h:mm a').format(d);
  }

  /// `4:05 PM` — chat bubbles only need the time.
  static String time(dynamic value) {
    final d = _toDate(value);
    if (d == null) return '';
    return DateFormat('h:mm a').format(d);
  }

  /// `2 hours ago`, the same wording the testimonials carry on the web.
  static String timeAgo(dynamic value) {
    final d = _toDate(value);
    if (d == null) return '';
    final seconds = DateTime.now().difference(d).inSeconds;
    if (seconds < 60) return 'just now';

    const units = <List<Object>>[
      ['year', 31536000],
      ['month', 2592000],
      ['week', 604800],
      ['day', 86400],
      ['hour', 3600],
      ['minute', 60],
    ];
    for (final unit in units) {
      final name = unit[0] as String;
      final size = unit[1] as int;
      final n = seconds ~/ size;
      if (n >= 1) return '$n $name${n > 1 ? 's' : ''} ago';
    }
    return 'just now';
  }

  /// `12:04`, or `1:05:30` past an hour — the live consultation clock.
  static String clock(Duration d) {
    final total = d.isNegative ? Duration.zero : d;
    final s = (total.inSeconds % 60).toString().padLeft(2, '0');
    if (total.inHours > 0) {
      final m = (total.inMinutes % 60).toString().padLeft(2, '0');
      return '${total.inHours}:$m:$s';
    }
    final m = total.inMinutes.toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// `8 min 20 sec left` — how leftover time is offered for a free resume.
  static String leftover(int seconds) {
    if (seconds <= 0) return 'No time left';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return '$s sec left';
    if (s == 0) return '$m min left';
    return '$m min $s sec left';
  }

  /// `8+ years`
  static String experience(num? years) {
    final y = (years ?? 0).round();
    if (y <= 0) return 'New practitioner';
    return '$y+ ${y == 1 ? 'year' : 'years'}';
  }

  static String rating(num? value) => (value ?? 0).toStringAsFixed(1);

  /// `+91 98765 43210` for display; the raw digits are what the API gets.
  static String phone(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      return '+91 ${digits.substring(0, 5)} ${digits.substring(5)}';
    }
    if (digits.length == 12 && digits.startsWith('91')) {
      return '+91 ${digits.substring(2, 7)} ${digits.substring(7)}';
    }
    return raw ?? '';
  }

  /// First letter, for the avatar fallback. Strips the "Adv." the site strips.
  static String initial(String? name) {
    final clean = (name ?? '').replaceFirst(RegExp(r'^Adv\.?\s*', caseSensitive: false), '').trim();
    return clean.isEmpty ? '?' : clean[0].toUpperCase();
  }

  static String pluralize(int count, String singular, [String? plural]) =>
      '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    final parsed = DateTime.tryParse(value.toString());
    return parsed?.toLocal();
  }
}

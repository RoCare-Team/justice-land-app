/// Client-side validation, copied rule for rule from the web app's
/// `lib/registerValidation.js` and its API routes.
///
/// These exist to tell someone what is wrong before a round trip — they are
/// not the enforcement. The server validates everything again, and it is the
/// server's answer that decides. Keeping the two in step matters: a field the
/// app accepts and the API rejects produces an error with no field attached to
/// it, which is the worst kind to debug from a phone.
class Validators {
  const Validators._();

  // ── Rate bounds, from constants/callRates.js ─────────────────────────────
  static const int minRate = 1;
  static const int maxRate = 5000;

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp _mobile = RegExp(r'^[6-9]\d{9}$');
  /// Indian PIN codes are six digits and never start with zero.
  static final RegExp _pincode = RegExp(r'^[1-9][0-9]{5}$');
  static final RegExp _digits = RegExp(r'\D');

  static bool isEmail(String? v) => _email.hasMatch((v ?? '').trim());

  /// The API accepts any 10+ digit number for enquiries, but a login number
  /// must be a real Indian mobile — that is the account's identity.
  static bool isMobile(String? v) =>
      _mobile.hasMatch((v ?? '').replaceAll(_digits, ''));

  static bool isPhoneLoose(String? v) =>
      (v ?? '').replaceAll(_digits, '').length >= 10;

  static bool isPincode(String? v) => _pincode.hasMatch((v ?? '').trim());

  // Payout details, from constants/payouts.js — the server checks them again.
  static final RegExp _ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final RegExp _pan = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
  static final RegExp _accountNumber = RegExp(r'^\d{9,18}$');

  /// Four letters, a zero, six letters or digits — HDFC0001234.
  static bool isIfsc(String? v) => _ifsc.hasMatch((v ?? '').trim().toUpperCase());

  /// Five letters, four digits, a letter — ABCDE1234F.
  static bool isPan(String? v) => _pan.hasMatch((v ?? '').trim().toUpperCase());

  /// Nine to eighteen digits; spaces typed for readability are ignored.
  static bool isAccountNumber(String? v) =>
      _accountNumber.hasMatch((v ?? '').replaceAll(RegExp(r'\s+'), ''));

  static String digitsOnly(String? v) => (v ?? '').replaceAll(_digits, '');

  // ── Field validators, shaped for TextFormField.validator ─────────────────

  static String? required$(String? v, String label) =>
      (v ?? '').trim().isEmpty ? '$label is required.' : null;

  static String? fullName(String? v) =>
      (v ?? '').trim().isEmpty ? 'Full name is required.' : null;

  static String? email(String? v) =>
      isEmail(v) ? null : 'Enter a valid email address.';

  static String? mobile(String? v) =>
      isMobile(v) ? null : 'Enter a valid 10-digit mobile number.';

  static String? phoneLoose(String? v) =>
      isPhoneLoose(v) ? null : 'Please enter a valid phone number.';

  static String? password(String? v) =>
      (v ?? '').length < 8 ? 'Use at least 8 characters.' : null;

  static String? confirmPassword(String? v, String password) =>
      v != password ? 'Passwords do not match.' : null;

  /// Optional field — but a PIN that was typed has to be a real one.
  static String? optionalPincode(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return null;
    return isPincode(value) ? null : 'Enter a valid 6-digit PIN code.';
  }

  static String? experience(String? v) {
    final n = num.tryParse((v ?? '').trim());
    if (n == null || n < 0) return 'Enter your years of experience.';
    return null;
  }

  /// A blank rate means the lawyer does not offer that channel, which is
  /// allowed. A rate that was typed has to be usable.
  static String? optionalRate(String? v) {
    final raw = (v ?? '').trim();
    if (raw.isEmpty) return null;
    final n = num.tryParse(raw);
    if (n == null || n < minRate || n > maxRate) {
      return 'Enter a rate between ₹$minRate and ₹$maxRate per minute.';
    }
    return null;
  }

  static String? about(String? v) => (v ?? '').trim().length < 40
      ? 'About should be at least 40 characters.'
      : null;

  /// Enquiry message — the API asks for a sentence or two.
  static String? enquiryMessage(String? v) => (v ?? '').trim().length < 10
      ? 'Please describe your legal matter in a sentence or two.'
      : null;

  static String? reviewText(String? v) => (v ?? '').trim().length < 5
      ? 'Please write a short review (at least 5 characters).'
      : null;

  static String? testimonialText(String? v) => (v ?? '').trim().length < 10
      ? 'Please write at least a sentence about your experience.'
      : null;

  /// Wallet top-up, matching /api/wallet/order's floor and ceiling.
  static String? topUp(String? v, {int min = 50, int max = 100000}) {
    final raw = (v ?? '').trim();
    if (raw.isEmpty) return 'Enter an amount.';
    final n = num.tryParse(raw);
    if (n == null || n <= 0) return 'Enter a valid amount.';
    if (n < min) return 'The smallest top-up is ₹$min.';
    if (n > max) return 'You can add up to ₹$max at a time.';
    return null;
  }

  // ── Registration wizard, step by step ────────────────────────────────────
  // Mirrors validateStep() so the app blocks exactly where the site blocks.

  /// Step 0 · Personal
  static Map<String, String> stepPersonal({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required String confirm,
    required String state,
    required String city,
    required List<String> languages,
    String pincode = '',
  }) {
    final e = <String, String>{};
    if (fullName.trim().isEmpty) e['fullName'] = 'Full name is required.';
    if (!isEmail(email)) e['email'] = 'Enter a valid email address.';
    if (!isMobile(phone)) e['phone'] = 'Enter a valid 10-digit mobile number.';
    if (password.length < 8) e['password'] = 'Use at least 8 characters.';
    if (confirm != password) e['confirm'] = 'Passwords do not match.';
    if (state.trim().isEmpty) e['state'] = 'Select your state.';
    if (city.trim().isEmpty) e['city'] = 'Select your city.';
    if (languages.isEmpty) e['languages'] = 'Select at least one language.';
    final pin = optionalPincode(pincode);
    if (pin != null) e['pincode'] = pin;
    return e;
  }

  /// Step 1 · Professional
  static Map<String, String> stepProfessional({
    required String barCouncil,
    required String experienceYears,
    required String officeName,
    required String officeAddress,
    bool practiceFromResidence = false,
    String residencePincode = '',
  }) {
    final e = <String, String>{};
    if (barCouncil.trim().isEmpty) {
      e['barCouncil'] = 'Bar Council number is required.';
    }
    final exp = experience(experienceYears);
    if (exp != null) e['experience'] = exp;
    if (officeName.trim().isEmpty) e['officeName'] = 'Office name is required.';
    if (officeAddress.trim().isEmpty) {
      e['officeAddress'] = 'Office address is required.';
    }
    if (practiceFromResidence && residencePincode.trim().isNotEmpty) {
      final pin = optionalPincode(residencePincode);
      if (pin != null) e['residencePincode'] = pin;
    }
    return e;
  }

  /// Step 2 · Practice
  static Map<String, String> stepPractice({
    required List<String> courts,
    required List<String> services,
  }) {
    final e = <String, String>{};
    if (courts.isEmpty) {
      e['courts'] = 'Select at least one court you practise in.';
    }
    if (services.isEmpty) e['services'] = 'Select at least one practice area.';
    return e;
  }

  /// Step 3 · Consultation
  static Map<String, String> stepConsultation({
    required String chatRate,
    required String audioRate,
    required String videoRate,
    required String aboutText,
  }) {
    final e = <String, String>{};
    final chat = optionalRate(chatRate);
    if (chat != null) e['chatRate'] = chat;
    final audio = optionalRate(audioRate);
    if (audio != null) e['audioRate'] = audio;
    final video = optionalRate(videoRate);
    if (video != null) e['videoRate'] = video;
    final ab = about(aboutText);
    if (ab != null) e['about'] = ab;
    return e;
  }

  /// Step 4 · Review
  static Map<String, String> stepReview({required bool terms}) {
    return terms ? {} : {'terms': 'Please accept the terms to continue.'};
  }
}

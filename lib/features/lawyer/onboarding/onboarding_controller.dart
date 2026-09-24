import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../models/account.dart';
import '../../../models/advocate.dart';
import '../../../models/legal_query.dart';
import '../../../services/content_service.dart';
import '../../../services/dashboard_service.dart';
import '../../../services/membership_service.dart';
import '../../../state/membership_checkout.dart';
import 'plan_fit.dart';

/// Where the last step is: choosing, paying, saving, or finished.
enum OnboardingStage { idle, paying, saving, done }

typedef OnboardingDoc = ({String kind, String title, IconData icon});

/// Whether a choice went through, or is past what the lawyer's plan covers.
enum PickResult { ok, needsUpgrade }

/// The name a phone-only account carries until the profile step replaces it.
const String kPlaceholderName = 'New Advocate';

/// The state behind the five onboarding steps.
///
///   1 Verification  2 Specializations  3 Profile  4 Consultations  5 Earnings  6 Plan
///
/// Each step saves to the server when the lawyer continues. The plan's limits are
/// applied as choices are made: a practice area, matter or city past what the
/// current plan covers is refused with [PickResult.needsUpgrade], and the screen
/// opens the plans right there. Paying lifts the limit and the choice goes
/// through — the same as it always worked on the profile editor. The server holds
/// the same limits on save.
class OnboardingController extends ChangeNotifier {
  OnboardingController({
    required this.dashboard,
    required this.content,
    required this.membership,
    required this.advocate,
    required this.refreshAuth,
    required this.onCompleted,
    MembershipCheckout? checkout,
  }) : _checkout = checkout ?? MembershipCheckout(membership) {
    _init();
  }

  static const int stepCount = 6;
  static const int maxDocBytes = 5 * 1024 * 1024;

  static const List<OnboardingDoc> docKinds = [
    (kind: 'bar_council_certificate', title: 'Bar Council Certificate', icon: Icons.description_outlined),
    (kind: 'government_id', title: 'Government ID Proof', icon: Icons.badge_outlined),
  ];

  final DashboardService dashboard;
  final ContentService content;
  final MembershipService membership;
  final Advocate? advocate;

  /// Re-reads the signed-in lawyer after a plan changes.
  final Future<void> Function() refreshAuth;

  /// Marks onboarding finished for this install — the router stops sending the
  /// lawyer back here.
  final Future<void> Function() onCompleted;

  final MembershipCheckout _checkout;

  // ── Fields ───────────────────────────────────────────────────────────────
  final barCouncil = TextEditingController();
  final fullName = TextEditingController();
  final email = TextEditingController();
  final title = TextEditingController();
  final experience = TextEditingController();
  final pincode = TextEditingController();
  final chatRate = TextEditingController();
  final audioRate = TextEditingController();
  final videoRate = TextEditingController();
  final inPersonFee = TextEditingController();
  final holder = TextEditingController();
  final bankName = TextEditingController();
  final accountNumber = TextEditingController();
  final ifsc = TextEditingController();
  final pan = TextEditingController();
  late final List<TextEditingController> _fields;

  // ── State ────────────────────────────────────────────────────────────────
  int _step = 0;
  bool _loading = true;
  bool _disposed = false;

  /// Something that stops the whole flow (nothing loaded at all).
  String loadError = '';

  /// A failure on the current step, shown as a red banner.
  String error = '';

  /// A neutral note (a cancelled payment is not an error).
  String notice = '';

  bool saving = false;

  Map<String, VerificationDocument> docs = {};
  String uploadingKind = '';

  List<LegalService> services = [];
  final List<String> areas = [];
  final List<String> matters = [];

  List<City> cityOptions = [];
  String baseCity = '';
  String state = '';
  final List<String> cities = [];
  bool lookingUp = false;
  bool pincodeOk = false;
  String pincodeNote = '';
  String _lookedUp = '';

  String existingPhoto = '';
  Uint8List? photoBytes;
  String? photoDataUrl;

  /// Which ways this lawyer will consult, and at what price. A channel that
  /// is off is saved as 0, which is how the website reads "not offered".
  bool offersChat = false;
  bool offersAudio = false;
  bool offersVideo = false;
  bool offersInPerson = false;

  BankAccount? savedAccount;

  PlanCatalog? catalog;
  String selectedPlanId = '';
  OnboardingStage stage = OnboardingStage.idle;
  bool _paidAwaitingActivation = false;

  int get step => _step;
  bool get loading => _loading;

  void _init() {
    final a = advocate;
    barCouncil.text = a?.barCouncilNumber ?? '';
    // A phone-only account is named "New Advocate" until this step replaces it;
    // that is not something to show back as if the lawyer had typed it.
    fullName.text = a == null || a.name == kPlaceholderName ? '' : a.name;
    email.text = a?.contact.email ?? '';
    title.text = a?.tagline ?? '';
    if ((a?.experience ?? 0) > 0) experience.text = '${a!.experience}';
    pincode.text = a?.office.pincode ?? '';
    baseCity = (a?.city ?? '').trim();
    state = (a?.state ?? '').trim();
    areas.addAll(a?.specializations ?? const <String>[]);
    matters.addAll(a?.subSpecializations ?? const <String>[]);
    cities.addAll((a?.practiceCities ?? const <String>[]).where((c) => !_isBase(c)));
    existingPhoto = a?.photo ?? '';
    // A rate of 0 means the channel is not offered, so the switch starts off
    // and the field empty rather than showing "0".
    if ((a?.chatRate ?? 0) > 0) {
      offersChat = true;
      chatRate.text = '${a!.chatRate}';
    }
    if ((a?.audioRate ?? 0) > 0) {
      offersAudio = true;
      audioRate.text = '${a!.audioRate}';
    }
    if ((a?.videoRate ?? 0) > 0) {
      offersVideo = true;
      videoRate.text = '${a!.videoRate}';
    }
    if ((a?.consultationFee ?? 0) > 0) {
      offersInPerson = true;
      inPersonFee.text = '${a!.consultationFee}';
    }

    if (Validators.isPincode(pincode.text) && baseCity.isNotEmpty) {
      _lookedUp = pincode.text.trim();
      pincodeOk = true;
      pincodeNote = state.isEmpty ? baseCity : '$baseCity, $state';
    }

    _fields = [
      barCouncil, fullName, email, title, experience, pincode,
      chatRate, audioRate, videoRate, inPersonFee,
      holder, bankName, accountNumber, ifsc, pan,
    ];
    for (final f in _fields) {
      f.addListener(_onText);
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final f in _fields) {
      f.dispose();
    }
    _checkout.dispose();
    super.dispose();
  }

  bool _isBase(String city) => city.trim().toLowerCase() == baseCity.toLowerCase();

  // ── Loading ──────────────────────────────────────────────────────────────

  Future<void> load() async {
    try {
      docs = await dashboard.verificationDocuments();
    } on ApiException {
      // Not fatal: the lawyer can upload again.
    }
    try {
      services = await content.services();
    } on ApiException catch (e) {
      loadError = e.message;
    }
    try {
      cityOptions = await content.cities();
    } on ApiException {
      // Search and suggestions are a convenience; the base city still works.
    }
    try {
      catalog = await membership.catalog();
    } on ApiException {
      // The plan step retries on its own.
    }
    try {
      final accounts = await dashboard.bankAccounts();
      if (accounts.isNotEmpty) savedAccount = accounts.first;
    } on ApiException {
      // Treated as "none yet".
    }
    _pickDefaultPlan();
    _loading = false;
    notifyListeners();
  }

  void _pickDefaultPlan() {
    final c = catalog;
    if (c == null || c.plans.isEmpty) return;
    final current = c.plans.where((p) => p.id == c.currentPlanId);
    selectedPlanId = current.isNotEmpty ? current.first.id : c.plans.first.id;
  }

  /// Re-reads the plans — after an upgrade, or to retry a failed read. A plan
  /// the lawyer has just bought becomes the selected one, so the last step opens
  /// on it; a higher plan they had picked themselves is left alone.
  Future<void> reloadPlans() async {
    try {
      final fresh = await membership.catalog();
      final ids = [for (final p in fresh.plans) p.id];
      final selected = ids.indexOf(selectedPlanId);
      final current = ids.indexOf(fresh.currentPlanId);
      catalog = fresh;
      if (selected < 0 || selected < current) _pickDefaultPlan();
      error = '';
    } on ApiException catch (e) {
      error = e.message;
    }
    notifyListeners();
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  bool get canGoBack => _step > 0 && !saving && stage == OnboardingStage.idle;

  void back() {
    if (!canGoBack) return;
    error = '';
    notice = '';
    _step -= 1;
    notifyListeners();
  }

  /// From the plan step: the choices are too big for the plan, go and trim them.
  void editChoices() {
    if (stage == OnboardingStage.idle) _go(1);
  }

  void _go(int step) {
    error = '';
    notice = '';
    _step = step;
    notifyListeners();
  }

  // ── Text changes ─────────────────────────────────────────────────────────

  void _onText() {
    final pin = pincode.text.trim();
    if (Validators.isPincode(pin)) {
      if (pin != _lookedUp) {
        _lookedUp = pin;
        unawaited(_lookupPin(pin));
      }
    } else {
      _lookedUp = '';
      lookingUp = false;
      pincodeOk = false;
      pincodeNote = '';
    }
    notifyListeners();
  }

  /// A PIN code names the city and state, so the lawyer types one field rather
  /// than picking from two long lists.
  Future<void> _lookupPin(String pin) async {
    lookingUp = true;
    pincodeOk = false;
    pincodeNote = '';
    notifyListeners();
    try {
      final place = await content.lookupPincode(pin);
      if (pin != _lookedUp) return;
      final city = place['city'] ?? '';
      final st = place['state'] ?? '';
      if (city.isEmpty) {
        pincodeNote = 'We could not place that PIN code. Please check it.';
      } else {
        baseCity = city;
        state = st;
        cities.removeWhere(_isBase);
        pincodeOk = true;
        pincodeNote = st.isEmpty ? city : '$city, $st';
      }
    } on ApiException catch (e) {
      if (pin == _lookedUp) pincodeNote = e.message;
    } finally {
      if (pin == _lookedUp) lookingUp = false;
      notifyListeners();
    }
  }

  // ── Step 1: verification ─────────────────────────────────────────────────

  bool get canContinueVerification =>
      barCouncil.text.trim().length >= 3 &&
      docKinds.every((d) => docs.containsKey(d.kind)) &&
      uploadingKind.isEmpty;

  /// Returns the server's message on failure, or null on success.
  Future<String?> uploadDoc({required String kind, required String path, required String name}) async {
    if (uploadingKind.isNotEmpty) return null;
    uploadingKind = kind;
    notifyListeners();
    try {
      final doc = await dashboard.uploadVerificationDocument(kind: kind, filePath: path, fileName: name);
      docs = {...docs, kind: doc};
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      uploadingKind = '';
      notifyListeners();
    }
  }

  Future<void> continueVerification() => _guarded(() async {
        await dashboard.saveProfile({'barCouncil': barCouncil.text.trim()});
        _step = 1;
      });

  // ── Step 2: specializations ──────────────────────────────────────────────

  bool get canContinueAreas => areas.isNotEmpty;

  /// The plan the lawyer is on right now — what their choices are held to. Null
  /// if the plans could not be read, in which case the server is left to refuse.
  MembershipPlan? get currentPlan => catalog?.currentPlan;

  /// Ticks or unticks a practice area. Unticking always works; ticking past what
  /// the current plan covers is refused with [PickResult.needsUpgrade], and the
  /// screen opens the plans (see [areaUpgradeReason]) and tries again once paid.
  PickResult toggleArea(LegalService service) {
    if (areas.contains(service.name)) {
      areas.remove(service.name);
      matters.removeWhere((m) => service.subServices.any((s) => s.name == m));
      notifyListeners();
      return PickResult.ok;
    }
    final plan = currentPlan;
    if (plan != null && !plan.allowsAreas(areas.length + 1)) return PickResult.needsUpgrade;
    areas.add(service.name);
    notifyListeners();
    return PickResult.ok;
  }

  PickResult toggleMatter(String matter) {
    if (matters.remove(matter)) {
      notifyListeners();
      return PickResult.ok;
    }
    final plan = currentPlan;
    if (plan != null && !plan.allowsMatters(matters.length + 1)) return PickResult.needsUpgrade;
    matters.add(matter);
    notifyListeners();
    return PickResult.ok;
  }

  String areaUpgradeReason(String name) => currentPlan?.areasReason(name) ?? '';
  String matterUpgradeReason(String name) => currentPlan?.mattersReason(name) ?? '';
  String cityUpgradeReason(String name) => currentPlan?.citiesReason(name) ?? '';

  int mattersIn(LegalService service) =>
      matters.where((m) => service.subServices.any((s) => s.name == m)).length;

  /// Saves the areas and matters, then moves on. The server holds the same plan
  /// limits, so a choice that got past the screen and not the plan is refused
  /// here with the server's own sentence.
  Future<void> continueAreas() => _guarded(() async {
        await dashboard.saveProfile({'services': areas, 'subServices': matters});
        _step = 2;
      });

  // ── Step 3: profile and cities ───────────────────────────────────────────

  int? get experienceYears => int.tryParse(experience.text.trim());

  bool get canContinueProfile {
    final years = experienceYears;
    return fullName.text.trim().length >= 2 &&
        Validators.isEmail(email.text) &&
        title.text.trim().length >= 2 &&
        years != null &&
        years >= 0 &&
        years <= 70 &&
        Validators.isPincode(pincode.text) &&
        baseCity.isNotEmpty &&
        !lookingUp;
  }

  void setPhoto(Uint8List bytes) {
    photoBytes = bytes;
    photoDataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    notifyListeners();
  }

  /// Adds or removes an extra city (the base city is always included). Adding
  /// past the plan's allowance is refused with [PickResult.needsUpgrade].
  PickResult toggleCity(String city) {
    if (_isBase(city)) return PickResult.ok;
    if (cities.remove(city)) {
      notifyListeners();
      return PickResult.ok;
    }
    final plan = currentPlan;
    if (plan != null && !plan.allowsCities(cities.length + 1)) return PickResult.needsUpgrade;
    cities.add(city);
    notifyListeners();
    return PickResult.ok;
  }

  Future<void> continueProfile() => _guarded(() async {
        await dashboard.saveProfile({
          'fullName': fullName.text.trim(),
          'email': email.text.trim(),
          'tagline': title.text.trim(),
          'experience': experienceYears,
          'pincode': pincode.text.trim(),
          'city': baseCity,
          if (state.isNotEmpty) 'state': state,
          'practiceCities': cities,
          if (photoDataUrl != null) 'photo': photoDataUrl,
        });
        _step = 3;
      });

  // ── Step 4: consultations ────────────────────────────────────────────────

  void setOffersChat(bool on) => _setOffer(() => offersChat = on, on ? null : chatRate);
  void setOffersAudio(bool on) => _setOffer(() => offersAudio = on, on ? null : audioRate);
  void setOffersVideo(bool on) => _setOffer(() => offersVideo = on, on ? null : videoRate);
  void setOffersInPerson(bool on) => _setOffer(() => offersInPerson = on, on ? null : inPersonFee);

  void _setOffer(VoidCallback apply, TextEditingController? clear) {
    apply();
    clear?.clear();
    notifyListeners();
  }

  int _amount(TextEditingController field) => int.tryParse(field.text.trim()) ?? 0;

  /// A per-minute rate has to be within the range the server accepts; the
  /// in-person fee is a whole visit, so it only has to be more than nothing.
  bool _rateOk(bool offered, TextEditingController field) {
    if (!offered) return true;
    final n = _amount(field);
    return n >= Validators.minRate && n <= Validators.maxRate;
  }

  bool get canContinueConsultations =>
      (offersChat || offersAudio || offersVideo || offersInPerson) &&
      _rateOk(offersChat, chatRate) &&
      _rateOk(offersAudio, audioRate) &&
      _rateOk(offersVideo, videoRate) &&
      (!offersInPerson || _amount(inPersonFee) > 0);

  Future<void> continueConsultations() => _guarded(() async {
        await dashboard.saveProfile({
          'chatRate': offersChat ? '${_amount(chatRate)}' : '0',
          'audioRate': offersAudio ? '${_amount(audioRate)}' : '0',
          'videoRate': offersVideo ? '${_amount(videoRate)}' : '0',
          'fee': offersInPerson ? '${_amount(inPersonFee)}' : '0',
        });
        _step = 4;
      });

  // ── Step 5: earnings ─────────────────────────────────────────────────────

  bool get canContinueEarnings =>
      savedAccount != null ||
      (holder.text.trim().length >= 3 &&
          bankName.text.trim().length >= 2 &&
          Validators.isAccountNumber(accountNumber.text) &&
          Validators.isIfsc(ifsc.text) &&
          Validators.isPan(pan.text));

  Future<void> continueEarnings() => _guarded(() async {
        savedAccount ??= await dashboard.addBankAccount(
          holderName: holder.text.trim(),
          bankName: bankName.text.trim(),
          accountNumber: accountNumber.text.replaceAll(RegExp(r'\s+'), ''),
          ifsc: ifsc.text.trim().toUpperCase(),
          pan: pan.text.trim().toUpperCase(),
        );
        _step = 5;
      });

  void skipEarnings() => _go(5);

  // ── Step 6: plan ─────────────────────────────────────────────────────────

  MembershipPlan? get selectedPlan {
    final c = catalog;
    if (c == null) return null;
    for (final p in c.plans) {
      if (p.id == selectedPlanId) return p;
    }
    return null;
  }

  void selectPlan(String id) {
    selectedPlanId = id;
    error = '';
    notice = '';
    notifyListeners();
  }

  PlanFit fitOf(MembershipPlan plan) =>
      planFit(plan, areas: areas.length, matters: matters.length, cities: cities.length);

  String describeFitOf(MembershipPlan plan) =>
      describePlanFit(plan, areas: areas.length, matters: matters.length, cities: cities.length);

  /// Confirms the plan: pays for it if it is a paid one, then saves the practice
  /// areas, matters and cities the lawyer picked and finishes onboarding.
  Future<void> confirmPlan() async {
    final plan = selectedPlan;
    final cat = catalog;
    if (plan == null || cat == null || stage != OnboardingStage.idle) return;

    if (!fitOf(plan).fits) {
      error = '${plan.name} ${describeFitOf(plan).toLowerCase()}. '
          'Choose a bigger plan, or go back and trim your choices.';
      notifyListeners();
      return;
    }

    error = '';
    notice = '';

    if (!plan.isFree && plan.id != cat.currentPlanId) {
      // A payment that went through but had not been confirmed may have landed
      // since — look before asking for money a second time.
      if (_paidAwaitingActivation) await _refreshCatalog();
      if (catalog?.currentPlanId != plan.id) {
        stage = OnboardingStage.paying;
        notifyListeners();
        final result = await _checkout.buy(plan.id, planLabel: plan.name);
        switch (result.outcome) {
          case PlanPurchaseOutcome.success:
            _paidAwaitingActivation = false;
            await _refreshCatalog();
            try {
              await refreshAuth();
            } catch (_) {
              // The plan is bought; a stale header is not worth stopping for.
            }
          case PlanPurchaseOutcome.pending:
            _paidAwaitingActivation = true;
            error = '${result.message} Tap the button again in a moment to continue.';
            stage = OnboardingStage.idle;
            notifyListeners();
            return;
          case PlanPurchaseOutcome.cancelled:
            notice = 'Payment cancelled. You can try again, or pick another plan.';
            stage = OnboardingStage.idle;
            notifyListeners();
            return;
          case PlanPurchaseOutcome.failed:
            error = result.message;
            stage = OnboardingStage.idle;
            notifyListeners();
            return;
        }
      }
    }

    await _finishSetup();
  }

  Future<void> _refreshCatalog() async {
    try {
      catalog = await membership.catalog();
    } on ApiException {
      // Keep the last read.
    }
  }

  /// Everything was saved as its step was completed, so all that is left is to
  /// mark onboarding finished. The short "saving" stage is the progress screen's
  /// pause before the success screen, not a network call.
  Future<void> _finishSetup() async {
    stage = OnboardingStage.saving;
    notifyListeners();
    try {
      await onCompleted();
      stage = OnboardingStage.done;
    } catch (_) {
      error = 'Something went wrong. Please try again.';
      stage = OnboardingStage.idle;
    }
    notifyListeners();
  }

  /// "Later": leave the flow now and finish from the profile.
  Future<void> skipAll() => onCompleted();

  // ── Plumbing ─────────────────────────────────────────────────────────────

  Future<void> _guarded(Future<void> Function() body) async {
    if (saving) return;
    saving = true;
    error = '';
    notice = '';
    notifyListeners();
    try {
      await body();
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Something went wrong. Please try again.';
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}

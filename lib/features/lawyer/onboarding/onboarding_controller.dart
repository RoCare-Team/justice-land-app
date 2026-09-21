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

/// The state behind the five onboarding steps.
///
///   1 Verification    2 Specializations    3 Profile    4 Earnings    5 Plan
///
/// Steps 1, 3 and 4 save to the server when the lawyer continues. Step 2 does
/// not: the practice areas, matters and cities are held here and saved at the end,
/// once the plan is settled. The server refuses a save that is over the plan's
/// limit, so saving them earlier would stop a Starter lawyer on their third
/// choice — the flow instead lets them pick freely and reconciles the choices
/// with the plan on the last step, where an upgrade is one tap away.
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

  static const int stepCount = 5;
  static const int maxAreas = 6;
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
  final title = TextEditingController();
  final experience = TextEditingController();
  final pincode = TextEditingController();
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
    fullName.text = a?.name ?? '';
    title.text = a?.tagline ?? '';
    if ((a?.experience ?? 0) > 0) experience.text = '${a!.experience}';
    pincode.text = a?.office.pincode ?? '';
    baseCity = (a?.city ?? '').trim();
    state = (a?.state ?? '').trim();
    areas.addAll((a?.specializations ?? const <String>[]).take(maxAreas));
    matters.addAll(a?.subSpecializations ?? const <String>[]);
    cities.addAll((a?.practiceCities ?? const <String>[]).where((c) => !_isBase(c)));
    existingPhoto = a?.photo ?? '';

    if (Validators.isPincode(pincode.text) && baseCity.isNotEmpty) {
      _lookedUp = pincode.text.trim();
      pincodeOk = true;
      pincodeNote = state.isEmpty ? baseCity : '$baseCity, $state';
    }

    _fields = [barCouncil, fullName, title, experience, pincode, holder, bankName, accountNumber, ifsc, pan];
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

  Future<void> reloadPlans() async {
    try {
      catalog = await membership.catalog();
      if (selectedPlan == null) _pickDefaultPlan();
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

  bool get canContinueAreas => areas.isNotEmpty && areas.length <= maxAreas;

  /// False when the six-area limit stopped it.
  bool toggleArea(LegalService service) {
    if (areas.contains(service.name)) {
      areas.remove(service.name);
      matters.removeWhere((m) => service.subServices.any((s) => s.name == m));
      notifyListeners();
      return true;
    }
    if (areas.length >= maxAreas) return false;
    areas.add(service.name);
    notifyListeners();
    return true;
  }

  void toggleMatter(String matter) {
    if (!matters.remove(matter)) matters.add(matter);
    notifyListeners();
  }

  int mattersIn(LegalService service) =>
      matters.where((m) => service.subServices.any((s) => s.name == m)).length;

  void continueAreas() => _go(2);

  // ── Step 3: profile and cities ───────────────────────────────────────────

  int? get experienceYears => int.tryParse(experience.text.trim());

  bool get canContinueProfile {
    final years = experienceYears;
    return fullName.text.trim().length >= 2 &&
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

  void toggleCity(String city) {
    if (_isBase(city)) return;
    if (!cities.remove(city)) cities.add(city);
    notifyListeners();
  }

  /// One-tap suggestions: the first cities the directory lists, minus the
  /// lawyer's own and any already chosen.
  List<String> get popularCities => [
        for (final c in cityOptions)
          if (!_isBase(c.name) && !cities.contains(c.name)) c.name,
      ].take(12).toList();

  List<String> searchCities(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final c in cityOptions)
        if (c.name.toLowerCase().contains(q) && !_isBase(c.name) && !cities.contains(c.name)) c.name,
    ].take(8).toList();
  }

  Future<void> continueProfile() => _guarded(() async {
        await dashboard.saveProfile({
          'fullName': fullName.text.trim(),
          'tagline': title.text.trim(),
          'experience': experienceYears,
          'pincode': pincode.text.trim(),
          'city': baseCity,
          if (state.isNotEmpty) 'state': state,
          if (photoDataUrl != null) 'photo': photoDataUrl,
        });
        _step = 3;
      });

  // ── Step 4: earnings ─────────────────────────────────────────────────────

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
        _step = 4;
      });

  void skipEarnings() => _go(4);

  // ── Step 5: plan ─────────────────────────────────────────────────────────

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

  Future<void> _finishSetup() async {
    stage = OnboardingStage.saving;
    notifyListeners();
    try {
      await dashboard.saveProfile({
        'services': areas,
        'subServices': matters,
        'practiceCities': cities,
      });
      await onCompleted();
      stage = OnboardingStage.done;
    } on ApiException catch (e) {
      error = e.message;
      stage = OnboardingStage.idle;
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

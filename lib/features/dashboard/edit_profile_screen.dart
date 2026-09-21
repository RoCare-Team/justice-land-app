import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/config/reference_data.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/account.dart';
import '../../models/advocate.dart';
import '../../models/legal_query.dart';
import '../../services/content_service.dart';
import '../../services/dashboard_service.dart';
import '../../services/membership_service.dart';
import '../../state/auth_controller.dart';
import '../lawyer/city_picker.dart';
import '../lawyer/plan_upgrade_sheet.dart';

/// Editing the lawyer's own profile.
///
/// The save sends only the fields this screen actually shows. The API writes
/// what it is given and leaves the rest alone, so a partial payload cannot
/// blank out sections the screen never displayed — which is exactly what a
/// full-object PUT built from a half-loaded model would do.
///
/// Practice areas, matters and cities are drawn from the same lists the
/// onboarding uses, so whatever was chosen there shows as chosen here. Ticking
/// past the plan opens the plans, the way it does in the onboarding.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  Advocate? _advocate;
  bool _loading = true;
  bool _saving = false;
  ApiException? _error;
  String _photo = '';

  final _fullName = TextEditingController();
  final _tagline = TextEditingController();
  final _about = TextEditingController();
  final _experience = TextEditingController();
  final _barCouncil = TextEditingController();
  final _officeName = TextEditingController();
  final _officeAddress = TextEditingController();
  final _pincode = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();
  final _fee = TextEditingController();
  final _chatRate = TextEditingController();
  final _audioRate = TextEditingController();
  final _videoRate = TextEditingController();

  String _state = '';
  String _city = '';
  final List<String> _languages = [];
  final List<String> _courts = [];
  final List<String> _services = [];
  final List<String> _matters = [];
  final List<String> _practiceCities = [];

  /// What can be ticked: the directory's practice areas (each with its matters)
  /// and cities. Empty until read; a saved choice is shown either way.
  List<LegalService> _serviceOptions = [];
  List<String> _cityOptions = [];
  PlanCatalog? _plans;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in [
      _fullName, _tagline, _about, _experience, _barCouncil,
      _officeName, _officeAddress, _pincode, _phone, _whatsapp, _email,
      _fee, _chatRate, _audioRate, _videoRate,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final advocate = await context.read<DashboardService>().profile();
      if (!mounted) return;
      final content = context.read<ContentService>();
      final membership = context.read<MembershipService>();
      // The lists and the plan are what the chips are drawn from and held to;
      // a failed read leaves the saved choices showing and the server to decide.
      var services = <LegalService>[];
      var cities = <String>[];
      PlanCatalog? plans;
      try {
        services = await content.services();
      } on ApiException {
        // Falls back to the saved choices below.
      }
      try {
        cities = [for (final c in await content.cities()) c.name];
      } on ApiException {
        // Same.
      }
      try {
        plans = await membership.catalog();
      } on ApiException {
        // Same.
      }
      if (!mounted) return;
      setState(() {
        _serviceOptions = services;
        _cityOptions = cities;
        _plans = plans;
        _advocate = advocate;
        _photo = advocate.photo;
        _fullName.text = advocate.name;
        _tagline.text = advocate.tagline;
        _about.text = advocate.about;
        _experience.text = advocate.experience > 0 ? '${advocate.experience}' : '';
        _barCouncil.text = advocate.barCouncilNumber;
        _officeName.text = advocate.office.name;
        _officeAddress.text = advocate.office.address;
        _pincode.text = advocate.office.pincode;
        _phone.text = advocate.contact.phone;
        _whatsapp.text = advocate.contact.whatsapp;
        _email.text = advocate.contact.email;
        _fee.text = advocate.consultationFee > 0 ? '${advocate.consultationFee}' : '';
        _chatRate.text = advocate.chatRate > 0 ? '${advocate.chatRate}' : '';
        _audioRate.text = advocate.audioRate > 0 ? '${advocate.audioRate}' : '';
        _videoRate.text = advocate.videoRate > 0 ? '${advocate.videoRate}' : '';
        _state = advocate.state;
        _city = advocate.city;
        _languages
          ..clear()
          ..addAll(advocate.languages);
        _courts
          ..clear()
          ..addAll(advocate.courts);
        _services
          ..clear()
          ..addAll(advocate.specializations);
        _matters
          ..clear()
          ..addAll(advocate.subSpecializations);
        _practiceCities
          ..clear()
          ..addAll(advocate.practiceCities);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (file == null) return;

    setState(() => _saving = true);
    try {
      final url = await context.read<DashboardService>().uploadImage(file.path);
      if (!mounted) return;
      setState(() {
        _photo = url;
        _saving = false;
      });
      Toast.success(context, 'Photo uploaded. Save to apply it.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      Toast.error(context, e.message);
    }
  }

  // ── Practice areas, matters and cities, held to the plan ────────────────

  MembershipPlan? get _plan => _plans?.currentPlan;

  bool _sameCity(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

  /// Other cities chosen — the lawyer's own is never counted against the plan.
  int get _extraCities => _practiceCities.where((c) => _city.isEmpty || !_sameCity(c, _city)).length;

  /// True when the current plan covers the choice; otherwise opens the plans
  /// over the form, and once one is bought lifts the limit and checks again.
  /// The form stays exactly as it is while the lawyer pays.
  Future<bool> _room(bool Function(MembershipPlan) allows, String Function(MembershipPlan) reason) async {
    final catalog = _plans;
    var plan = catalog?.currentPlan;
    if (catalog == null || plan == null || allows(plan)) return true;

    final upgraded = await PlanUpgradeSheet.open(context, catalog: catalog, reason: reason(plan));
    if (!upgraded || !mounted) return false;

    try {
      final fresh = await context.read<MembershipService>().catalog();
      if (!mounted) return false;
      setState(() => _plans = fresh);
      plan = fresh.currentPlan;
    } on ApiException {
      // Bought, but the plans could not be re-read: let it through and the
      // server, which knows the new plan, has the last word on save.
      return true;
    }
    if (plan != null && !allows(plan)) {
      Toast.error(context, reason(plan));
      return false;
    }
    return true;
  }

  Future<void> _toggleArea(String name) async {
    if (_services.contains(name)) {
      setState(() {
        _services.remove(name);
        // Its matters go with it, so none is left listed under an area the
        // lawyer no longer practises.
        for (final s in _serviceOptions.where((s) => s.name == name)) {
          _matters.removeWhere((m) => s.subServices.any((x) => x.name == m));
        }
      });
      return;
    }
    if (!await _room((p) => p.allowsAreas(_services.length + 1), (p) => p.areasReason(name))) return;
    if (mounted) setState(() => _services.add(name));
  }

  Future<void> _toggleMatter(String name) async {
    if (_matters.contains(name)) {
      setState(() => _matters.remove(name));
      return;
    }
    if (!await _room((p) => p.allowsMatters(_matters.length + 1), (p) => p.mattersReason(name))) return;
    if (mounted) setState(() => _matters.add(name));
  }

  Future<void> _addCity(String name) async {
    if (_practiceCities.contains(name)) return;
    if (!await _room((p) => p.allowsCities(_extraCities + 1), (p) => p.citiesReason(name))) return;
    if (mounted) setState(() => _practiceCities.add(name));
  }

  /// "2 of 2 on your Starter plan" — what has been chosen against what the plan
  /// covers, or null while the plan is unknown.
  String? _usage(int used, int? limit) {
    final plan = _plan;
    if (plan == null) return null;
    return limit == null
        ? '$used chosen · no limit on your ${plan.name} plan'
        : '$used of $limit on your ${plan.name} plan';
  }

  Future<void> _save() async {
    // Rates are optional, but one that was typed has to be usable — the same
    // bound the server enforces.
    for (final entry in {
      'Live chat': _chatRate,
      'Audio call': _audioRate,
      'Video call': _videoRate,
    }.entries) {
      final error = Validators.optionalRate(entry.value.text);
      if (error != null) {
        Toast.error(context, '${entry.key}: $error');
        return;
      }
    }
    if (_about.text.trim().isNotEmpty && _about.text.trim().length < 40) {
      Toast.error(context, 'About should be at least 40 characters.');
      return;
    }

    setState(() => _saving = true);
    try {
      // Field names are the API's, not the model's.
      final updated = await context.read<DashboardService>().saveProfile({
        'fullName': _fullName.text.trim(),
        'photo': _photo,
        'tagline': _tagline.text.trim(),
        'about': _about.text.trim(),
        'experience': _experience.text.trim(),
        'barCouncil': _barCouncil.text.trim(),
        'city': _city,
        'state': _state,
        'languages': _languages,
        'courts': _courts,
        'services': _services,
        'subServices': _matters,
        'practiceCities': _practiceCities,
        'officeName': _officeName.text.trim(),
        'officeAddress': _officeAddress.text.trim(),
        'pincode': _pincode.text.trim(),
        'phone': _phone.text.trim(),
        'whatsapp': _whatsapp.text.trim(),
        'email': _email.text.trim(),
        'fee': _fee.text.trim(),
        'chatRate': _chatRate.text.trim(),
        'audioRate': _audioRate.text.trim(),
        'videoRate': _videoRate.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _advocate = updated;
        _saving = false;
      });
      await context.read<AuthController>().refresh();
      if (!mounted) return;
      Toast.success(context, 'Profile saved.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      Toast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: const LoadingView(label: 'Loading your profile…'),
      );
    }

    final error = _error;
    if (error != null && _advocate == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: ErrorView(
          message: error.message,
          isNetwork: error.isNetwork,
          onRetry: _load,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Center(
            child: Stack(
              children: [
                Avatar(name: _fullName.text, photo: _photo, size: 92),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: AppColors.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _saving ? null : _pickPhoto,
                      child: const Padding(
                        padding: EdgeInsets.all(7),
                        child: Icon(Icons.camera_alt_rounded,
                            size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SectionCard(
            title: 'Basics',
            icon: Icons.person_outline_rounded,
            child: Column(
              children: [
                _field(_fullName, 'Full name'),
                _field(_tagline, 'Tagline', help: 'One line under your name.'),
                _field(_experience, 'Years of experience', digitsOnly: true),
                _field(_barCouncil, 'Bar Council number'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Location',
            icon: Icons.location_on_outlined,
            child: Column(
              children: [
                // Both of these pass the saved value through `_optionOr`.
                // A Dropdown asserts if its value is not among its items, and
                // these lists come from a fixed reference file while the saved
                // value came from the server — a lawyer whose city was typed
                // before it was on the list, or who has a state the list spells
                // differently, would otherwise crash this screen the moment it
                // opened, with no way back into their own profile.
                DropdownButtonFormField<String>(
                  value: _optionOr(_state, RefData.states),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'State'),
                  items: [
                    for (final s in RefData.states)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: (v) => setState(() {
                    _state = v ?? '';
                    _city = '';
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _optionOr(_city, RefData.citiesIn(_state)),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'City'),
                  items: [
                    for (final c in RefData.citiesIn(_state))
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() => _city = v ?? ''),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Rates',
            subtitle: 'Blank means you do not offer that channel.',
            icon: Icons.payments_outlined,
            child: Column(
              children: [
                _field(_chatRate, 'Live chat (₹/min)', digitsOnly: true),
                _field(_audioRate, 'Audio call (₹/min)', digitsOnly: true),
                _field(_videoRate, 'Video call (₹/min)', digitsOnly: true),
                _field(_fee, 'In-person fee (₹)', digitsOnly: true),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Office & contact',
            icon: Icons.business_outlined,
            child: Column(
              children: [
                _field(_officeName, 'Office name'),
                _field(_officeAddress, 'Office address', lines: 3),
                _field(_pincode, 'PIN code', digitsOnly: true, maxLength: 6),
                _field(_phone, 'Phone', keyboard: TextInputType.phone),
                _field(_whatsapp, 'WhatsApp', keyboard: TextInputType.phone),
                _field(_email, 'Email', keyboard: TextInputType.emailAddress),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Practice areas',
            subtitle: _usage(_services.length, _plan?.areas),
            icon: Icons.gavel_rounded,
            child: ChipWrap(
              children: [
                for (final name in _areaNames)
                  SelectableChip(
                    label: name,
                    selected: _services.contains(name),
                    onTap: () => _toggleArea(name),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _mattersCard(),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Courts',
            icon: Icons.account_balance_rounded,
            child: ChipWrap(
              children: [
                for (final c in RefData.courts)
                  SelectableChip(
                    label: c,
                    selected: _courts.contains(c),
                    onTap: () => setState(
                        () => _courts.contains(c) ? _courts.remove(c) : _courts.add(c)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Languages',
            icon: Icons.translate_rounded,
            child: ChipWrap(
              children: [
                for (final l in RefData.languages)
                  SelectableChip(
                    label: l,
                    selected: _languages.contains(l),
                    onTap: () => setState(() => _languages.contains(l)
                        ? _languages.remove(l)
                        : _languages.add(l)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Cities you work in',
            subtitle: _usage(_extraCities, _plan?.cities) ??
                'Besides your base city — clients searching those cities find you.',
            icon: Icons.location_city_rounded,
            child: CityPicker(
              options: _cityOptions,
              selected: _practiceCities,
              baseCity: _city,
              onAdd: _addCity,
              onRemove: (city) => setState(() => _practiceCities.remove(city)),
            ),
          ),
          const SizedBox(height: 12),
          // Last, after everything that can be ticked: it is the one field a
          // lawyer writes rather than picks.
          SectionCard(
            title: 'About',
            icon: Icons.notes_rounded,
            child: _field(
              _about,
              'About',
              lines: 5,
              help: 'At least 40 characters. The first thing a client reads.',
            ),
          ),
          const SizedBox(height: 22),
          PrimaryButton(
            label: 'Save changes',
            busy: _saving,
            icon: Icons.save_rounded,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  /// The directory's practice areas, then any the lawyer has saved that it does
  /// not list, so nothing they chose can go missing from the screen.
  List<String> get _areaNames => [
        for (final s in _serviceOptions) s.name,
        for (final s in _services)
          if (!_serviceOptions.any((o) => o.name == s)) s,
      ];

  /// The matters under each chosen practice area, as chips. A saved matter that
  /// sits under no listed area is shown last, so it can still be removed.
  Widget _mattersCard() {
    final chosen = [
      for (final s in _serviceOptions)
        if (_services.contains(s.name) && s.subServices.isNotEmpty) s,
    ];
    final known = {for (final s in _serviceOptions) for (final m in s.subServices) m.name};
    final other = [for (final m in _matters) if (!known.contains(m)) m];

    return SectionCard(
      title: 'Matters',
      subtitle: _usage(_matters.length, _plan?.matters),
      icon: Icons.list_alt_rounded,
      child: chosen.isEmpty && other.isEmpty
          ? Text(
              _services.isEmpty
                  ? 'Choose a practice area above to pick the matters you handle in it.'
                  : 'No matters are listed under your practice areas.',
              style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < chosen.length; i++) ...[
                  if (i > 0) const SizedBox(height: 18),
                  Text(chosen[i].name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ChipWrap(
                    children: [
                      for (final m in chosen[i].subServices)
                        SelectableChip(
                          label: m.name,
                          selected: _matters.contains(m.name),
                          onTap: () => _toggleMatter(m.name),
                        ),
                    ],
                  ),
                ],
                if (other.isNotEmpty) ...[
                  if (chosen.isNotEmpty) const SizedBox(height: 18),
                  const Text('Other', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ChipWrap(
                    children: [
                      for (final m in other) SelectableChip(label: m, selected: true, onTap: () => _toggleMatter(m)),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  /// [value] when the dropdown actually has an item for it, else null.
  ///
  /// Null shows the label as a hint and leaves the field empty, which is the
  /// honest thing: we are not going to silently replace what the lawyer saved
  /// with a value they did not choose, and we cannot display one that is not
  /// on the list.
  String? _optionOr(String value, List<String> options) =>
      options.contains(value) ? value : null;

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
    bool digitsOnly = false,
    int? maxLength,
    String? help,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: lines,
        maxLength: maxLength,
        keyboardType: keyboard ?? (digitsOnly ? TextInputType.number : null),
        inputFormatters: digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: help,
          counterText: '',
        ),
      ),
    );
  }
}

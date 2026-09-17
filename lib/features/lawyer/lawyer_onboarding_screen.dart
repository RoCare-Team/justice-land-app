import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/account.dart';
import '../../models/legal_query.dart';
import '../../services/content_service.dart';
import '../../services/dashboard_service.dart';
import '../../services/membership_service.dart';
import '../../state/auth_controller.dart';
import 'plan_upgrade_sheet.dart';

const int _maxBytes = 5 * 1024 * 1024;

const List<({String kind, String title, IconData icon})> _docKinds = [
  (kind: 'bar_council_certificate', title: 'Bar Council Certificate', icon: Icons.description_outlined),
  (kind: 'government_id', title: 'Government ID Proof', icon: Icons.badge_outlined),
];

/// A new lawyer's setup after Basic Details, in the app's own look:
///
///   1. Basic Details            — done at signup
///   2. Verification             — Bar Council ID, certificate, government ID
///   3. Practice                 — the website's "Legal Services" section:
///                                 practice areas, the matters under each,
///                                 the cities they work in, in-person fee
///
/// Limits are the plan's, as on the website — Starter covers 2 practice areas,
/// 4 matters and 2 other cities. A choice past that opens the plans; paying
/// there lifts the limit and the choice goes through.
class LawyerOnboardingScreen extends StatefulWidget {
  const LawyerOnboardingScreen({super.key});

  @override
  State<LawyerOnboardingScreen> createState() => _LawyerOnboardingScreenState();
}

class _LawyerOnboardingScreenState extends State<LawyerOnboardingScreen> {
  int _step = 0; // 0 = verification, 1 = practice

  // Verification
  final _barCouncil = TextEditingController();
  Map<String, VerificationDocument> _docs = {};
  String _uploading = '';

  // Practice
  List<LegalService> _services = [];
  List<String> _cityOptions = [];
  PlanCatalog? _catalog;
  final List<String> _areas = [];
  final List<String> _matters = [];
  final List<String> _cities = [];
  final _citySearch = TextEditingController();
  String _baseCity = '';
  bool? _inPerson;
  final _fee = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final a = context.read<AuthController>().advocate;
    _barCouncil.text = a?.barCouncilNumber ?? '';
    _areas.addAll(a?.specializations ?? const []);
    _matters.addAll(a?.subSpecializations ?? const []);
    _baseCity = (a?.city ?? '').trim();
    _cities.addAll((a?.practiceCities ?? const []).where((c) => !_isBase(c)));
    if ((a?.consultationFee ?? 0) > 0) {
      _inPerson = true;
      _fee.text = '${a!.consultationFee}';
    }
    for (final c in [_barCouncil, _fee, _citySearch]) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  @override
  void dispose() {
    _barCouncil.dispose();
    _fee.dispose();
    _citySearch.dispose();
    super.dispose();
  }

  bool _isBase(String city) => city.trim().toLowerCase() == _baseCity.toLowerCase();

  Future<void> _load() async {
    final dashboard = context.read<DashboardService>();
    final content = context.read<ContentService>();
    final membership = context.read<MembershipService>();
    try {
      final docs = await dashboard.verificationDocuments().catchError((_) => <String, VerificationDocument>{});
      final services = await content.services();
      final cities = await content.cities().catchError((_) => <City>[]);
      final catalog = await membership.catalog();
      if (!mounted) return;
      setState(() {
        _docs = docs;
        _services = services;
        _cityOptions = cities.map((c) => c.name).where((n) => !_isBase(n)).toList();
        _catalog = catalog;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  // ── Plan ─────────────────────────────────────────────────────────────────

  MembershipPlan? get _plan {
    final c = _catalog;
    if (c == null) return null;
    for (final p in c.plans) {
      if (p.id == c.currentPlanId) return p;
    }
    return c.plans.isEmpty ? null : c.plans.first;
  }

  /// Opens the plans. On a successful upgrade re-reads the limits and runs
  /// [andThen], so the choice that was refused goes through.
  Future<void> _upgradeFor(String reason, VoidCallback andThen) async {
    final catalog = _catalog;
    if (catalog == null) return;
    final upgraded = await PlanUpgradeSheet.open(context, catalog: catalog, reason: reason);
    if (!upgraded || !mounted) return;
    try {
      final fresh = await context.read<MembershipService>().catalog();
      if (!mounted) return;
      setState(() => _catalog = fresh);
      andThen();
    } on ApiException {
      // The sheet already said the plan is on its way.
    }
  }

  String _limitText(int used, int? limit, String noun, String plural) {
    final plan = _plan;
    if (plan == null) return '';
    if (limit == null) return '$used ${used == 1 ? noun : plural} — no limit on your ${plan.name} plan';
    return '$used of $limit ${limit == 1 ? noun : plural} used on your ${plan.name} plan';
  }

  void _toggleArea(LegalService area) {
    if (_areas.contains(area.name)) {
      setState(() {
        _areas.remove(area.name);
        _matters.removeWhere((m) => area.subServices.any((s) => s.name == m));
      });
      return;
    }
    final plan = _plan;
    void add() => setState(() => _areas.add(area.name));
    if (plan != null && !plan.allowsAreas(_areas.length + 1)) {
      _upgradeFor(
        '“${area.name}” needs a bigger plan. ${plan.name} covers ${plan.areas} practice '
        '${plan.areas == 1 ? 'area' : 'areas'}, and you have used them all.',
        add,
      );
      return;
    }
    add();
  }

  void _toggleMatter(String matter) {
    if (_matters.contains(matter)) {
      setState(() => _matters.remove(matter));
      return;
    }
    final plan = _plan;
    void add() => setState(() => _matters.add(matter));
    if (plan != null && !plan.allowsMatters(_matters.length + 1)) {
      _upgradeFor(
        '“$matter” needs a bigger plan. ${plan.name} covers ${plan.matters} '
        '${plan.matters == 1 ? 'matter' : 'matters'}, and you have used them all.',
        add,
      );
      return;
    }
    add();
  }

  void _toggleCity(String city) {
    if (_cities.contains(city)) {
      setState(() => _cities.remove(city));
      return;
    }
    final plan = _plan;
    void add() => setState(() {
          _cities.add(city);
          _citySearch.clear();
        });
    if (plan != null && !plan.allowsCities(_cities.length + 1)) {
      _upgradeFor(
        '“$city” needs a bigger plan. ${plan.name} covers ${plan.cities} other '
        '${plan.cities == 1 ? 'city' : 'cities'}, and you have used them all.',
        add,
      );
      return;
    }
    add();
  }

  // ── Documents ────────────────────────────────────────────────────────────

  Future<void> _pick(String kind) async {
    if (_uploading.isNotEmpty) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final file = picked?.files.single;
    if (file == null || file.path == null || !mounted) return;
    if (file.size > _maxBytes) {
      Toast.error(context, 'That file is over 5 MB. Please choose a smaller one.');
      return;
    }
    setState(() => _uploading = kind);
    try {
      final doc = await context.read<DashboardService>().uploadVerificationDocument(
            kind: kind,
            filePath: file.path!,
            fileName: file.name,
          );
      if (mounted) setState(() => _docs = {..._docs, kind: doc});
    } on ApiException catch (e) {
      if (mounted) Toast.error(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = '');
    }
  }

  // ── Steps ────────────────────────────────────────────────────────────────

  int get _feeValue => int.tryParse(_fee.text.trim()) ?? 0;

  bool get _canContinue => _step == 0
      ? _barCouncil.text.trim().length >= 3 &&
          _docKinds.every((d) => _docs.containsKey(d.kind)) &&
          _uploading.isEmpty
      : _areas.isNotEmpty && (_inPerson == false || (_inPerson == true && _feeValue > 0));

  Future<void> _continue() async {
    setState(() {
      _saving = true;
      _error = '';
    });
    final dashboard = context.read<DashboardService>();
    try {
      if (_step == 0) {
        await dashboard.saveProfile({'barCouncil': _barCouncil.text.trim()});
        if (mounted) setState(() => _step = 1);
      } else {
        await dashboard.saveProfile({
          'services': _areas,
          'subServices': _matters,
          'practiceCities': _cities,
          // 0 means in-person is not offered.
          'fee': _inPerson == true ? '$_feeValue' : '0',
        });
        if (mounted) await _finish('You are all set. We will verify your documents shortly.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finish(String message) async {
    final auth = context.read<AuthController>();
    await auth.setLawyerOnboardingPending(false);
    unawaited(auth.refresh());
    if (!mounted) return;
    Toast.success(context, message);
    context.go('/lawyer');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == 1 && !_saving) setState(() => _step = 0);
      },
      child: Scaffold(
        backgroundColor: AppColors.muted,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: _step == 1
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _saving ? null : () => setState(() => _step = 0),
                )
              : null,
          title: const Text('Complete your profile'),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => _finish('You can finish this any time from your profile.'),
              child: const Text('Later'),
            ),
          ],
        ),
        body: _loading
            ? const LoadingView(label: 'Getting things ready…')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _StepRail(current: _step + 1),
                  const SizedBox(height: 20),
                  Text(
                    _step == 0 ? 'Professional verification' : 'Your practice',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _step == 0
                        ? 'We check these before your profile goes live. They are never shown to clients.'
                        : 'What you practise and where. How many you can list depends on your plan.',
                    style: TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: 16),
                  if (_step == 0) ..._verification() else ..._practice(),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    NoticeBanner(tone: ChipTone.danger, icon: Icons.error_outline_rounded, message: _error),
                  ],
                ],
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: PrimaryButton(
              label: _step == 0 ? 'Continue' : 'Finish setup',
              busy: _saving,
              onPressed: _canContinue && !_loading ? _continue : null,
            ),
          ),
        ),
      ),
    );
  }

  // ── Verification step ────────────────────────────────────────────────────

  List<Widget> _verification() => [
        _Section(
          title: 'Bar Council ID',
          icon: Icons.gavel_rounded,
          children: [
            TextField(
              controller: _barCouncil,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'e.g. D/1234/2015'),
            ),
          ],
        ),
        _Section(
          title: 'Documents',
          icon: Icons.folder_open_rounded,
          subtitle: 'PDF, JPG or PNG, up to 5 MB each.',
          children: [
            for (var i = 0; i < _docKinds.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _docTile(_docKinds[i]),
            ],
          ],
        ),
      ];

  Widget _docTile(({String kind, String title, IconData icon}) d) {
    final doc = _docs[d.kind];
    final busy = _uploading == d.kind;
    return Material(
      color: doc != null ? AppColors.successSoft : AppColors.muted,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: busy ? null : () => _pick(d.kind),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: doc != null ? AppColors.success.withValues(alpha: 0.35) : AppColors.border),
          ),
          child: Row(
            children: [
              Icon(doc != null ? Icons.check_circle_rounded : d.icon, color: doc != null ? AppColors.success : AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      busy ? 'Uploading…' : doc != null ? doc.fileName : 'Not uploaded',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: doc != null ? AppColors.success : AppColors.inkFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                  : Text(
                      doc != null ? 'Replace' : 'Upload',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Practice step ────────────────────────────────────────────────────────

  List<Widget> _practice() {
    final plan = _plan;
    final chosen = _services.where((s) => _areas.contains(s.name) && s.subServices.isNotEmpty).toList();
    final query = _citySearch.text.trim().toLowerCase();
    final cityMatches = query.isEmpty
        ? const <String>[]
        : _cityOptions.where((c) => c.toLowerCase().contains(query) && !_cities.contains(c)).take(8).toList();

    return [
      _Section(
        title: 'Legal services',
        icon: Icons.balance_rounded,
        subtitle: _limitText(_areas.length, plan?.areas, 'practice area', 'practice areas'),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _services)
                SelectableChip(label: s.name, selected: _areas.contains(s.name), onTap: () => _toggleArea(s)),
            ],
          ),
        ],
      ),
      if (chosen.isNotEmpty)
        _Section(
          title: 'Matters you handle (optional)',
          icon: Icons.checklist_rounded,
          subtitle: _limitText(_matters.length, plan?.matters, 'matter', 'matters'),
          children: [
            for (final area in chosen) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  area.name.toUpperCase(),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.primary),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in area.subServices)
                    SelectableChip(label: m.name, selected: _matters.contains(m.name), onTap: () => _toggleMatter(m.name)),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      _Section(
        title: 'Cities you work in',
        icon: Icons.location_city_rounded,
        subtitle: '${_baseCity.isEmpty ? '' : '$_baseCity is included. '}'
            '${_limitText(_cities.length, plan?.cities, 'other city', 'other cities')}',
        children: [
          if (_cities.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _cities) SelectableChip(label: c, selected: true, onTap: () => _toggleCity(c)),
              ],
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _citySearch,
            decoration: const InputDecoration(
              hintText: 'Search a city to add',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
          ),
          if (cityMatches.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in cityMatches) SelectableChip(label: c, selected: false, onTap: () => _toggleCity(c)),
              ],
            ),
          ],
        ],
      ),
      _Section(
        title: 'In-person consultation',
        icon: Icons.meeting_room_outlined,
        subtitle: 'Are you available for physical consultations at your office?',
        children: [
          Row(
            children: [
              Expanded(child: _choice('Yes', true)),
              const SizedBox(width: 10),
              Expanded(child: _choice('No', false)),
            ],
          ),
          if (_inPerson == true) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _fee,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Fee per visit',
                prefixText: '₹ ',
                counterText: '',
                helperText: 'Shown on your profile as the in-person price.',
              ),
            ),
          ],
        ],
      ),
    ];
  }

  Widget _choice(String label, bool value) {
    final selected = _inPerson == value;
    return OutlinedButton(
      onPressed: _saving ? null : () => setState(() => _inPerson = value),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        backgroundColor: selected ? AppColors.primary.withValues(alpha: 0.08) : null,
        foregroundColor: selected ? AppColors.primary : AppColors.inkMuted,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.6 : 1),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

/// Basic details · Verification · Practice — the same rail the signup screen
/// uses, carried on from where it stopped.
class _StepRail extends StatelessWidget {
  const _StepRail({required this.current});

  /// 0-based index of the active step (Basic details is always done here).
  final int current;

  static const _labels = ['Basic details', 'Verification', 'Practice'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          _dot(i),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _labels[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: i <= current ? AppColors.ink.withValues(alpha: 0.8) : AppColors.ink.withValues(alpha: 0.35),
              ),
            ),
          ),
          if (i < _labels.length - 1)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: i < current ? AppColors.success.withValues(alpha: 0.6) : AppColors.ink.withValues(alpha: 0.12),
              ),
            ),
        ],
      ],
    );
  }

  Widget _dot(int i) {
    final done = i < current;
    final active = i == current;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.success : active ? AppColors.primary : AppColors.ink.withValues(alpha: 0.1),
      ),
      child: done
          ? const Icon(Icons.check, size: 13, color: Colors.white)
          : Text(
              '${i + 1}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? Colors.white : AppColors.ink.withValues(alpha: 0.4)),
            ),
    );
  }
}

/// A plain white section with a title — the app's standard form panel.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children, this.subtitle});

  final String title;
  final IconData icon;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.inkMuted)),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

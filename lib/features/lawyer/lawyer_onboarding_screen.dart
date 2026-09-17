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

const Color _blue = Color(0xFF2563EB);
const Color _blueDark = Color(0xFF1D4ED8);
const int _maxBytes = 5 * 1024 * 1024;

/// The two documents asked for, in the order a lawyer has them to hand.
const List<({String kind, String title, IconData icon, Color tint})> _docKinds = [
  (kind: 'bar_council_certificate', title: 'Bar Council Certificate', icon: Icons.description_outlined, tint: Color(0xFF475569)),
  (kind: 'government_id', title: 'Government ID Proof', icon: Icons.badge_outlined, tint: Color(0xFF059669)),
];

/// A new lawyer's setup, straight after Basic Details: the fields an admin
/// needs to verify them, then what they practise.
///
///   1. Basic Details           — name, email, city (already done at signup)
///   2. Professional Verification — Bar Council ID, certificate, government ID
///   3. Practice Areas          — areas, then the matters under each
///
/// Practice areas are chosen the way the website does it: pick an area and
/// its matters open beneath it. A choice the plan does not cover opens the
/// plans right there, as the website's upgrade modal does.
class LawyerOnboardingScreen extends StatefulWidget {
  const LawyerOnboardingScreen({super.key});

  @override
  State<LawyerOnboardingScreen> createState() => _LawyerOnboardingScreenState();
}

class _LawyerOnboardingScreenState extends State<LawyerOnboardingScreen> {
  int _step = 0; // 0 = verification, 1 = practice areas

  final _barCouncil = TextEditingController();
  Map<String, VerificationDocument> _docs = {};
  String _uploading = '';

  List<LegalService> _services = [];
  PlanCatalog? _catalog;
  final Set<String> _areas = {};
  final Set<String> _matters = {};

  /// In-person (physical) consultations: `null` until the lawyer answers.
  /// A "yes" needs a price per visit — the same `consultationFee` the website
  /// shows as "In-Person … /visit" and filters on.
  bool? _inPerson;
  final _fee = TextEditingController();

  int get _feeValue => int.tryParse(_fee.text.trim()) ?? 0;
  bool get _inPersonReady => _inPerson == false || (_inPerson == true && _feeValue > 0);

  bool _loading = true;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final advocate = context.read<AuthController>().advocate;
    _barCouncil.text = advocate?.barCouncilNumber ?? '';
    _areas.addAll(advocate?.specializations ?? const []);
    _matters.addAll(advocate?.subSpecializations ?? const []);
    _barCouncil.addListener(() => setState(() {}));
    final fee = advocate?.consultationFee ?? 0;
    if (fee > 0) {
      _inPerson = true;
      _fee.text = '$fee';
    }
    _fee.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _barCouncil.dispose();
    _fee.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dashboard = context.read<DashboardService>();
    final content = context.read<ContentService>();
    final membership = context.read<MembershipService>();
    try {
      final results = await Future.wait([
        dashboard.verificationDocuments().catchError((_) => <String, VerificationDocument>{}),
        content.services(),
        membership.catalog(),
      ]);
      if (!mounted) return;
      setState(() {
        _docs = results[0] as Map<String, VerificationDocument>;
        _services = results[1] as List<LegalService>;
        _catalog = results[2] as PlanCatalog;
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

  // ── Step 2: verification ─────────────────────────────────────────────────

  bool get _verificationReady =>
      _barCouncil.text.trim().length >= 3 &&
      _docKinds.every((d) => _docs.containsKey(d.kind)) &&
      _uploading.isEmpty;

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

    setState(() {
      _uploading = kind;
      _error = '';
    });
    try {
      final doc = await context.read<DashboardService>().uploadVerificationDocument(
            kind: kind,
            filePath: file.path!,
            fileName: file.name,
          );
      if (!mounted) return;
      setState(() => _docs = {..._docs, kind: doc});
    } on ApiException catch (e) {
      if (mounted) Toast.error(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = '');
    }
  }

  // ── Step 3: practice areas ───────────────────────────────────────────────

  MembershipPlan? get _plan {
    final c = _catalog;
    if (c == null) return null;
    for (final p in c.plans) {
      if (p.id == c.currentPlanId) return p;
    }
    return c.plans.isEmpty ? null : c.plans.first;
  }

  Future<void> _toggleArea(LegalService area) async {
    if (_areas.contains(area.name)) {
      setState(() {
        _areas.remove(area.name);
        _matters.removeAll(area.subServices.map((m) => m.name));
      });
      return;
    }
    final plan = _plan;
    if (plan != null && !plan.allowsAreas(_areas.length + 1)) {
      final upgraded = await _offerUpgrade(
        'Your ${plan.name} plan covers ${plan.areas} practice ${plan.areas == 1 ? 'area' : 'areas'}. '
        'Upgrade to add ${area.name}.',
      );
      if (!upgraded || !mounted) return;
    }
    setState(() => _areas.add(area.name));
  }

  Future<void> _toggleMatter(String matter) async {
    if (_matters.contains(matter)) {
      setState(() => _matters.remove(matter));
      return;
    }
    final plan = _plan;
    if (plan != null && !plan.allowsMatters(_matters.length + 1)) {
      final upgraded = await _offerUpgrade(
        'Your ${plan.name} plan covers ${plan.matters} ${plan.matters == 1 ? 'matter' : 'matters'}. '
        'Upgrade to add $matter.',
      );
      if (!upgraded || !mounted) return;
    }
    setState(() => _matters.add(matter));
  }

  /// Opens the plans; on a successful upgrade, re-reads the limits so the
  /// choice that was refused goes through.
  Future<bool> _offerUpgrade(String reason) async {
    final catalog = _catalog;
    if (catalog == null) return false;
    final upgraded = await PlanUpgradeSheet.open(context, catalog: catalog, reason: reason);
    if (!upgraded || !mounted) return false;
    try {
      final fresh = await context.read<MembershipService>().catalog();
      if (mounted) setState(() => _catalog = fresh);
    } on ApiException {
      return false;
    }
    return true;
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  Future<void> _continue() async {
    setState(() {
      _saving = true;
      _error = '';
    });
    final dashboard = context.read<DashboardService>();
    try {
      if (_step == 0) {
        await dashboard.saveProfile({'barCouncil': _barCouncil.text.trim()});
        if (!mounted) return;
        setState(() => _step = 1);
      } else {
        await dashboard.saveProfile({
          'services': _areas.toList(),
          'subServices': _matters.toList(),
          // 0 means "not offered" — the website hides the in-person price then.
          'fee': _inPerson == true ? '$_feeValue' : '0',
        });
        if (!mounted) return;
        await _finish('You are all set. Our team will verify your documents shortly.');
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
    final ready = _step == 0 ? _verificationReady : _areas.isNotEmpty && _inPersonReady;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == 1 && !_saving) setState(() => _step = 0);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5FF),
        body: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? const LoadingView(label: 'Getting things ready…')
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        if (_step == 0) ..._verificationStep() else ..._practiceStep(),
                        if (_error.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          NoticeBanner(tone: ChipTone.danger, icon: Icons.error_outline_rounded, message: _error),
                        ],
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton(
                            onPressed: _saving ? null : () => _finish('You can finish this any time from your profile.'),
                            child: Text('I\'ll finish this later', style: TextStyle(color: AppColors.inkFaint)),
                          ),
                        ),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: ready && !_saving && !_loading ? _continue : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      disabledForegroundColor: const Color(0xFF94A3B8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    child: _saving
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Text(_step == 0 ? 'Continue' : 'Finish setup'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final title = _step == 0 ? 'Professional Verification' : 'Practice Areas';
    final subtitle = _step == 0
        ? 'Verify your credentials to start accepting clients'
        : 'Choose what you practise — matters open under each area';
    // Basic Details is done before this screen, so the first segment is full.
    final filled = _step + 2;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_blue, _blueDark]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 40,
                child: _step == 1
                    ? IconButton(
                        onPressed: _saving ? null : () => setState(() => _step = 0),
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      )
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Step ${_step + 2} of 3',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              height: 5,
                              decoration: BoxDecoration(
                                color: i < filled ? Colors.white : Colors.white24,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Row(
                      children: [
                        Expanded(child: Text('Basic Details', style: TextStyle(fontSize: 11, color: Colors.white70))),
                        Expanded(child: Text('Verification', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white70))),
                        Expanded(child: Text('Practice Areas', textAlign: TextAlign.end, style: TextStyle(fontSize: 11, color: Colors.white70))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({required String title, required List<Widget> children, String? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              ),
              if (trailing != null)
                Text(trailing, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.inkFaint)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  List<Widget> _verificationStep() => [
        _card(
          title: 'Bar Council Details',
          children: [
            const Text('Bar Council ID *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _barCouncil,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'e.g. D/1234/2015',
                filled: true,
                fillColor: const Color(0xFFF8FAFF),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _blue, width: 1.8),
                ),
              ),
            ),
          ],
        ),
        _card(
          title: 'Document Upload',
          children: [
            for (var i = 0; i < _docKinds.length; i++) ...[
              if (i > 0) Divider(height: 22, color: AppColors.border),
              _docRow(_docKinds[i]),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.inkFaint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Kept private — seen only by the Justiceland team to verify you, never shown on your profile.',
                    style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.inkFaint),
                  ),
                ),
              ],
            ),
          ],
        ),
      ];

  Widget _docRow(({String kind, String title, IconData icon, Color tint}) d) {
    final doc = _docs[d.kind];
    final busy = _uploading == d.kind;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: busy ? null : () => _pick(d.kind),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: doc != null ? AppColors.successSoft : d.tint.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(doc != null ? Icons.check_circle_rounded : d.icon, color: doc != null ? AppColors.success : d.tint),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    busy
                        ? 'Uploading…'
                        : doc != null
                            ? '${doc.fileName.isEmpty ? 'Uploaded' : doc.fileName} · tap to replace'
                            : 'PDF, JPG or PNG (max 5 MB)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: doc != null ? AppColors.success : AppColors.inkFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(color: const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(12)),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: _blue),
                    )
                  : Icon(doc != null ? Icons.refresh_rounded : Icons.upload_rounded, color: _blue),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _practiceStep() {
    final plan = _plan;
    String limit(int? n) => n == null ? '' : ' of $n';

    return [
      _card(
        title: 'Practice areas',
        trailing: '${_areas.length}${limit(plan?.areas)} selected',
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _services) _chip(s.name, _areas.contains(s.name), () => _toggleArea(s)),
            ],
          ),
          if (plan?.areas != null) ...[
            const SizedBox(height: 10),
            Text(
              '${plan!.name} plan: up to ${plan.areas} areas and ${plan.matters} matters. Pick more to see the plans.',
              style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
          ],
        ],
      ),
      for (final area in _services.where((s) => _areas.contains(s.name)))
        if (area.subServices.isNotEmpty)
          _card(
            title: area.name,
            trailing: '${area.subServices.where((m) => _matters.contains(m.name)).length} chosen',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in area.subServices)
                    _chip(m.name, _matters.contains(m.name), () => _toggleMatter(m.name)),
                ],
              ),
            ],
          ),
      if (_areas.isNotEmpty && plan?.matters != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${_matters.length}${limit(plan?.matters)} matters selected',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
          ),
        ),
      _inPersonCard(),
    ];
  }

  Widget _inPersonCard() {
    Widget option(bool value, String label, IconData icon) {
      final selected = _inPerson == value;
      return Expanded(
        child: Material(
          color: selected ? _blue.withValues(alpha: 0.08) : const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _saving ? null : () => setState(() => _inPerson = value),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? _blue : AppColors.border, width: selected ? 1.8 : 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: selected ? _blue : AppColors.inkFaint),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: selected ? _blue : AppColors.inkMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return _card(
      title: 'In-person consultation',
      children: [
        Text(
          'Are you available for physical (in-person) consultations at your office? *',
          style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.ink.withValues(alpha: 0.8)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            option(true, 'Yes', Icons.check_circle_outline_rounded),
            const SizedBox(width: 10),
            option(false, 'No', Icons.cancel_outlined),
          ],
        ),
        if (_inPerson == true) ...[
          const SizedBox(height: 16),
          const Text('Your fee per visit *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: _fee,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              prefixText: '₹ ',
              hintText: 'e.g. 1000',
              counterText: '',
              filled: true,
              fillColor: const Color(0xFFF8FAFF),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _blue, width: 1.8),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Shown on your profile as “In-Person ₹… /visit”. You can change it any time.',
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
        ],
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? _blue : const Color(0xFFF8FAFF),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _saving ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? _blue : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.ink.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

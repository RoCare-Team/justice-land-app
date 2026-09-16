import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/common.dart';
import '../../services/query_service.dart';
import '../../state/auth_controller.dart';
import '../../state/location_controller.dart';

/// Topics in the words people use for their trouble. Each files the question
/// under the practice area lawyers filter by — the same six as the website.
const List<({String label, String category})> _topics = [
  (label: 'Property / Land', category: 'Property Law'),
  (label: 'Divorce / Family', category: 'Family Law'),
  (label: 'Police / FIR', category: 'Criminal Law'),
  (label: 'Money / Cheque bounce', category: 'Civil Law'),
  (label: 'Job / Salary', category: 'Labour & Employment'),
  (label: 'Consumer complaint', category: 'Consumer Law'),
];

const int _minMessage = 20;

/// "Have a legal problem?" — the app's version of the website's ask popup.
///
/// No account needed. Two numbered steps: what happened, and where a lawyer
/// can call. The question goes to verified lawyers on a paid plan; the first
/// one to take it gets the number, nobody else ever sees it.
class AskLawyerSheet extends StatefulWidget {
  const AskLawyerSheet({super.key, this.category = ''});

  /// Pre-selects a topic, e.g. from a practice-area screen.
  final String category;

  static Future<void> open(BuildContext context, {String category = ''}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Above the client shell's bottom bar. Opened from a tab, the nearest
      // navigator is the shell's own, and the bar covered the send button.
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AskLawyerSheet(category: category),
    );
  }

  @override
  State<AskLawyerSheet> createState() => _AskLawyerSheetState();
}

class _AskLawyerSheetState extends State<AskLawyerSheet> {
  final _message = TextEditingController();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _city;
  late String _category = widget.category;

  bool _busy = false;
  bool _sent = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthController>().user;
    final location = context.read<LocationController>();
    _name = TextEditingController(text: user?.name ?? '');
    final digits = Validators.digitsOnly(user?.phone);
    _phone = TextEditingController(text: digits.length > 10 ? digits.substring(digits.length - 10) : digits);
    _city = TextEditingController(text: location.city);
    for (final c in [_message, _name, _phone]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _message.dispose();
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    super.dispose();
  }

  int get _left => (_minMessage - _message.text.trim().length).clamp(0, _minMessage);
  bool get _step1Done => _left == 0;
  bool get _ready =>
      _step1Done && _name.text.trim().length >= 2 && Validators.isMobile(Validators.digitsOnly(_phone.text));

  Future<void> _send() async {
    if (!_ready || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await context.read<QueryService>().ask(
            name: _name.text.trim(),
            phone: Validators.digitsOnly(_phone.text),
            message: _message.text.trim(),
            category: _category,
            city: _city.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: _sent ? _success() : _form(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 18),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primaryDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Have a legal problem?',
                  style: TextStyle(fontFamily: AppText.display, fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ],
          ),
          const Text(
            'Tell us what happened. A verified lawyer will call you — free, no login.',
            style: TextStyle(fontSize: 13.5, height: 1.4, color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _step(Icons.edit_note_rounded, 'You write\nthe problem'),
              const SizedBox(width: 8),
              _step(Icons.how_to_reg_rounded, 'A lawyer\ntakes it'),
              const SizedBox(width: 8),
              _step(Icons.phone_in_talk_rounded, 'You get\na call'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _step(IconData icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Icon(icon, size: 20, color: AppColors.accent),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, height: 1.25, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepTitle(int n, bool done, String title) {
    return Row(
      children: [
        Container(
          height: 26,
          width: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? AppColors.success : AppColors.primary.withValues(alpha: 0.08),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
              : Text('$n', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
      ],
    );
  }

  Widget _form() {
    final topics = [
      if (widget.category.isNotEmpty && !_topics.any((t) => t.category == widget.category))
        (label: widget.category, category: widget.category),
      ..._topics,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(1, _step1Done, 'What is your problem?'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in topics)
              ChoiceChip(
                label: Text(t.label),
                selected: _category == t.category,
                onSelected: (on) => setState(() => _category = on ? t.category : ''),
                showCheckmark: false,
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _category == t.category ? Colors.white : AppColors.ink.withValues(alpha: 0.7),
                ),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surface,
                side: BorderSide(color: _category == t.category ? AppColors.primary : AppColors.border),
                shape: const StadiumBorder(),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _message,
          maxLines: 4,
          maxLength: 1500,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Write in your own words, in English or Hindi. e.g. My landlord is not returning my ₹60,000 deposit for 3 months.',
            hintMaxLines: 3,
            counterText: '',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _step1Done
              ? 'Looks good. Don’t share bank details or passwords.'
              : _message.text.trim().isEmpty
                  ? 'A few lines are enough.'
                  : 'Write a little more — $_left more letters',
          style: TextStyle(fontSize: 12, color: _step1Done ? AppColors.success : AppColors.inkFaint),
        ),
        const SizedBox(height: 22),
        _stepTitle(2, _ready, 'Where should the lawyer call you?'),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Your name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91  ', counterText: ''),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _city,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'City (optional)'),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 14),
          NoticeBanner(message: _error, tone: ChipTone.danger, icon: Icons.error_outline_rounded),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _ready && !_busy ? _send : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: const Color(0xFF241B02),
              disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.4),
              disabledForegroundColor: const Color(0xFF241B02).withValues(alpha: 0.6),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            icon: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF241B02)))
                : const Icon(Icons.send_rounded, size: 18),
            label: const Text('Get a free call from a lawyer'),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 4,
          children: [
            _trust(Icons.lock_outline_rounded, 'Number stays private'),
            _trust(Icons.verified_user_outlined, 'Verified lawyers'),
            _trust(Icons.schedule_rounded, 'No login, free'),
          ],
        ),
      ],
    );
  }

  Widget _trust(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.success),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint))),
      ],
    );
  }

  Widget _success() {
    final digits = Validators.digitsOnly(_phone.text);
    final pretty = digits.length == 10 ? '${digits.substring(0, 5)} ${digits.substring(5)}' : digits;
    return Column(
      children: [
        const SizedBox(height: 6),
        Container(
          height: 68,
          width: 68,
          decoration: const BoxDecoration(color: AppColors.successSoft, shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_outline_rounded, size: 40, color: AppColors.success),
        ),
        const SizedBox(height: 14),
        const Text(
          'Done! A lawyer will call you',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: AppText.display, fontSize: 21, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Your problem has reached our verified lawyers. The one who takes it up will call you on +91 $pretty. Nobody else sees your number.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.inkMuted),
        ),
        const SizedBox(height: 22),
        PrimaryButton(label: 'OK, got it', onPressed: () => Navigator.of(context).pop()),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => setState(() {
            _sent = false;
            _message.clear();
            _category = widget.category;
          }),
          child: const Text('Ask another question'),
        ),
      ],
    );
  }
}

/// The "Not sure which lawyer to pick?" strip that opens [AskLawyerSheet].
class AskLawyerBanner extends StatelessWidget {
  const AskLawyerBanner({super.key, this.category = ''});

  final String category;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => AskLawyerSheet.open(context, category: category),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.question_answer_outlined, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Have a legal problem?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text(
                      'Tell us — a verified lawyer will call you. Free, no login.',
                      style: TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFF475569)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                child: const Text('Ask free', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

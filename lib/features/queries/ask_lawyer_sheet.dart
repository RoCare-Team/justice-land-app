import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../services/query_service.dart';
import '../../state/auth_controller.dart';
import '../../state/location_controller.dart';

/// Topics in the words people use for their trouble. Each files the question
/// under the practice area lawyers filter by — the same six as the website.
const List<({String label, String category, IconData icon})> _topics = [
  (label: 'Property / Land', category: 'Property Law', icon: Icons.home_work_outlined),
  (label: 'Divorce / Family', category: 'Family Law', icon: Icons.family_restroom_rounded),
  (label: 'Police / FIR', category: 'Criminal Law', icon: Icons.local_police_outlined),
  (label: 'Money / Cheque bounce', category: 'Civil Law', icon: Icons.currency_rupee_rounded),
  (label: 'Job / Salary', category: 'Labour & Employment', icon: Icons.work_outline_rounded),
  (label: 'Consumer complaint', category: 'Consumer Law', icon: Icons.shopping_bag_outlined),
];

const int _minMessage = 20;
const int _maxMessage = 1500;

/// "Describe your legal problem" — the app's version of the website's free
/// Ask-a-lawyer popup.
///
/// No account needed. Step one is the problem, and the quickest way to give it
/// is to say it: the big microphone dictates straight into the box, in Hindi or
/// English, with the phone's own recognizer. Typing works just as well. Step
/// two is where a lawyer can call. The question goes to verified lawyers; the
/// first to take it gets the number, nobody else ever sees it.
class AskLawyerSheet extends StatefulWidget {
  const AskLawyerSheet({super.key, this.category = '', this.listenOnOpen = false});

  /// Pre-selects a topic, e.g. from a practice-area screen.
  final String category;

  /// Starts listening the moment the sheet is up — for the "Tap to speak"
  /// button outside it, which has already been tapped once.
  final bool listenOnOpen;

  static Future<void> open(BuildContext context, {String category = '', bool listenOnOpen = false}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Above the client shell's bottom bar. Opened from a tab, the nearest
      // navigator is the shell's own, and the bar covered the send button.
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AskLawyerSheet(category: category, listenOnOpen: listenOnOpen),
    );
  }

  @override
  State<AskLawyerSheet> createState() => _AskLawyerSheetState();
}

class _AskLawyerSheetState extends State<AskLawyerSheet> with SingleTickerProviderStateMixin {
  final _message = TextEditingController();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _city;
  late String _category = widget.category;

  bool _busy = false;
  bool _sent = false;
  String _error = '';

  // ── Dictation ────────────────────────────────────────────────────────────
  final _speech = SpeechToText();
  bool _speechReady = false;
  bool _listening = false;

  /// 'hi_IN' or 'en_IN'. Hindi first: most people describing a problem to a
  /// lawyer in India think it in Hindi, and the recognizer handles the English
  /// words mixed into it.
  String _locale = 'hi_IN';

  /// What was in the box when listening started — the spoken words are added
  /// after it rather than replacing what was typed.
  String _before = '';

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

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
    if (widget.listenOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toggleListening());
    }
  }

  @override
  void dispose() {
    // The microphone must not outlive the sheet.
    _speech.cancel();
    _pulse.dispose();
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

  void _setListening(bool on) {
    if (!mounted || on == _listening) return;
    setState(() => _listening = on);
    if (on) {
      _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.reset();
    }
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      _setListening(false);
      return;
    }
    FocusScope.of(context).unfocus();
    // Asks for the microphone the first time; after a refusal it answers
    // false straight away, and saying why beats a mic that does nothing.
    _speechReady = _speechReady ||
        await _speech.initialize(
          onStatus: (status) {
            if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
              _setListening(false);
            }
          },
          onError: (_) => _setListening(false),
        );
    if (!mounted) return;
    if (!_speechReady) {
      Toast.error(context, 'Speaking needs the microphone. Allow it for Justiceland in your phone settings — or type instead.');
      return;
    }
    _before = _message.text.trim();
    _setListening(true);
    await _speech.listen(
      onResult: _onWords,
      listenOptions: SpeechListenOptions(
        localeId: _locale,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        // Room to think mid-sentence; a minute is plenty for a problem.
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 60),
      ),
    );
  }

  void _onWords(SpeechRecognitionResult result) {
    if (!mounted) return;
    final words = result.recognizedWords.trim();
    var text = _before.isEmpty ? words : '$_before $words';
    if (text.length > _maxMessage) text = text.substring(0, _maxMessage);
    _message.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    if (result.finalResult) _setListening(false);
  }

  Future<void> _send() async {
    if (!_ready || _busy) return;
    FocusScope.of(context).unfocus();
    final queries = context.read<QueryService>();
    if (_listening) await _speech.stop();
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await queries.ask(
            name: _name.text.trim(),
            phone: Validators.digitsOnly(_phone.text),
            message: _message.text.trim(),
            category: _category,
            city: _city.text.trim(),
          );
      await AskLawyerPrompt.markSent();
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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

  /* ── Header ─────────────────────────────────────────────────────────── */

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 18),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
                ),
                child: const Text(
                  'FREE · NO LOGIN',
                  style: TextStyle(fontSize: 10.5, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.accent),
                ),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _sent ? 'Your question is with our lawyers' : 'Describe your legal problem',
            style: const TextStyle(
              fontFamily: AppText.display,
              fontSize: 23,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Bolkar ya likhkar batayein — a verified lawyer will call you back.',
            style: TextStyle(fontSize: 13.5, height: 1.4, color: Colors.white70),
          ),
          if (!_sent) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _step(Icons.record_voice_over_rounded, 'You tell us\nthe problem'),
                const SizedBox(width: 8),
                _step(Icons.how_to_reg_rounded, 'A lawyer\ntakes it up'),
                const SizedBox(width: 8),
                _step(Icons.phone_in_talk_rounded, 'You get\na call'),
              ],
            ),
          ],
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
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
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

  /* ── Step 1: the problem, spoken or typed ─────────────────────────────── */

  Widget _speakPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: _listening ? AppColors.accentSoft : AppColors.muted,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _listening ? AppColors.accent.withValues(alpha: 0.6) : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _toggleListening,
            child: SizedBox(
              height: 112,
              width: 112,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Two rings expanding outward while it listens — the
                  // universal "I can hear you" signal.
                  if (_listening)
                    for (final delay in const [0.0, 0.5])
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) {
                          final t = (_pulse.value + delay) % 1.0;
                          return Container(
                            height: 78 + 34 * t,
                            width: 78 + 34 * t,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.accent.withValues(alpha: 0.35 * (1 - t)),
                            ),
                          );
                        },
                      ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 78,
                    width: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _listening
                            ? const [Color(0xFFDC2626), Color(0xFFB91C1C)]
                            : const [Color(0xFFE5B42A), AppColors.accent],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_listening ? AppColors.danger : AppColors.accent).withValues(alpha: 0.4),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      _listening ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 36,
                      color: _listening ? Colors.white : AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _listening ? 'Listening… tap to stop' : 'Tap to speak',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _listening ? AppColors.danger : AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _listening ? 'Apni baat aaram se boliye' : 'Apni problem apne shabdon me boliye',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 12),
          // Which language the phone listens for.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _langChip('hi_IN', 'हिंदी'),
              const SizedBox(width: 8),
              _langChip('en_IN', 'English'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _langChip(String locale, String label) {
    final on = _locale == locale;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      onSelected: _listening ? null : (_) => setState(() => _locale = locale),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: on ? Colors.white : AppColors.ink.withValues(alpha: 0.7),
      ),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      side: BorderSide(color: on ? AppColors.primary : AppColors.border),
      shape: const StadiumBorder(),
    );
  }

  Widget _form() {
    final topics = [
      if (widget.category.isNotEmpty && !_topics.any((t) => t.category == widget.category))
        (label: widget.category, category: widget.category, icon: Icons.gavel_rounded),
      ..._topics,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(1, _step1Done, 'What happened?'),
        const SizedBox(height: 12),
        _speakPanel(),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: Divider(color: AppColors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('or type it', style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
            ),
            Expanded(child: Divider(color: AppColors.border)),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _message,
          minLines: 3,
          maxLines: 6,
          maxLength: _maxMessage,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'e.g. Mera landlord 3 mahine se ₹60,000 ka deposit wapas nahi kar raha.',
            hintMaxLines: 3,
            counterText: '',
            filled: true,
            fillColor: _listening ? AppColors.accentSoft.withValues(alpha: 0.5) : AppColors.surface,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              _step1Done ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              size: 14,
              color: _step1Done ? AppColors.success : AppColors.inkFaint,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                _step1Done
                    ? 'Looks good. Don’t share bank details or passwords.'
                    : _message.text.trim().isEmpty
                        ? 'A few lines are enough.'
                        : 'A little more please — $_left more letters',
                style: TextStyle(fontSize: 12, color: _step1Done ? AppColors.success : AppColors.inkFaint),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Topic (optional)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in topics)
              ChoiceChip(
                avatar: Icon(
                  t.icon,
                  size: 16,
                  color: _category == t.category ? Colors.white : AppColors.primary,
                ),
                label: Text(t.label),
                selected: _category == t.category,
                onSelected: (on) => setState(() => _category = on ? t.category : ''),
                showCheckmark: false,
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _category == t.category ? Colors.white : AppColors.ink.withValues(alpha: 0.75),
                ),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surface,
                side: BorderSide(color: _category == t.category ? AppColors.primary : AppColors.border),
                shape: const StadiumBorder(),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _stepTitle(2, _ready, 'Where should the lawyer call you?'),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Your name',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Mobile number',
            prefixIcon: Icon(Icons.phone_outlined),
            prefixText: '+91  ',
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _city,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'City (optional)',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 14),
          NoticeBanner(message: _error, tone: ChipTone.danger, icon: Icons.error_outline_rounded),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: _ready && !_busy ? _send : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: const Color(0xFF241B02),
              disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.4),
              disabledForegroundColor: const Color(0xFF241B02).withValues(alpha: 0.6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
            ),
            icon: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF241B02)))
                : const Icon(Icons.send_rounded, size: 18),
            label: const Text('Get a free call from a lawyer'),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 4,
          children: [
            _trust(Icons.lock_outline_rounded, 'Number stays private'),
            _trust(Icons.verified_user_outlined, 'Verified lawyers'),
            _trust(Icons.money_off_rounded, 'Free to ask'),
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
          height: 76,
          width: 76,
          decoration: const BoxDecoration(color: AppColors.successSoft, shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded, size: 44, color: AppColors.success),
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

/// When to offer the ask sheet on its own, the way the website's popup does —
/// once per launch at most, never to a lawyer, and not again for a while once
/// it has been waved away (3 days) or used (7 days). Nobody wants the same
/// popup every time they open an app.
class AskLawyerPrompt {
  const AskLawyerPrompt._();

  static const _dismissedKey = 'ask_prompt_dismissed_at';
  static const _sentKey = 'ask_prompt_sent_at';
  static const _quietAfterDismiss = Duration(days: 3);
  static const _quietAfterSend = Duration(days: 7);

  /// Long enough for the home screen to be seen first.
  static const _delay = Duration(seconds: 6);

  static bool _triedThisLaunch = false;

  static Future<void> markSent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_sentKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {/* the prompt may simply offer itself again */}
  }

  /// Call once the home screen is up. Waits, then opens the sheet if this
  /// visitor should see it and nothing else is on top.
  static Future<void> maybeShow(BuildContext context) async {
    if (_triedThisLaunch) return;
    _triedThisLaunch = true;

    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final dismissed = prefs.getInt(_dismissedKey) ?? 0;
    final sent = prefs.getInt(_sentKey) ?? 0;
    if (now - dismissed < _quietAfterDismiss.inMilliseconds || now - sent < _quietAfterSend.inMilliseconds) {
      return;
    }

    await Future<void>.delayed(_delay);
    if (!context.mounted) return;
    // Not over another sheet, a dialog or a pushed screen, and never for a
    // lawyer — this is for people looking for one.
    if (context.read<AuthController>().isAdvocate) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;

    await AskLawyerSheet.open(context);
    final sentNow = prefs.getInt(_sentKey) ?? 0;
    if (sentNow <= now) {
      await prefs.setInt(_dismissedKey, DateTime.now().millisecondsSinceEpoch);
    }
  }
}

/// The floating "Ask a lawyer — free" pill, the app's copy of the website's
/// button in the corner: always one tap from the problem, with the mic on it.
class AskLawyerFab extends StatelessWidget {
  const AskLawyerFab({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      elevation: 6,
      shadowColor: AppColors.accent.withValues(alpha: 0.5),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => AskLawyerSheet.open(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 32,
                width: 32,
                decoration: const BoxDecoration(color: AppColors.primaryDark, shape: BoxShape.circle),
                child: const Icon(Icons.mic_rounded, size: 18, color: AppColors.accent),
              ),
              const SizedBox(width: 8),
              const Text(
                'Ask a lawyer — free',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF241B02)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Have a legal problem?" card that opens [AskLawyerSheet] — with a
/// "Tap to speak" button that opens it already listening.
class AskLawyerBanner extends StatelessWidget {
  const AskLawyerBanner({super.key, this.category = ''});

  final String category;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primaryDark],
        ),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => AskLawyerSheet.open(context, category: category),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 42,
                      width: 42,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.question_answer_rounded, color: AppColors.accent),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Describe your legal problem',
                            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'A verified lawyer will call you. Free, no login.',
                            style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _BannerButton(
                        icon: Icons.mic_rounded,
                        label: 'Tap to speak',
                        filled: true,
                        onTap: () => AskLawyerSheet.open(context, category: category, listenOnOpen: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _BannerButton(
                        icon: Icons.edit_rounded,
                        label: 'Type it',
                        onTap: () => AskLawyerSheet.open(context, category: category),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerButton extends StatelessWidget {
  const _BannerButton({required this.icon, required this.label, required this.onTap, this.filled = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.accent : Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: filled ? AppColors.primaryDark : Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: filled ? AppColors.primaryDark : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

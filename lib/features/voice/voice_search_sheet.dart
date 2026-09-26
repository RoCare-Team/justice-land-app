import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../models/voice_search.dart';
import '../../services/voice_service.dart';
import '../lawyers/advocate_card.dart';

/// "Tell us your legal problem" — say it, and the right lawyers come back.
///
/// Built for the client who does not know that an unpaid salary is "Labour &
/// Employment": they speak, in Hindi or English or both, and the server does
/// the understanding. This screen's whole job is to capture a clean recording
/// and to be honest about what is happening to it.
///
/// It stops listening on its own. Holding a button down, or hunting for Stop
/// while trying to explain a problem, is exactly the moment people give up —
/// so the recording ends when the speaking does: once a sentence has been
/// heard, a pause of [_silenceHold] finishes it. Stop is still there for
/// anyone who wants it, and the microphone is released the instant either
/// happens.
class VoiceSearchSheet extends StatefulWidget {
  const VoiceSearchSheet({super.key});

  /// Opens it over everything, including the bottom tab bar.
  static Future<void> open(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const VoiceSearchSheet(),
      );

  @override
  State<VoiceSearchSheet> createState() => _VoiceSearchSheetState();
}

enum _Phase { idle, permission, recording, working, results, error }

/// The longest clip the server accepts. Reaching it stops the recording rather
/// than letting someone talk into audio that will be refused.
const _maxSeconds = 60;

/// Loud enough to be someone speaking, in dBFS. Quiet rooms sit near -50.
const _speechDb = -35.0;

/// Below this counts as a pause.
const _silenceDb = -42.0;

/// How long a pause has to last before the recording is finished. Long enough
/// to think mid-sentence, short enough that nobody wonders if it is stuck.
const _silenceHold = Duration(milliseconds: 1800);

/// Nothing heard at all by here: the microphone is muted, or the phone cannot
/// hear them, and waiting the full minute helps nobody.
const _giveUpOnSilenceAfter = Duration(seconds: 9);

/// Shorter than this is a slip of the finger, not a problem being described.
const _minSpeechMs = 1200;

class _VoiceSearchSheetState extends State<VoiceSearchSheet> {
  final _recorder = AudioRecorder();
  final _cityController = TextEditingController();

  StreamSubscription<Amplitude>? _amplitude;
  Timer? _ticker;

  _Phase _phase = _Phase.idle;
  String _error = '';
  String _stage = 'Sending your recording…';
  VoiceSearchResult? _result;

  String _path = '';
  DateTime? _startedAt;
  int _seconds = 0;

  /// Current loudness, 0..1, for the bars.
  double _level = 0;

  /// Whether anything that sounded like speech has been heard yet, and when we
  /// last heard it — the two facts the automatic stop is built on.
  bool _heardSpeech = false;
  DateTime? _lastLoudAt;
  bool _stopping = false;

  @override
  void dispose() {
    _amplitude?.cancel();
    _ticker?.cancel();
    _cityController.dispose();
    // Fire and forget: the sheet is going away and the microphone must not
    // outlive it, but there is nothing left to await it.
    unawaited(_recorder.stop().catchError((_) => null));
    _recorder.dispose();
    super.dispose();
  }

  /* ── Recording ───────────────────────────────────────────────────────── */

  Future<void> _start() async {
    setState(() {
      _error = '';
      _result = null;
      _heardSpeech = false;
      _lastLoudAt = null;
      _stopping = false;
      _level = 0;
      _seconds = 0;
      _phase = _Phase.permission;
    });

    try {
      if (!await _recorder.hasPermission()) {
        _fail('Microphone access was blocked. Allow it in your phone settings and try again.');
        return;
      }

      final dir = await getTemporaryDirectory();
      _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Mono, 16 kHz, AAC: speech is all that matters here and this is what
      // transcription wants anyway. A minute of it is a few hundred kilobytes,
      // which matters on a phone paying for the upload.
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 32000,
        ),
        path: _path,
      );

      _startedAt = DateTime.now();
      if (mounted) setState(() => _phase = _Phase.recording);

      _amplitude = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 150))
          .listen(_onAmplitude);

      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds += 1);
        if (_seconds >= _maxSeconds) _stop();
      });
    } catch (e) {
      _fail('We could not reach your microphone. Please check it and try again.');
    }
  }

  /// Every reading from the microphone: the bars, and the decision to stop.
  void _onAmplitude(Amplitude amp) {
    if (!mounted || _stopping) return;

    final db = amp.current;
    // dBFS runs from about -50 (a quiet room) to 0 (clipping). Mapped here so
    // ordinary speech fills most of the meter rather than a sliver of it.
    final level = ((db + 45) / 45).clamp(0.0, 1.0);
    final now = DateTime.now();

    if (db > _speechDb) {
      _heardSpeech = true;
      _lastLoudAt = now;
    }

    setState(() => _level = level);

    final since = _startedAt == null ? Duration.zero : now.difference(_startedAt!);

    // Heard them, and they have now stopped: that is the end of the answer.
    if (_heardSpeech && db < _silenceDb && _lastLoudAt != null
        && now.difference(_lastLoudAt!) >= _silenceHold
        && since.inMilliseconds > _minSpeechMs) {
      _stop();
      return;
    }

    // Never heard anything at all: say so instead of recording silence for a
    // minute and failing at the end of it.
    if (!_heardSpeech && since >= _giveUpOnSilenceAfter) {
      _stop(silent: true);
    }
  }

  Future<void> _stop({bool silent = false, bool discard = false}) async {
    if (_stopping) return;
    _stopping = true;

    _ticker?.cancel();
    await _amplitude?.cancel();
    _amplitude = null;

    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _path.isEmpty ? null : _path;
    }

    if (!mounted) return;
    if (discard) {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {
          // A temporary file we could not remove is the operating system's
          // problem, not the client's.
        }
      }
      return;
    }

    if (silent || !_heardSpeech) {
      _fail('Your phone did not pick up any sound. Check the microphone is not covered or muted, then try again.');
      return;
    }

    final ranMs = _startedAt == null
        ? 0
        : DateTime.now().difference(_startedAt!).inMilliseconds;
    if (ranMs < _minSpeechMs) {
      _fail('That was too quick — start again and say what the problem is.');
      return;
    }
    if (path == null || !File(path).existsSync()) {
      _fail('The recording did not save. Please try again.');
      return;
    }

    await _send(path);
  }

  /* ── Sending ─────────────────────────────────────────────────────────── */

  Future<void> _send(String path, {String city = ''}) async {
    setState(() {
      _phase = _Phase.working;
      _stage = 'Sending your recording…';
    });

    // The request is one round trip, but it really does pass through these
    // stages in this order, so the wait says what is happening rather than
    // spinning silently.
    final narration = <Timer>[
      Timer(const Duration(milliseconds: 1200), () => _say('Writing down what you said…')),
      Timer(const Duration(milliseconds: 3600), () => _say('Understanding your legal issue…')),
      Timer(const Duration(milliseconds: 6000), () => _say('Finding relevant lawyers…')),
    ];

    try {
      final result = await context.read<VoiceService>().search(
            filePath: path,
            mimeType: 'audio/mp4',
            city: city,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _Phase.results;
      });
    } on ApiException catch (e) {
      // The server already answers in plain language; nothing technical is
      // ever put in front of the person who just spoke.
      _fail(e.message);
    } catch (_) {
      _fail('Something went wrong. Please try again.');
    } finally {
      for (final t in narration) {
        t.cancel();
      }
    }
  }

  /// Answers "which city?" without paying to transcribe the same words twice.
  Future<void> _answerCity() async {
    final city = _cityController.text.trim();
    final transcript = _result?.transcript ?? '';
    if (city.isEmpty || transcript.isEmpty) return;

    setState(() {
      _phase = _Phase.working;
      _stage = 'Finding lawyers in $city…';
    });

    try {
      final result = await context.read<VoiceService>().searchText(
            transcript: transcript,
            city: city,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _Phase.results;
      });
    } on ApiException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('Something went wrong. Please try again.');
    }
  }

  void _say(String stage) {
    if (mounted && _phase == _Phase.working) setState(() => _stage = stage);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _phase = _Phase.error;
    });
  }

  /* ── UI ──────────────────────────────────────────────────────────────── */

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: DraggableScrollableSheet(
        initialChildSize: _phase == _Phase.results ? 0.85 : 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              _header(),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  children: [_body()],
                ),
              ),
              _disclaimer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.accent),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Apni legal problem bataiye',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                SizedBox(height: 2),
                Text(
                  'Hindi ya English — jaise bolna ho bol dijiye',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _disclaimer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.muted,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Text(
        _result?.disclaimer.isNotEmpty == true
            ? _result!.disclaimer
            : 'This AI helps identify relevant legal services. It does not provide legal advice or representation.',
        style: TextStyle(fontSize: 10.5, height: 1.4, color: AppColors.inkFaint),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.idle:
        return _idle();
      case _Phase.permission:
        return _waiting('Microphone ki permission…');
      case _Phase.recording:
        return _recording();
      case _Phase.working:
        return _waiting(_stage);
      case _Phase.error:
        return _errorView();
      case _Phase.results:
        return _results(_result!);
    }
  }

  Widget _idle() {
    return Column(
      children: [
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _start,
          child: Container(
            height: 104,
            width: 104,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_rounded, size: 40, color: Colors.white),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Tap karke boliye',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 8),
        Text(
          '“Meri company mujhe teen mahine se salary nahi de rahi hai, mujhe lawyer chahiye.”',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.ink.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 12),
        Text(
          'Bolna band karte hi recording apne aap ruk jayegi',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
        ),
      ],
    );
  }

  Widget _waiting(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const SizedBox(
            height: 34,
            width: 34,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
        ],
      ),
    );
  }

  Widget _recording() {
    final clock = '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';
    final quiet = !_heardSpeech && _seconds >= 3;

    return Column(
      children: [
        const SizedBox(height: 6),
        Container(
          height: 96,
          width: 96,
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.10 + _level * 0.18),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Container(
            height: 74,
            width: 74,
            decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
            child: const Icon(Icons.mic_rounded, size: 32, color: Colors.white),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          clock,
          style: const TextStyle(
            fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),

        // Bars that move are the proof that the phone is hearing them — worth
        // more than any sentence this screen could print.
        SizedBox(
          height: 26,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(11, (i) {
              final spread = 1 - (i - 5).abs() / 5 * 0.55;
              final height = (4 + _level * 22 * spread).clamp(4.0, 26.0);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: 4,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: quiet ? AppColors.border : AppColors.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          quiet
              ? 'Koi awaaz nahi aa rahi — mic check kijiye'
              : _heardSpeech
                  ? 'Sun rahe hain… ruk jaiye to apne aap band ho jayega'
                  : 'Boliye…',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: quiet ? AppColors.danger : AppColors.ink.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => _stop(),
              icon: const Icon(Icons.stop_rounded, size: 20),
              label: const Text('Ho gaya'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () async {
                await _stop(discard: true);
                if (mounted) setState(() => _phase = _Phase.idle);
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: AppColors.dangerSoft, shape: BoxShape.circle),
            child: const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 26),
          ),
          const SizedBox(height: 14),
          Text(
            _error,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.ink.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Dobara boliye'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Band kijiye'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _results(VoiceSearchResult result) {
    final analysis = result.analysis;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // What was heard, shown back. If the phone misheard them, this is the
        // only way they can tell — and the fix is one tap away.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.muted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AAPNE KAHA',
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 1.1, color: AppColors.inkFaint,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '“${result.transcript}”',
                style: TextStyle(
                  fontSize: 14, height: 1.5, fontStyle: FontStyle.italic,
                  color: AppColors.ink.withValues(alpha: 0.85),
                ),
              ),
              if (analysis.category.isNotEmpty || analysis.location.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (analysis.category.isNotEmpty)
                      _chip(analysis.category, Icons.auto_awesome_rounded, AppColors.primary),
                    if (analysis.issue.isNotEmpty) _chip(analysis.issue, null, AppColors.inkMuted),
                    if (analysis.location.isNotEmpty)
                      _chip(analysis.location, Icons.place_rounded, AppColors.success),
                    if (analysis.isUrgent) _chip('Urgent', null, AppColors.danger),
                  ],
                ),
              ],
            ],
          ),
        ),

        if (result.needsCity) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.followUpQuestion,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cityController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _answerCity(),
                        decoration: const InputDecoration(
                          hintText: 'City, jaise Gurgaon',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _answerCity,
                      child: const Text('Dhundhiye'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        if (!result.isEmpty && (result.relaxed.isNotEmpty || result.toppedUp)) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              result.relaxed.contains('city') && analysis.location.isNotEmpty
                  ? '${analysis.location} me koi match nahi mila — ye poore India ke lawyers hain.'
                  : result.relaxed.isNotEmpty
                      ? 'Search thoda wide kiya hai, ye sabse kareebi matches hain.'
                      : analysis.location.isNotEmpty
                          ? '${analysis.location} ke lawyers pehle, uske baad baaki India se.'
                          : 'Sabse kareebi matches pehle.',
              style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.warning),
            ),
          ),
        ],

        const SizedBox(height: 16),

        if (result.isEmpty)
          Column(
            children: [
              const SizedBox(height: 10),
              const Text(
                'Koi lawyer itna match nahi hua.',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              const SizedBox(height: 6),
              Text(
                'Thoda aur detail me boliye, ya directory se khud choose kijiye.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.ink.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.mic_rounded, size: 18),
                    label: const Text('Dobara boliye'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).maybePop();
                      context.go('/lawyers');
                    },
                    child: const Text('Lawyers dekhiye'),
                  ),
                ],
              ),
            ],
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '${result.lawyers.length} lawyer${result.lawyers.length == 1 ? '' : 's'} aapke liye',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
              TextButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.mic_rounded, size: 16),
                label: const Text('Dobara'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final match in result.lawyers)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdvocateCard(advocate: match.advocate),
                  if (match.reason.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.verified_user_rounded, size: 14, color: AppColors.primary),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                const TextSpan(
                                  text: 'Ye lawyer kyun? ',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                TextSpan(text: match.reason),
                              ]),
                              style: TextStyle(
                                fontSize: 12, height: 1.4,
                                color: AppColors.ink.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _chip(String label, IconData? icon, Color tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tone),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: tone),
          ),
        ],
      ),
    );
  }
}

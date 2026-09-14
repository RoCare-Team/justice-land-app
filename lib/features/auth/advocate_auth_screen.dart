import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../state/auth_controller.dart';

/// How a lawyer gets into JusticeLand — the whole of it.
///
/// A number and a code, and nothing else. If the number already belongs to a
/// lawyer they are signed in and sent to their dashboard; if it does not, the
/// same screen asks for a name, an email and a city, and that creates the
/// account. There is no password anywhere in this flow, because the website
/// removed passwords for lawyers entirely — `/api/auth/login` and
/// `/api/auth/register` no longer exist, which is why the app's old
/// email-and-password screens could not sign anybody in.
///
/// The phone number is deliberately not carried into the third step. The
/// server proved it and remembers it in an httpOnly cookie; the signup call
/// sends only the three new fields. An app that posted the number itself could
/// create an account on a line it never verified.
class AdvocateAuthScreen extends StatefulWidget {
  const AdvocateAuthScreen({super.key, this.intent = AdvocateAuthIntent.register});

  /// Changes the words on the first step and nothing else. Which of the two
  /// things actually happens is decided by the number, so a lawyer who opened
  /// the wrong entry point still ends up in the right place.
  final AdvocateAuthIntent intent;

  @override
  State<AdvocateAuthScreen> createState() => _AdvocateAuthScreenState();
}

enum AdvocateAuthIntent { login, register }

enum _Step { phone, otp, details }

/// The gateway sends four digits.
const int _otpLength = 4;

class _AdvocateAuthScreenState extends State<AdvocateAuthScreen> {
  _Step _step = _Step.phone;

  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _city = TextEditingController();
  final _codeNodes = List.generate(_otpLength, (_) => FocusNode());
  final _codeFields = List.generate(_otpLength, (_) => TextEditingController());

  String _notice = '';

  /// Something went wrong after the code was accepted — shown in red, and kept
  /// apart from [AuthController.error], which only carries request failures.
  String _failure = '';
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phone.dispose();
    _name.dispose();
    _email.dispose();
    _city.dispose();
    for (final n in _codeNodes) {
      n.dispose();
    }
    for (final c in _codeFields) {
      c.dispose();
    }
    super.dispose();
  }

  String get _code => _codeFields.map((c) => c.text).join();

  bool get _phoneValid => RegExp(r'^[6-9]\d{9}$').hasMatch(_phone.text.trim());

  bool get _detailsValid =>
      _name.text.trim().length >= 2 &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(_email.text.trim()) &&
      _city.text.trim().isNotEmpty;

  void _startResendCountdown(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _sendCode({bool resend = false}) async {
    final auth = context.read<AuthController>();
    final ok = await auth.sendAdvocateOtp(_phone.text.trim());
    if (!mounted || !ok) return;

    setState(() {
      _step = _Step.otp;
      _failure = '';
      _notice = resend
          ? 'A new code is on its way.'
          : 'Code sent to ••••••${_phone.text.trim().substring(6)}.';
      if (resend) {
        for (final c in _codeFields) {
          c.clear();
        }
      }
    });
    _startResendCountdown(30);
    _codeNodes.first.requestFocus();
  }

  Future<void> _verify() async {
    final auth = context.read<AuthController>();
    final result = await auth.verifyAdvocateOtp(
      phone: _phone.text.trim(),
      otp: _code,
    );
    if (!mounted) return;

    if (result == null) {
      // Wrong or expired code — clear the boxes so the next attempt starts
      // from an empty field rather than one the lawyer has to erase.
      for (final c in _codeFields) {
        c.clear();
      }
      _codeNodes.first.requestFocus();
      return;
    }

    if (result.registered) {
      // Known number: already signed in by that call.
      _openDashboard(
        auth,
        result.name.isEmpty ? 'Signed in.' : 'Welcome back, ${result.name}.',
      );
      return;
    }

    setState(() {
      _step = _Step.details;
      _notice = '';
      _failure = '';
    });
  }

  /// Where a lawyer goes once they are in.
  ///
  /// `go`, not a pop. Adopting the session makes the router rebuild its stack,
  /// and popping across that rebuild left the lawyer sitting on this very form
  /// — signed in, looking at the screen that had just signed them in. Naming
  /// the destination is also the honest end of this flow: someone who has
  /// verified wants their dashboard, not whichever screen sent them here.
  void _openDashboard(AuthController auth, String greeting) {
    if (!mounted) return;

    // The dashboard is guarded on exactly this. Checking it here turns a
    // silent bounce back to this form into something that says what happened.
    if (!auth.isAdvocate) {
      setState(() {
        _failure = 'You are verified, but the session did not load. '
            'Please try again.';
        _notice = '';
      });
      return;
    }

    Toast.success(context, greeting);
    // The lawyer app's home — the router keeps a lawyer inside it from here on.
    context.go('/lawyer');
  }

  Future<void> _createAccount() async {
    final auth = context.read<AuthController>();
    final created = await auth.signUpAdvocate(
      name: _name.text.trim(),
      email: _email.text.trim(),
      city: _city.text.trim(),
    );
    if (!mounted) return;
    if (created != null) _openDashboard(auth, 'Welcome to Justiceland.');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final busy = auth.busy;

    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: _step == _Step.phone
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: busy
                    ? null
                    : () => setState(() {
                          _step = _step == _Step.details ? _Step.otp : _Step.phone;
                          _notice = '';
                          _failure = '';
                        }),
              ),
        title: const Text('For lawyers'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _PhaseRail(step: _step),
            const SizedBox(height: 22),
            Text(_title, style: Theme.of(context).textTheme.headlineSmall),
            if (_subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                _subtitle!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.ink.withValues(alpha: 0.6)),
              ),
            ],
            const SizedBox(height: 22),
            if (_step == _Step.phone) _phoneField(),
            if (_step == _Step.otp) _otpBlock(busy),
            if (_step == _Step.details) _detailsFields(),
            if (auth.error != null) ...[
              const SizedBox(height: 14),
              NoticeBanner(tone: ChipTone.danger, message: auth.error!),
            ] else if (_failure.isNotEmpty) ...[
              const SizedBox(height: 14),
              NoticeBanner(tone: ChipTone.danger, message: _failure),
            ] else if (_notice.isNotEmpty && _step == _Step.otp) ...[
              const SizedBox(height: 14),
              NoticeBanner(tone: ChipTone.success, message: _notice),
            ],
            const SizedBox(height: 22),
            PrimaryButton(
              label: _cta,
              busy: busy,
              onPressed: _canSubmit && !busy ? _submit : null,
            ),
            if (_step == _Step.phone) ...[
              const SizedBox(height: 18),
              Text(
                'The same number registers you and signs you in — we work out '
                'which.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.ink.withValues(alpha: 0.45)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _title => switch (_step) {
        _Step.phone => widget.intent == AdvocateAuthIntent.login
            ? 'Log in'
            : 'Register as a lawyer',
        _Step.otp => 'Enter the code',
        _Step.details => 'A few basics',
      };

  String? get _subtitle => switch (_step) {
        _Step.phone =>
          'Enter your mobile number — we will text you a code. No password to '
              'remember.',
        _Step.otp => null,
        _Step.details =>
          'Three fields and your account is live. The rest of your profile '
              'comes next, guided.',
      };

  String get _cta => switch (_step) {
        _Step.phone => 'Send code',
        _Step.otp => 'Verify',
        _Step.details => 'Create my account',
      };

  bool get _canSubmit => switch (_step) {
        _Step.phone => _phoneValid,
        _Step.otp => _code.length == _otpLength,
        _Step.details => _detailsValid,
      };

  void _submit() => switch (_step) {
        _Step.phone => _sendCode(),
        _Step.otp => _verify(),
        _Step.details => _createAccount(),
      };

  Widget _phoneField() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Mobile number'),
          const SizedBox(height: 6),
          // One control, two parts. A bare box reads as "type anything"; the
          // fixed +91 says what belongs in it and takes the country code out
          // of the lawyer's hands entirely.
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.ink.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: AppColors.ink.withValues(alpha: 0.12)),
                    ),
                  ),
                  child: Text(
                    '+91',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    maxLength: 10,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: '98765 43210',
                      counterText: '',
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _otpBlock(bool busy) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.ink.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Sent to +91 ${_phone.text.trim()}',
                      style: const TextStyle(fontSize: 13)),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            _step = _Step.phone;
                            _notice = '';
                          }),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_otpLength, (i) => _codeBox(i)),
          ),
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              onPressed: (_resendIn > 0 || busy) ? null : () => _sendCode(resend: true),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(_resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend code'),
            ),
          ),
        ],
      );

  Widget _codeBox(int i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          width: 56,
          height: 60,
          child: TextField(
            controller: _codeFields[i],
            focusNode: _codeNodes[i],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: _codeFields[i].text.isEmpty
                  ? AppColors.surface
                  : AppColors.primary.withValues(alpha: 0.05),
            ),
            onChanged: (v) {
              setState(() {});
              if (v.isNotEmpty && i < _otpLength - 1) {
                _codeNodes[i + 1].requestFocus();
              }
              if (v.isEmpty && i > 0) _codeNodes[i - 1].requestFocus();
              // Submit as soon as the last box is filled — the length is the
              // whole test, since an empty box contributes nothing to the join.
              if (_code.length == _otpLength) _verify();
            },
          ),
        ),
      );

  Widget _detailsFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NoticeBanner(
            tone: ChipTone.success,
            message: '+91 ${_phone.text.trim()} verified — this is the number '
                'clients will reach you on.',
          ),
          const SizedBox(height: 18),
          const _FieldLabel('Full name'),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Adv. Your Name'),
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Email address'),
          const SizedBox(height: 6),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'you@example.com'),
          ),
          const SizedBox(height: 16),
          const _FieldLabel('City you practise in'),
          const SizedBox(height: 6),
          TextField(
            controller: _city,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Start typing your city'),
          ),
          const SizedBox(height: 6),
          Text(
            'You can add more cities later.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.ink.withValues(alpha: 0.45)),
          ),
        ],
      );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.ink.withValues(alpha: 0.75),
        ),
      );
}

/// Two dots for the steps everyone does, and a third that only appears once
/// the number turns out to be new.
///
/// It grows rather than promising three up front: until the code is checked
/// nobody knows whether this is a sign-in or a sign-up, and telling a
/// returning lawyer they have three steps left when they have none would be a
/// lie the very next tap exposes.
class _PhaseRail extends StatelessWidget {
  const _PhaseRail({required this.step});
  final _Step step;

  @override
  Widget build(BuildContext context) {
    final labels = step == _Step.details
        ? const ['Number', 'Verify', 'Details']
        : const ['Number', 'Verify'];
    final current = _Step.values.indexOf(step);

    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          _dot(i, current),
          const SizedBox(width: 8),
          Text(
            labels[i],
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: i <= current
                  ? AppColors.ink.withValues(alpha: 0.8)
                  : AppColors.ink.withValues(alpha: 0.35),
            ),
          ),
          if (i < labels.length - 1)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: i < current
                    ? AppColors.success.withValues(alpha: 0.6)
                    : AppColors.ink.withValues(alpha: 0.12),
              ),
            ),
        ],
      ],
    );
  }

  Widget _dot(int i, int current) {
    final done = i < current;
    final active = i == current;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? AppColors.success
            : active
                ? AppColors.primary
                : AppColors.ink.withValues(alpha: 0.1),
      ),
      child: done
          ? const Icon(Icons.check, size: 13, color: Colors.white)
          : Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.ink.withValues(alpha: 0.4),
              ),
            ),
    );
  }
}

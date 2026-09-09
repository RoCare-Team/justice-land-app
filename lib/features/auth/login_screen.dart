import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../state/auth_controller.dart';

/// Client sign-in: mobile number, then the code.
///
/// There is no separate sign-up. Entering a number that has never been used
/// creates the account once the code checks out — which is why nothing here
/// asks whether you are new, and why the name step appears only for an account
/// that has not got one yet.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.redirectTo});

  /// Where to go once signed in — so a booking interrupted by the sign-in wall
  /// resumes where it left off instead of dumping the user on the home screen.
  final String? redirectTo;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Step { phone, otp, name }

class _LoginScreenState extends State<LoginScreen> {
  static const int _otpLength = 4; // set by the SMS gateway
  static const int _resendSeconds = 30;

  _Step _step = _Step.phone;

  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final List<TextEditingController> _digits =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _digitFocus = List.generate(_otpLength, (_) => FocusNode());

  String _error = '';
  String _notice = '';
  bool _busy = false;
  int _resendIn = 0;
  Timer? _resendTimer;

  /// True when this sign-in created the account. Kept so the final screen can
  /// welcome a new client rather than greeting a returning one.
  bool _wasCreated = false;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _nameController.dispose();
    for (final c in _digits) {
      c.dispose();
    }
    for (final f in _digitFocus) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _digits.map((c) => c.text).join();

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _resendSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _sendOtp({bool resend = false}) async {
    final phone = Validators.digitsOnly(_phoneController.text);
    if (!Validators.isMobile(phone)) {
      setState(() => _error = 'Enter a valid 10-digit mobile number.');
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
      _notice = '';
    });

    final auth = context.read<AuthController>();
    final ok = await auth.sendOtp(phone);

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _step = _Step.otp;
        _notice = resend ? 'A new code is on its way.' : 'Code sent to +91 $phone';
      } else {
        _error = auth.error ?? 'Could not send the code. Please try again.';
      }
    });

    if (ok) {
      _startResendCountdown();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (mounted) _digitFocus.first.requestFocus();
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otp;
    if (code.length < _otpLength) {
      setState(() => _error = 'Enter the $_otpLength-digit code.');
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });

    final auth = context.read<AuthController>();
    final result = await auth.verifyOtp(
      phone: Validators.digitsOnly(_phoneController.text),
      otp: code,
    );

    if (!mounted) return;

    if (result == null) {
      setState(() {
        _busy = false;
        _error = auth.error ?? 'Verification failed.';
        for (final c in _digits) {
          c.clear();
        }
      });
      _digitFocus.first.requestFocus();
      return;
    }

    _wasCreated = result.created;
    _resendTimer?.cancel();

    // Signed in either way. A name is asked for only when we have none — the
    // account already exists at this point, so skipping is safe.
    if (result.needsName) {
      setState(() {
        _busy = false;
        _step = _Step.name;
        _notice = '';
      });
      return;
    }

    _finish();
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Enter your name so lawyers know who they are speaking to.');
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });

    final ok = await context.read<AuthController>().setName(name);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _busy = false;
        _error = context.read<AuthController>().error ?? 'Could not save your name.';
      });
      return;
    }
    _finish();
  }

  void _finish() {
    if (!mounted) return;
    Toast.success(
      context,
      _wasCreated ? 'Welcome to Justiceland.' : 'Signed in.',
    );
    final target = widget.redirectTo;
    if (target != null && target.isNotEmpty) {
      context.go(target);
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_step == _Step.otp) {
              setState(() {
                _step = _Step.phone;
                _error = '';
                _notice = '';
              });
              return;
            }
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 26),
              switch (_step) {
                _Step.phone => _phoneStep(),
                _Step.otp => _otpStep(),
                _Step.name => _nameStep(),
              },
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                NoticeBanner(
                  message: _error,
                  tone: ChipTone.danger,
                  icon: Icons.error_outline_rounded,
                ),
              ],
              if (_notice.isNotEmpty && _error.isEmpty) ...[
                const SizedBox(height: 16),
                NoticeBanner(message: _notice, tone: ChipTone.info),
              ],
              const SizedBox(height: 28),
              if (_step == _Step.phone) _advocateSwitch(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final (title, subtitle) = switch (_step) {
      _Step.phone => (
          'Talk to a verified lawyer',
          'Enter your mobile number. We will send you a code — no password to remember.',
        ),
      _Step.otp => (
          'Verify your number',
          'Code sent to +91 ${Validators.digitsOnly(_phoneController.text)}',
        ),
      _Step.name => (
          'What should we call you?',
          'Lawyers see this name when you book. You can stay anonymous later from your account.',
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 52,
          width: 52,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            switch (_step) {
              _Step.phone => Icons.phone_iphone_rounded,
              _Step.otp => Icons.password_rounded,
              _Step.name => Icons.person_outline_rounded,
            },
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 18),
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.inkMuted),
        ),
      ],
    );
  }

  Widget _phoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _sendOtp(),
          decoration: const InputDecoration(
            labelText: 'Mobile number',
            hintText: '98765 43210',
            counterText: '',
            prefixText: '+91  ',
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Send code',
          busy: _busy,
          onPressed: _sendOtp,
          icon: Icons.arrow_forward_rounded,
        ),
      ],
    );
  }

  Widget _otpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(_otpLength, (i) {
            return SizedBox(
              width: 58,
              child: TextField(
                controller: _digits[i],
                focusNode: _digitFocus[i],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(counterText: ''),
                onChanged: (value) {
                  if (value.isNotEmpty && i < _otpLength - 1) {
                    _digitFocus[i + 1].requestFocus();
                  }
                  if (value.isEmpty && i > 0) {
                    _digitFocus[i - 1].requestFocus();
                  }
                  // Auto-submit once every box is filled — one less tap on a
                  // screen where the keyboard covers the button.
                  if (_otp.length == _otpLength) _verifyOtp();
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 20),
        PrimaryButton(label: 'Verify', busy: _busy, onPressed: _verifyOtp),
        const SizedBox(height: 12),
        Center(
          child: _resendIn > 0
              ? Text(
                  'Resend in ${_resendIn}s',
                  style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                )
              : TextButton.icon(
                  onPressed: _busy ? null : () => _sendOtp(resend: true),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Resend code'),
                ),
        ),
      ],
    );
  }

  Widget _nameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _saveName(),
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'e.g. Rahul Sharma',
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Continue', busy: _busy, onPressed: _saveName),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _finish,
            child: const Text('Skip for now'),
          ),
        ),
      ],
    );
  }

  Widget _advocateSwitch() {
    return Container(
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
              const Icon(Icons.gavel_rounded, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text('Are you a lawyer?', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Lawyers sign in with the email and password used at registration.',
            style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.45),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.push('/advocate/login'),
                  child: const Text('Lawyer sign in'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.push('/advocate/register'),
                  child: const Text('Register'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

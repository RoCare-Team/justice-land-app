import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/advocate.dart';
import '../../services/advocate_service.dart';
import '../../state/auth_controller.dart';

/// Sending a lawyer an enquiry — the slower path, for someone who wants a
/// callback rather than to talk right now.
///
/// Requires a signed-in session, matching the contact gate on the web profile:
/// a lawyer's inbox is not open to anonymous traffic.
class EnquirySheet extends StatefulWidget {
  const EnquirySheet({super.key, required this.advocate});

  final Advocate advocate;

  static Future<void> open(BuildContext context, {required Advocate advocate}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EnquirySheet(advocate: advocate),
    );
  }

  @override
  State<EnquirySheet> createState() => _EnquirySheetState();
}

class _EnquirySheetState extends State<EnquirySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  final _message = TextEditingController();
  DateTime? _preferredDate;

  bool _busy = false;
  bool _sent = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthController>().user;
    _name = TextEditingController(text: user?.name ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
    _email = TextEditingController(text: user?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = '';
    });

    try {
      await context.read<AdvocateService>().sendEnquiry(
            advocateId: widget.advocate.id,
            name: _name.text.trim(),
            phone: Validators.digitsOnly(_phone.text),
            email: _email.text.trim(),
            preferredDate: _preferredDate == null
                ? ''
                : '${_preferredDate!.year}-'
                    '${_preferredDate!.month.toString().padLeft(2, '0')}-'
                    '${_preferredDate!.day.toString().padLeft(2, '0')}',
            message: _message.text.trim(),
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
    if (_sent) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          child: SuccessView(
            title: 'Enquiry sent',
            message:
                '${widget.advocate.name} has your details and will get back to '
                'you. You can also start a live consultation any time.',
            primaryAction: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                      color: AppColors.ink.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Send an enquiry',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'to ${widget.advocate.name}',
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v ?? '').trim().length < 2
                      ? 'Please enter your name.'
                      : null,
                  decoration: const InputDecoration(labelText: 'Your name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: Validators.phoneLoose,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    counterText: '',
                    prefixText: '+91  ',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: now,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 90)),
                    );
                    if (picked != null) setState(() => _preferredDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Preferred date (optional)',
                      suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                    ),
                    child: Text(
                      _preferredDate == null
                          ? 'Any day'
                          : '${_preferredDate!.day}/${_preferredDate!.month}/${_preferredDate!.year}',
                      style: TextStyle(
                        fontSize: 14,
                        color: _preferredDate == null
                            ? AppColors.inkFaint
                            : AppColors.inkStrong,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _message,
                  maxLines: 4,
                  validator: Validators.enquiryMessage,
                  decoration: const InputDecoration(
                    labelText: 'Your legal matter',
                    alignLabelWithHint: true,
                    hintText: 'A sentence or two about what you need help with.',
                  ),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  NoticeBanner(
                    message: _error,
                    tone: ChipTone.danger,
                    icon: Icons.error_outline_rounded,
                  ),
                ],
                const SizedBox(height: 18),
                PrimaryButton(
                  label: 'Send enquiry',
                  busy: _busy,
                  icon: Icons.send_rounded,
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

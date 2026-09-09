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
import '../../models/advocate.dart';
import '../../services/dashboard_service.dart';
import '../../state/auth_controller.dart';

/// Editing the lawyer's own profile.
///
/// The save sends only the fields this screen actually shows. The API writes
/// what it is given and leaves the rest alone, so a partial payload cannot
/// blank out sections the screen never displayed — which is exactly what a
/// full-object PUT built from a half-loaded model would do.
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
  final List<String> _practiceCities = [];

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
      setState(() {
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
                _field(
                  _about,
                  'About',
                  lines: 5,
                  help: 'At least 40 characters. The first thing a client reads.',
                ),
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
                DropdownButtonFormField<String>(
                  value: _state.isEmpty ? null : _state,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'State'),
                  items: [
                    for (final s in RefData.states)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: (v) => setState(() {
                    _state = v ?? '';
                    _city = '';
                    _practiceCities
                        .removeWhere((c) => !RefData.citiesIn(_state).contains(c));
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _city.isEmpty ? null : _city,
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
            icon: Icons.gavel_rounded,
            child: ChipWrap(
              children: [
                for (final s in RefData.serviceNames)
                  SelectableChip(
                    label: s,
                    selected: _services.contains(s),
                    onTap: () => setState(() => _services.contains(s)
                        ? _services.remove(s)
                        : _services.add(s)),
                  ),
              ],
            ),
          ),
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
            subtitle: 'Besides your base city — clients searching those cities find you.',
            icon: Icons.location_city_rounded,
            child: ChipWrap(
              children: [
                for (final c in RefData.citiesIn(_state))
                  SelectableChip(
                    label: c,
                    selected: _practiceCities.contains(c),
                    onTap: () => setState(() => _practiceCities.contains(c)
                        ? _practiceCities.remove(c)
                        : _practiceCities.add(c)),
                  ),
              ],
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

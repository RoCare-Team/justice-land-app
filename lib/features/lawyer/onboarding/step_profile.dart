import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import '../city_picker.dart';
import 'onboarding_controller.dart';
import 'onboarding_shell.dart';
import 'pick_or_upgrade.dart';

const _titleSuggestions = [
  'Advocate',
  'Senior Advocate',
  'Corporate Lawyer',
  'Criminal Lawyer',
  'Family Lawyer',
];

/// Step 3 — how the lawyer appears to clients: photo, name, title, experience,
/// and where they practise. The PIN code names the base city and state, so those
/// are never typed; further cities are picked from one-tap suggestions or search.
class StepProfile extends StatefulWidget {
  const StepProfile({super.key});

  @override
  State<StepProfile> createState() => _StepProfileState();
}

class _StepProfileState extends State<StepProfile> {
  /// Adding a city past the plan's allowance opens the plans right here; paying
  /// lifts the limit and the city is added.
  void _addCity(OnboardingController c, String city) => pickOrUpgrade(
        context,
        c,
        pick: () => c.toggleCity(city),
        reason: () => c.cityUpgradeReason(city),
      );

  /// What the plan covers, so the city limit is never a surprise.
  String _cityNote(OnboardingController c) {
    final n = c.currentPlan?.cities;
    if (c.currentPlan == null) return 'Clients searching these cities can find you.';
    final covers = n == null ? 'any number of other cities' : '$n other ${n == 1 ? 'city' : 'cities'}';
    return 'Your ${c.currentPlan!.name} plan covers $covers. Add more and you can upgrade right here.';
  }

  Future<void> _pickPhoto(OnboardingController c) async {
    final XFile? file;
    try {
      // Small on purpose: the photo is stored inside the profile itself, and a
      // 512px JPEG is plenty for an avatar and a profile header.
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 82,
      );
    } catch (_) {
      if (mounted) Toast.error(context, 'Could not open your photos. Check the app\'s photo permission.');
      return;
    }
    if (file == null) return;
    c.setPhoto(await file.readAsBytes());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OnboardingController>();

    return OnboardingShell(
      step: 2,
      title: 'Professional Profile',
      subtitle: 'Help clients know you better',
      onBack: c.canGoBack ? c.back : null,
      headerAction: const OnbLaterButton(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          OnbCard(
            title: 'Profile Photo',
            children: [
              Center(child: _PhotoPicker(controller: c, onTap: () => _pickPhoto(c))),
            ],
          ),
          OnbCard(
            title: 'Basic Details',
            children: [
              OnbField(
                label: 'Full Name *',
                controller: c.fullName,
                hint: 'e.g., Adv. Priya Sharma',
                textCapitalization: TextCapitalization.words,
              ),
              OnbField(
                label: 'Email *',
                controller: c.email,
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
              ),
              OnbField(
                label: 'Professional Title *',
                controller: c.title,
                hint: 'e.g., Senior Advocate, Corporate Lawyer',
                textCapitalization: TextCapitalization.words,
                padBottom: 8,
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    for (final t in _titleSuggestions)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SelectableChip(
                          label: t,
                          selected: c.title.text.trim() == t,
                          onTap: () => c.title.text = t,
                        ),
                      ),
                  ],
                ),
              ),
              OnbField(
                label: 'Years of Experience *',
                controller: c.experience,
                hint: 'e.g., 12',
                keyboardType: TextInputType.number,
                digitsOnly: true,
                maxLength: 2,
              ),
              OnbField(
                label: 'Pincode *',
                controller: c.pincode,
                hint: 'e.g., 122001',
                keyboardType: TextInputType.number,
                digitsOnly: true,
                maxLength: 6,
                suffix: c.lookingUp
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
                      )
                    : c.pincodeOk
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
                        : null,
                helper: c.lookingUp
                    ? 'Finding your city…'
                    : c.pincodeNote.isNotEmpty
                        ? c.pincodeNote
                        : 'We use this to place you in the right city.',
                helperColor: c.pincodeOk
                    ? AppColors.success
                    : c.pincodeNote.isNotEmpty
                        ? AppColors.danger
                        : null,
                padBottom: 0,
              ),
            ],
          ),
          OnbCard(
            title: 'Practice in',
            subtitle: _cityNote(c),
            children: [
              CityPicker(
                options: [for (final city in c.cityOptions) city.name],
                selected: c.cities,
                baseCity: c.baseCity,
                onAdd: (city) => _addCity(c, city),
                onRemove: c.toggleCity,
              ),
            ],
          ),
          OnbMessages(controller: c),
        ],
      ),
      primaryLabel: 'Continue',
      busy: c.saving,
      onPrimary: c.canContinueProfile ? c.continueProfile : null,
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({required this.controller, required this.onTap});

  final OnboardingController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final hasPhoto = c.photoBytes != null || c.existingPhoto.isNotEmpty;

    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 108,
                width: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.07),
                  border: Border.all(color: AppColors.border, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: c.photoBytes != null
                    ? Image.memory(c.photoBytes!, fit: BoxFit.cover)
                    : c.existingPhoto.isNotEmpty
                        ? Avatar(name: c.fullName.text, photo: c.existingPhoto, size: 108)
                        : Icon(Icons.photo_camera_outlined, size: 38, color: AppColors.inkFaint),
              ),
              Positioned(
                right: -2,
                bottom: 2,
                child: Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(Icons.photo_camera_rounded, size: 17, color: AppColors.primaryDark),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          hasPhoto ? 'Tap to change photo' : 'Upload a professional photo',
          style: TextStyle(fontSize: 14, color: AppColors.inkMuted),
        ),
      ],
    );
  }
}

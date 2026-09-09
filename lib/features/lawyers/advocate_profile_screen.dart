import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_exception.dart';
import '../../core/config/consultation_slots.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/advocate.dart';
import '../../models/consultation.dart';
import '../../services/advocate_service.dart';
import '../../state/auth_controller.dart';
import 'booking_sheet.dart';
import 'enquiry_sheet.dart';

/// A lawyer's public profile, with the live consultation bar pinned at the
/// bottom — the one thing a visitor came here to do.
class AdvocateProfileScreen extends StatefulWidget {
  const AdvocateProfileScreen({super.key, required this.profilePath});

  /// `advocate-manoj-sharma-jusld04`, or the bare Justiceland ID.
  final String profilePath;

  @override
  State<AdvocateProfileScreen> createState() => _AdvocateProfileScreenState();
}

class _AdvocateProfileScreenState extends State<AdvocateProfileScreen> {
  Advocate? _advocate;
  bool? _online;
  bool _loading = true;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = context.read<AdvocateService>();
      final advocate = await service.profile(widget.profilePath);
      if (!mounted) return;
      setState(() {
        _advocate = advocate;
        _loading = false;
      });

      // Presence separately — it is the one thing that cannot ride along with
      // a cached profile without going stale.
      final online = await service.onlineAmong([advocate.id]);
      if (!mounted) return;
      setState(() => _online = online.contains(advocate.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _requireSignIn(VoidCallback then) {
    final auth = context.read<AuthController>();
    if (auth.isUser) {
      then();
      return;
    }
    if (auth.isAdvocate) {
      Toast.show(context, 'Lawyers cannot book consultations.');
      return;
    }
    context.push('/login?redirect=/lawyers/${widget.profilePath}');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lawyer')),
        body: const LoadingView(label: 'Loading profile…'),
      );
    }

    final error = _error;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lawyer')),
        body: error.isNotFound
            ? const EmptyView(
                icon: Icons.person_off_rounded,
                title: 'Lawyer not found',
                message: 'This profile may have been removed, or is awaiting approval.',
              )
            : ErrorView(
                message: error.message,
                isNetwork: error.isNetwork,
                onRetry: _load,
              ),
      );
    }

    final advocate = _advocate!;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            _cover(advocate),
            SliverToBoxAdapter(child: _header(advocate)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              sliver: SliverList.list(
                children: [
                  _quickFacts(advocate),
                  const SizedBox(height: 12),
                  if (advocate.about.isNotEmpty) ...[
                    SectionCard(
                      title: 'About',
                      icon: Icons.person_outline_rounded,
                      child: Text(
                        advocate.about,
                        style: const TextStyle(fontSize: 14, height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (advocate.specializations.isNotEmpty) ...[
                    SectionCard(
                      title: 'Practises in',
                      icon: Icons.gavel_rounded,
                      child: ChipWrap(
                        children: [
                          for (final s in advocate.specializations)
                            Tag(label: s, tone: AppColors.accent),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (advocate.courts.isNotEmpty) ...[
                    SectionCard(
                      title: 'Courts',
                      icon: Icons.account_balance_rounded,
                      child: ChipWrap(
                        children: [for (final c in advocate.courts) Tag(label: c)],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (advocate.practiceCities.isNotEmpty) ...[
                    SectionCard(
                      title: 'Also works in',
                      icon: Icons.location_city_rounded,
                      child: ChipWrap(
                        children: [
                          for (final c in advocate.practiceCities)
                            Tag(label: c, tone: AppColors.accent),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _ratesCard(advocate),
                  const SizedBox(height: 12),
                  if (!advocate.office.isEmpty) ...[
                    SectionCard(
                      title: 'Office',
                      icon: Icons.business_rounded,
                      child: Column(
                        children: [
                          DetailRow(label: 'Name', value: advocate.office.name),
                          DetailRow(label: 'Address', value: advocate.office.fullAddress),
                          for (final t in advocate.officeTiming)
                            DetailRow(label: t.day, value: t.hours),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (advocate.education.isNotEmpty)
                    _credentials('Education', Icons.school_rounded, advocate.education),
                  if (advocate.certificates.isNotEmpty)
                    _credentials('Certificates', Icons.workspace_premium_rounded,
                        advocate.certificates),
                  if (advocate.awards.isNotEmpty)
                    _credentials('Awards', Icons.emoji_events_rounded, advocate.awards),
                  if (advocate.gallery.isNotEmpty) ...[
                    _gallery(advocate),
                    const SizedBox(height: 12),
                  ],
                  _reviews(advocate),
                  const SizedBox(height: 12),
                  if (advocate.faqs.isNotEmpty) _faqs(advocate),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _actionBar(advocate),
    );
  }

  Widget _cover(Advocate advocate) {
    final cover = Avatar.resolveUrl(advocate.coverImage);
    return SliverAppBar(
      expandedHeight: cover.isEmpty ? 0 : 180,
      pinned: true,
      backgroundColor: AppColors.surface,
      title: Text(advocate.name, style: const TextStyle(fontSize: 16)),
      flexibleSpace: cover.isEmpty
          ? null
          : FlexibleSpaceBar(
              background: RemoteImage(
                source: cover,
                fit: BoxFit.cover,
                fallback: Container(color: AppColors.muted),
              ),
            ),
    );
  }

  Widget _header(Advocate advocate) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(
                name: advocate.name,
                photo: advocate.photo,
                size: 74,
                online: _online,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            advocate.name,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        if (advocate.verified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified_rounded,
                              size: 20, color: AppColors.primary),
                        ],
                      ],
                    ),
                    if (advocate.tagline.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        advocate.tagline,
                        style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (advocate.reviews > 0)
                          RatingStars(
                            rating: advocate.rating,
                            reviews: advocate.reviews,
                            size: 15,
                          )
                        else
                          Text(
                            'No reviews yet',
                            style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
                          ),
                        if (advocate.legalCareId.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.ink.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              advocate.legalCareId,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_online != null) ...[
            const SizedBox(height: 14),
            StatusChip(
              label: _online! ? 'Online now' : 'Currently offline',
              tone: _online! ? ChipTone.success : ChipTone.neutral,
              icon: Icons.circle,
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickFacts(Advocate advocate) {
    final facts = <(IconData, String, String)>[
      (Icons.location_on_outlined, 'Location',
          [advocate.city, advocate.state].where((s) => s.isNotEmpty).join(', ')),
      (Icons.work_outline_rounded, 'Experience', Fmt.experience(advocate.experience)),
      if (advocate.barCouncilNumber.isNotEmpty)
        (Icons.badge_outlined, 'Bar Council No.', advocate.barCouncilNumber),
      if (advocate.languages.isNotEmpty)
        (Icons.translate_rounded, 'Languages', advocate.languages.join(', ')),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (final (icon, label, value) in facts)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: AppColors.inkFaint),
                    const SizedBox(width: 5),
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _ratesCard(Advocate advocate) {
    if (!advocate.offersAnyLiveChannel && advocate.consultationFee <= 0) {
      return const SizedBox.shrink();
    }
    return SectionCard(
      title: 'Consultation',
      icon: Icons.payments_outlined,
      child: Column(
        children: [
          // Every channel, always. A lawyer who has set no price of their own
          // is charged at the platform's, so there is no such thing as a
          // channel they "do not offer" — hiding one would make them look
          // unreachable when the website would happily book it.
          for (final c in kConsultationChannels)
            DetailRow(
              icon: switch (c.key) {
                'audio' => Icons.call_outlined,
                'video' => Icons.videocam_outlined,
                _ => Icons.chat_bubble_outline_rounded,
              },
              label: c.label,
              value: slotsFor(advocate.slotPrices, channel: c.key)
                  .map((s) => '${s.slot.label} ₹${s.price}')
                  .join('  ·  '),
            ),
          if (advocate.consultationFee > 0)
            DetailRow(
              icon: Icons.business_center_outlined,
              label: 'In person',
              value: Fmt.money(advocate.consultationFee),
            ),
          const SizedBox(height: 6),
          Text(
            'Live sessions bill the minutes they actually run. Nothing is '
            'charged up front.',
            style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _credentials(String title, IconData icon, List<Credential> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        title: title,
        icon: icon,
        child: Column(
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 16, color: AppColors.inkFaint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (item.subtitle.isNotEmpty)
                            Text(
                              item.subtitle,
                              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                            ),
                        ],
                      ),
                    ),
                    if (item.year.isNotEmpty)
                      Text(
                        item.year,
                        style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _gallery(Advocate advocate) {
    return SectionCard(
      title: 'Gallery',
      icon: Icons.photo_library_outlined,
      child: SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: advocate.gallery.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: RemoteImage(
              source: advocate.gallery[i],
              width: 150,
              placeholder: Container(width: 150, color: AppColors.muted),
              fallback: Container(width: 150, color: AppColors.muted),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reviews(Advocate advocate) {
    return SectionCard(
      title: 'Client reviews',
      icon: Icons.star_outline_rounded,
      trailing: TextButton(
        onPressed: () => _requireSignIn(() => _writeReview(advocate)),
        child: const Text('Write a review'),
      ),
      child: advocate.reviewsList.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'No reviews yet. Be the first to share your experience.',
                style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
              ),
            )
          : Column(
              children: [
                for (final review in advocate.reviewsList.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            RatingStars(
                              rating: review.rating.toDouble(),
                              size: 13,
                              showValue: false,
                            ),
                            const Spacer(),
                            Text(
                              review.date,
                              style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          review.text,
                          style: const TextStyle(fontSize: 13.5, height: 1.5),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '— ${review.author}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _faqs(Advocate advocate) {
    return SectionCard(
      title: 'Frequently asked',
      icon: Icons.help_outline_rounded,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        children: [
          for (final faq in advocate.faqs)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                title: Text(
                  faq.question,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      faq.answer,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionBar(Advocate advocate) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _actionButton(
              icon: Icons.mail_outline_rounded,
              label: 'Enquire',
              onTap: () => _requireSignIn(
                () => EnquirySheet.open(context, advocate: advocate),
              ),
            ),
            _actionButton(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Chat',
                highlight: true,
                onTap: () => _requireSignIn(
                  () => BookingSheet.open(
                    context,
                    advocate: advocate,
                    type: ConsultationType.chat,
                  ),
                ),
              ),
            _actionButton(
                icon: Icons.call_outlined,
                label: 'Call',
                highlight: true,
                onTap: () => _requireSignIn(
                  () => BookingSheet.open(
                    context,
                    advocate: advocate,
                    type: ConsultationType.audio,
                  ),
                ),
              ),
            _actionButton(
                icon: Icons.videocam_outlined,
                label: 'Video',
                highlight: true,
                onTap: () => _requireSignIn(
                  () => BookingSheet.open(
                    context,
                    advocate: advocate,
                    type: ConsultationType.video,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: highlight ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: highlight ? null : Border.all(color: AppColors.borderStrong),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: highlight ? Colors.white : AppColors.primary,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: highlight ? Colors.white : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _writeReview(Advocate advocate) async {
    final textController = TextEditingController();
    final nameController = TextEditingController(
      text: context.read<AuthController>().user?.name ?? '',
    );
    var rating = 5;
    var busy = false;
    String error = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Write a review',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        onPressed: () => setSheetState(() => rating = i),
                        icon: Icon(
                          i <= rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 32,
                          color: i <= rating
                              ? AppColors.accent
                              : AppColors.ink.withOpacity(0.2),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Your name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Your experience',
                    alignLabelWithHint: true,
                  ),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  NoticeBanner(message: error, tone: ChipTone.danger),
                ],
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Post review',
                  busy: busy,
                  onPressed: () async {
                    if (textController.text.trim().length < 5) {
                      setSheetState(() =>
                          error = 'Please write a short review (at least 5 characters).');
                      return;
                    }
                    setSheetState(() {
                      busy = true;
                      error = '';
                    });
                    try {
                      await context.read<AdvocateService>().submitReview(
                            legalCareId: advocate.legalCareId,
                            author: nameController.text.trim(),
                            rating: rating,
                            text: textController.text.trim(),
                          );
                      if (!sheetContext.mounted) return;
                      Navigator.of(sheetContext).pop();
                      if (mounted) {
                        Toast.success(context, 'Thanks — your review is posted.');
                        _load();
                      }
                    } on ApiException catch (e) {
                      setSheetState(() {
                        busy = false;
                        error = e.message;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    textController.dispose();
    nameController.dispose();
  }
}

/// Opens the dialer for a plain phone number, used where a lawyer publishes one.
Future<void> dialNumber(String number) async {
  final uri = Uri(scheme: 'tel', path: number.replaceAll(RegExp(r'[^\d+]'), ''));
  if (await canLaunchUrl(uri)) await launchUrl(uri);
}

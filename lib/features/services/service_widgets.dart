import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../models/marketplace.dart';

/// The pieces the catalogue screens share.
///
/// A service card looks the same on the landing page, inside a category and in
/// search results, and it did not before: three copies drifted into three
/// slightly different cards, which is how a price ends up styled one way in one
/// place and another way two taps later.

/// A heading with an optional trailing action, aligned on one baseline.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.ink.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

/// A colour per shelf, cycled from a small fixed palette.
///
/// Fixed rather than random so a category keeps the same colour between
/// launches — a grid that recolours itself on every open is one the eye cannot
/// learn, which defeats the point of colouring it.
const List<Color> _tints = [
  Color(0xFFD4A017), // gold
  Color(0xFF16A34A), // green
  Color(0xFF2563EB), // blue
  Color(0xFFDB2777), // pink
  Color(0xFF7C3AED), // violet
  Color(0xFFEA580C), // orange
];

Color categoryTint(int index) => _tints[index % _tints.length];

/// An icon for a shelf, chosen from its name.
///
/// Falls back to a neutral folder rather than guessing: a wrong icon on a
/// category is read as a fact about what is inside it.
IconData iconForCategory(String name) {
  final key = name.toLowerCase();
  if (key.contains('business') || key.contains('startup')) {
    return Icons.rocket_launch_outlined;
  }
  if (key.contains('trademark') || key.contains('ip')) {
    return Icons.verified_outlined;
  }
  if (key.contains('document')) return Icons.description_outlined;
  if (key.contains('property')) return Icons.home_work_outlined;
  if (key.contains('family')) return Icons.family_restroom_rounded;
  if (key.contains('recovery')) return Icons.currency_rupee_rounded;
  if (key.contains('consumer')) return Icons.shopping_bag_outlined;
  if (key.contains('personal')) return Icons.person_outline_rounded;
  if (key.contains('tax') || key.contains('gst')) return Icons.receipt_long_outlined;
  return Icons.folder_open_outlined;
}

/// One catalogue entry, as a wide card.
///
/// Wide rather than a two-up grid because what sells a service is its one-line
/// summary, and a cell narrow enough to fit two across truncates that line to
/// nothing useful.
class ServiceCard extends StatelessWidget {
  const ServiceCard({super.key, required this.service});

  final ServiceProduct service;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/services/${service.slug}'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.ink.withValues(alpha: 0.07)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (service.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        service.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppColors.ink.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _priceRow(),
                    if (service.turnaround.isNotEmpty ||
                        service.purchased > 0) ...[
                      const SizedBox(height: 7),
                      _footnote(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priceRow() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 7,
      runSpacing: 4,
      children: [
        Text(
          Fmt.money(service.price),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
        if (service.hasOffer) ...[
          Text(
            Fmt.money(service.mrp),
            style: TextStyle(
              fontSize: 12,
              decoration: TextDecoration.lineThrough,
              color: AppColors.ink.withValues(alpha: 0.4),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${service.discountPercent}% OFF',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.success,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Turnaround and how many have bought it, each dropped when it has nothing
  /// honest to say — a "0 purchased" on a new service sells against it.
  Widget _footnote() {
    return Row(
      children: [
        if (service.turnaround.isNotEmpty) ...[
          Icon(Icons.schedule_rounded,
              size: 13, color: AppColors.ink.withValues(alpha: 0.45)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              service.turnaround,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.ink.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
        if (service.purchased > 0) ...[
          if (service.turnaround.isNotEmpty) const SizedBox(width: 10),
          const Icon(Icons.trending_up_rounded, size: 13, color: AppColors.success),
          const SizedBox(width: 4),
          Text(
            '${service.purchased} bought',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
        ],
      ],
    );
  }

  /// The thumbnail, with the rating badged onto its corner where it does not
  /// cost a line of text. Hidden entirely when nobody has rated the service.
  Widget _thumb() {
    const size = 76.0;
    final blank = Container(
      width: size,
      height: size,
      color: AppColors.primary.withValues(alpha: 0.07),
      alignment: Alignment.center,
      child: Icon(Icons.description_outlined,
          size: 28, color: AppColors.primary.withValues(alpha: 0.5)),
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: RemoteImage(
              source: service.banner,
              width: size,
              height: size,
              placeholder: blank,
              fallback: blank,
            ),
          ),
          if (service.hasRating)
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: 0.16),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 11, color: AppColors.accent),
                    const SizedBox(width: 2),
                    Text(
                      Fmt.rating(service.rating),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

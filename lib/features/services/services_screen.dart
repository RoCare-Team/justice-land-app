import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/reference_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/states.dart';
import '../../models/marketplace.dart';
import '../../state/marketplace_controller.dart';

/// The legal-services catalogue: fixed-price work, browsable without an account.
///
/// Two different things are on this screen and they are kept visibly apart.
/// The top strip sends you to a *lawyer* — a person, billed for their time.
/// Everything below is a *service* — a known job at a known price, with no
/// lawyer chosen at the point of sale. Blurring the two would leave a client
/// expecting a consultation to have bought an incorporation.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key, this.initialCategory = ''});

  final String initialCategory;

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = context.read<MarketplaceController>();
      if (widget.initialCategory.isNotEmpty) {
        await controller.setCategory(widget.initialCategory);
      } else {
        await controller.load();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final market = context.watch<MarketplaceController>();

    return Scaffold(
      backgroundColor: AppColors.muted,
      body: RefreshIndicator(
        onRefresh: () => market.load(silent: true),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              sliver: SliverList.list(
                children: [
                  const SizedBox(height: 18),
                  _talkToLawyer(),
                  const SizedBox(height: 24),
                  _categoryChips(market),
                  const SizedBox(height: 16),
                  _catalogue(market),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The navy block, matching the home screen's — same shape, same search
  /// field position, so the two read as one app rather than two.
  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/'),
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    'Legal Services',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'My orders',
                  onPressed: () => context.push('/orders'),
                  icon: const Icon(Icons.receipt_long_rounded,
                      color: Colors.white, size: 21),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Fixed prices. No hourly billing, no surprises.',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => context.read<MarketplaceController>().search(v),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search services…',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.ink.withValues(alpha: 0.4),
                ),
                prefixIcon: Icon(Icons.search_rounded,
                    size: 20, color: AppColors.ink.withValues(alpha: 0.4)),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          context.read<MarketplaceController>().search('');
                          setState(() {});
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: _searchBorder,
                enabledBorder: _searchBorder,
                focusedBorder: _searchBorder,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  static final _searchBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  );

  /// The other half of the marketplace: reach a person, not a product.
  ///
  /// These tiles go to the lawyer directory filtered by practice area — the
  /// same listing the Find Lawyer tab shows. They are not services and do not
  /// pretend to be: no price is printed on them, because what a consultation
  /// costs depends on which lawyer you pick.
  Widget _talkToLawyer() {
    final areas = RefData.services.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(
          title: 'Talk to a Lawyer',
          subtitle: 'Pick an area and speak to someone today',
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: areas.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.82,
          ),
          itemBuilder: (context, i) {
            final area = areas[i];
            return _AreaTile(
              label: area.name,
              icon: _iconForArea(area.slug),
              tint: _tints[i % _tints.length],
              onTap: () => context.push(
                '/lawyers?service=${Uri.encodeQueryComponent(area.name)}',
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _categoryChips(MarketplaceController market) {
    if (market.categories.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(
          title: 'Ready-priced services',
          subtitle: 'Everything below is a fixed fee, GST shown before you pay',
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: market.categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final category = market.categories[i];
              final selected = market.category == category.name;
              return _FilterChip(
                label: '${category.name} (${category.count})',
                selected: selected,
                onTap: () => market.setCategory(category.name),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _catalogue(MarketplaceController market) {
    if (market.loading && market.services.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: LoadingView(label: 'Loading services…'),
      );
    }

    if (market.error != null && market.services.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: ErrorView(
          message: market.error!,
          onRetry: () => market.load(),
        ),
      );
    }

    if (market.services.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: EmptyView(
          icon: Icons.work_outline_rounded,
          title: 'Nothing here yet',
          message: 'No service matches that. Try another category or search.',
        ),
      );
    }

    return Column(
      children: [
        for (final service in market.services) ...[
          ServiceCard(service: service),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  static const List<Color> _tints = [
    Color(0xFFD4A017),
    Color(0xFF16A34A),
    Color(0xFFDB2777),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFEA580C),
  ];

  IconData _iconForArea(String slug) {
    if (slug.contains('criminal')) return Icons.gavel_rounded;
    if (slug.contains('propert') || slug.contains('real-estate')) {
      return Icons.home_work_outlined;
    }
    if (slug.contains('family') || slug.contains('divorce')) {
      return Icons.family_restroom_rounded;
    }
    if (slug.contains('corporate') || slug.contains('company')) {
      return Icons.business_center_outlined;
    }
    if (slug.contains('civil')) return Icons.balance_rounded;
    if (slug.contains('tax')) return Icons.receipt_long_outlined;
    if (slug.contains('labour') || slug.contains('employ')) {
      return Icons.badge_outlined;
    }
    if (slug.contains('consumer')) return Icons.shopping_bag_outlined;
    if (slug.contains('cyber')) return Icons.security_rounded;
    if (slug.contains('immigration')) return Icons.flight_takeoff_rounded;
    return Icons.article_outlined;
  }
}

/// One catalogue entry, as a wide card.
///
/// Wide rather than a two-up grid because the thing that sells a service is
/// its one-line summary, and a grid cell narrow enough to fit two across
/// truncates that line to nothing useful.
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
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.ink.withValues(alpha: 0.07)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(),
              const SizedBox(width: 13),
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
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Text(
                          Formatters.money(service.price),
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        if (service.hasOffer) ...[
                          const SizedBox(width: 6),
                          Text(
                            Formatters.money(service.mrp),
                            style: TextStyle(
                              fontSize: 12,
                              decoration: TextDecoration.lineThrough,
                              color: AppColors.ink.withValues(alpha: 0.4),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${service.discountPercent}% off',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Turnaround and rating share a line, and each is dropped
                    // when it has nothing to say — a "0.0 ★" on a service
                    // nobody has rated reads as a bad one.
                    if (service.turnaround.isNotEmpty || service.hasRating) ...[
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          if (service.turnaround.isNotEmpty) ...[
                            Icon(Icons.schedule_rounded,
                                size: 13,
                                color: AppColors.ink.withValues(alpha: 0.45)),
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
                          if (service.hasRating) ...[
                            const SizedBox(width: 10),
                            const Icon(Icons.star_rounded,
                                size: 14, color: AppColors.accent),
                            const SizedBox(width: 3),
                            Text(
                              Formatters.rating(service.rating),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
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

  Widget _thumb() {
    const size = 74.0;
    if (service.banner.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.description_outlined,
            size: 28, color: AppColors.primary.withValues(alpha: 0.55)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: service.banner,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(
          width: size,
          height: size,
          color: AppColors.primary.withValues(alpha: 0.07),
          child: Icon(Icons.description_outlined,
              size: 28, color: AppColors.primary.withValues(alpha: 0.55)),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
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
              color: AppColors.ink.withValues(alpha: 0.55),
            ),
          ),
        ],
      ],
    );
  }
}

class _AreaTile extends StatelessWidget {
  const _AreaTile({
    required this.label,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: tint),
              ),
              const SizedBox(height: 6),
              Text(
                label.split(' ').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.ink.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

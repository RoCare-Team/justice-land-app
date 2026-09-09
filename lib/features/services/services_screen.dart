import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/states.dart';
import '../../state/marketplace_controller.dart';
import 'service_widgets.dart';

/// The Legal Services landing: fixed-price work, browsable without an account.
///
/// A shelf-first screen rather than one long list. Someone arriving here has a
/// job in mind — "register a company", "get an agreement drafted" — and picking
/// the shelf is a faster way into forty services than scrolling past thirty of
/// them. The full list is one tap away for anyone who would rather browse.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key, this.initialCategory = ''});

  final String initialCategory;

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = context.read<MarketplaceController>();
      // Always unfiltered: this page's job is to show every shelf, and it
      // reads `allServices`, which only an unfiltered load refreshes.
      await controller.clearFilters();
      if (widget.initialCategory.isNotEmpty && mounted) {
        _openCategory(widget.initialCategory);
      }
    });
  }

  void _openCategory(String name) =>
      context.push('/services/all?category=${Uri.encodeQueryComponent(name)}');

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
            if (market.loading && market.allServices.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: LoadingView(label: 'Loading services…'),
              )
            else if (market.error != null && market.allServices.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorView(message: market.error!, onRetry: market.load),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                sliver: SliverList.list(children: _sections(market)),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(MarketplaceController market) {
    if (market.allServices.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 40),
          child: EmptyView(
            icon: Icons.workspace_premium_outlined,
            title: 'No services yet',
            message: 'Fixed-price services will appear here once they go live.',
          ),
        ),
      ];
    }

    // The most-bought first, and only a handful — this is a shortcut past the
    // categories, not a second copy of the catalogue.
    final popular = [...market.allServices]
      ..sort((a, b) => b.purchased.compareTo(a.purchased));

    return [
      if (market.categories.isNotEmpty) ...[
        const SectionHeading(
          title: 'Browse by category',
          subtitle: 'Pick the kind of work you need done',
        ),
        const SizedBox(height: 14),
        _categoryGrid(market),
        const SizedBox(height: 26),
      ],
      SectionHeading(
        title: 'Popular services',
        subtitle: 'What people order most',
        action: market.allServices.length > 4
            ? _SeeAll(onTap: () => context.push('/services/all'))
            : null,
      ),
      const SizedBox(height: 14),
      for (final service in popular.take(4)) ...[
        ServiceCard(service: service),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 6),
      _exploreAll(market.allServices.length),
      const SizedBox(height: 26),
      _talkToLawyer(),
    ];
  }

  /// The navy block, the same shape the home screen uses, so the two read as
  /// one app rather than two.
  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 22),
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
                const Expanded(
                  child: Text(
                    'Legal Services',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                _headerIcon(
                  Icons.receipt_long_rounded,
                  'My orders',
                  () => context.push('/orders'),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              'Fixed prices, GST shown before you pay.',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            // Read-only: tapping opens the full list, which is where searching
            // makes sense. A field that filtered a landing page of category
            // tiles would have nothing to filter.
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.push('/services/all?focus=1'),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded,
                        size: 20, color: AppColors.ink.withValues(alpha: 0.4)),
                    const SizedBox(width: 10),
                    Text(
                      'Search services…',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.ink.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerIcon(IconData icon, String tooltip, VoidCallback onTap) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
        ),
      );

  /// Two per row, each with the count of what is on that shelf.
  ///
  /// The count is not decoration: it is the difference between tapping into a
  /// category with eleven services and one with a single service, and knowing
  /// which is which before you tap saves the trip back.
  Widget _categoryGrid(MarketplaceController market) {
    final categories = market.categories;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (context, i) {
        final category = categories[i];
        final tint = categoryTint(i);
        return Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openCategory(category.name),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.ink.withValues(alpha: 0.07)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(iconForCategory(category.name),
                        size: 20, color: tint),
                  ),
                  const Spacer(),
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Fmt.pluralize(category.count, 'service'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.ink.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _exploreAll(int count) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/services/all'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.grid_view_rounded, size: 18, color: Colors.white),
              const SizedBox(width: 10),
              const Text(
                'Explore all services',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The other half of the marketplace, kept clearly apart from it.
  ///
  /// A service is a known job at a known price. A consultation is time with a
  /// particular lawyer, and what it costs depends on which lawyer — which is
  /// why no price appears on this card and why it is a single strip rather
  /// than a grid competing with the catalogue above.
  Widget _talkToLawyer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_rounded, size: 19, color: AppColors.warning),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Not sure what you need?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Talk to a verified lawyer first. They will tell you which service '
            'fits your matter — or whether you need one at all.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.ink.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.go('/lawyers'),
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: const Text('Talk to a lawyer'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('See all', style: TextStyle(fontSize: 13)),
    );
  }
}

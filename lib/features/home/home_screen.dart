import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/reference_data.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/account.dart';
import '../../models/advocate.dart';
import '../../services/advocate_service.dart';
import '../../services/content_service.dart';
import '../../state/auth_controller.dart';
import '../../state/location_controller.dart';
import '../lawyers/advocate_card.dart';
import '../queries/ask_lawyer_sheet.dart';
import '../voice/voice_search_sheet.dart';
import 'location_sheet.dart';

/// The home screen — the same sections the website's homepage has, in the
/// order that matters on a phone: search, practice areas, lawyers near you,
/// then the platform's own reviews.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Advocate> _featured = [];
  NearbyAdvocates _nearby = NearbyAdvocates.empty;

  /// The best-rated lawyers in the country, whatever the visitor's city.
  ///
  /// A separate band from [_featured] on purpose. Those two answer different
  /// questions — "who is near me" and "who is the best" — and merging them
  /// meant that in a city with no lawyers yet the local heading quietly became
  /// a national list, so the reader was told they were seeing Gurgaon.
  List<Advocate> _topRated = [];
  List<Testimonial> _testimonials = [];

  /// The practice areas, from the server. Empty until they land, and the grid
  /// falls back to the list bundled with the app rather than showing a gap —
  /// they are the same twelve either way.
  List<LegalService> _services = [];

  Set<String> _online = {};
  bool _loading = true;
  ApiException? _error;

  /// What the visitor typed in "What is your legal matter?".
  final TextEditingController _matter = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _matter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final advocates = context.read<AdvocateService>();
    final content = context.read<ContentService>();
    final location = context.read<LocationController>();

    try {
      // With a location, this is the same call the website's home page makes:
      // the visitor's own city if anyone practises there, and a stated fallback
      // if not. Without one it is simply the top of the directory.
      //
      // Note it is not a plain city filter. Someone in Gurugram whose city has
      // no lawyers yet used to get an empty band and a "clear your location"
      // button — a dead end offered instead of the lawyers half an hour away.
      final NearbyAdvocates result;
      if (location.hasCity || location.hasLocation) {
        result = await advocates.nearby(
          city: location.city,
          lat: location.lat,
          lng: location.lng,
          limit: 8,
        );
      } else {
        final page = await advocates.search(const AdvocateQuery(perPage: 8));
        result = NearbyAdvocates(
          scope: 'all',
          place: '',
          total: page.total,
          advocates: page.advocates,
        );
      }

      if (!mounted) return;
      setState(() {
        _nearby = result;
        _featured = result.advocates;
        _loading = false;
      });

      // These three are extras: failing to load any of them should not blank
      // the page. The practice-area grid already has a list to fall back on,
      // the green dots simply stay off, and the reviews band stays hidden.
      advocates
          .onlineAmong(result.advocates.map((a) => a.id).toList())
          .then((online) {
        if (mounted) setState(() => _online = online);
      }).catchError((Object _) {});

      content.testimonials().then((list) {
        if (mounted) setState(() => _testimonials = list);
      }).catchError((Object _) {});

      content.services().then((list) {
        if (mounted) setState(() => _services = list);
      }).catchError((Object _) {});

      // Also an extra: the local band is the page, and this one is a bonus
      // below it that must not be able to blank anything if it fails.
      advocates
          .search(const AdvocateQuery(sort: 'rating', perPage: 5))
          .then((page) {
        if (!mounted) return;
        setState(() {
          // Anyone already shown above is dropped, so the same lawyer does not
          // appear twice on one screen under two different headings.
          final shown = result.advocates.map((a) => a.id).toSet();
          _topRated =
              page.advocates.where((a) => !shown.contains(a.id)).toList();
        });
        advocates
            .onlineAmong(_topRated.map((a) => a.id).toList())
            .then((online) {
          if (mounted) setState(() => _online = {..._online, ...online});
        }).catchError((Object _) {});
      }).catchError((Object _) {});
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final location = context.watch<LocationController>();

    return Scaffold(
      backgroundColor: AppColors.muted,
      body: HeaderStatusBand(
        child: RefreshIndicator(
          onRefresh: _load,
          // Drop the spinner clear of the band, or it turns beneath it.
          edgeOffset: MediaQuery.paddingOf(context).top,
          child: CustomScrollView(
          slivers: [
            // The header and the strip are one sliver because the strip is
            // lifted onto the header's seam, and a viewport paints its first
            // sliver *over* the ones after it — which is what let the navy
            // panel cut the top off the category icons. As siblings in one box
            // the later child paints last, the way the design reads.
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _navyHeader(location),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _categoryStrip(),
                  ),
                ],
              ),
            ),

            // Order is the whole point of this screen. A client opens it to
            // find a lawyer, so the lawyers sit directly under the category
            // strip — not third, after a hero panel and a grid of tiles.
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, bottomGutter(context)),
              sliver: SliverList.list(
                children: [
                  const SizedBox(height: 8),
                  _featuredSection(location),
                  const SizedBox(height: 20),
                  // For someone who does not know which lawyer they need: say
                  // what happened, and a lawyer calls them. No account needed.
                  const AskLawyerBanner(),
                  const SizedBox(height: 26),
                  if (_topRated.isNotEmpty) ...[
                    _topRatedSection(),
                    const SizedBox(height: 26),
                  ],
                  if (_testimonials.isNotEmpty) ...[
                    _testimonialsSection(),
                    const SizedBox(height: 20),
                  ],
                  _registerCta(auth),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// The navy block at the top: greeting, the promise, and the search field.
  ///
  /// The search sits *inside* the panel rather than below it. That is not
  /// decoration — it puts the one control on the screen against the darkest
  /// thing on it, where the eye lands first, and it costs no extra height
  /// because the panel was going to be there anyway.
  Widget _navyHeader(LocationController location) {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$part \u{1F44B}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Need Legal Help?',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Talk to verified lawyers instantly.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                _headerIcon(
                  Icons.notifications_none_rounded,
                  () => context.push('/consultations'),
                ),
                const SizedBox(width: 6),
                _headerAvatar(),
              ],
            ),
            const SizedBox(height: 16),
            _searchField(),
            const SizedBox(height: 10),
            _voiceRow(),
            const SizedBox(height: 10),
            // Where the lawyers below are being drawn from. Tappable, because
            // a client whose city is wrong needs to fix it here, not hunt for
            // a setting.
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => LocationSheet.open(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on_rounded,
                        size: 14, color: Colors.white.withValues(alpha: 0.75)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        location.label.isEmpty
                            ? 'Set your location'
                            : location.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16, color: Colors.white.withValues(alpha: 0.75)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The spoken way in, under the search box.
  ///
  /// The search box asks which practice area you want, which is a question
  /// someone with an unpaid salary cannot answer — they know what happened to
  /// them, not what it is called. This asks them to say it instead, in
  /// whichever language they think in, and does the naming on the server.
  Widget _voiceRow() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => VoiceSearchSheet.open(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_rounded, size: 17, color: AppColors.primaryDark),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Apni problem boliye',
                    style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white,
                    ),
                  ),
                  Text(
                    'Hindi me bhi — lawyer khud dhoond denge',
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: Colors.white.withValues(alpha: 0.8)),
          ],
        ),
      ),
    );
  }

  Widget _headerIcon(IconData icon, VoidCallback onTap) => InkWell(
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
      );

  Widget _headerAvatar() {
    final auth = context.read<AuthController>();
    // Whichever of the two is signed in, if either. The controller keeps the
    // client and the lawyer in separate fields rather than one name, so the
    // fallback chain is the app's own and not a guess.
    final name = auth.user?.displayName ?? auth.advocate?.name ?? '';
    final initial = name.trim().isEmpty ? '' : name.trim()[0].toUpperCase();

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push('/profile'),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: initial.isEmpty
            ? const Icon(Icons.person_outline_rounded,
                size: 19, color: Colors.white)
            : Text(
                initial,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _matter,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _findLawyers(),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search lawyers or legal issues...',
        hintStyle: TextStyle(
          fontSize: 13.5,
          color: AppColors.ink.withValues(alpha: 0.4),
        ),
        prefixIcon: Icon(Icons.search_rounded,
            size: 20, color: AppColors.ink.withValues(alpha: 0.4)),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  void _findLawyers() {
    final matter = _matter.text.trim();
    final city = context.read<LocationController>().city;
    final parts = <String>[
      if (matter.isNotEmpty) 'q=${Uri.encodeQueryComponent(matter)}',
      if (city.isNotEmpty) 'city=${Uri.encodeQueryComponent(city)}',
    ];
    context.go(parts.isEmpty ? '/lawyers' : '/lawyers?${parts.join('&')}');
  }

  /// The practice areas, as one scrolling strip of small icons.
  ///
  /// Names and slugs come from `/api/services`, so an area added on the web
  /// appears here without an app release. It is a strip rather than the grid
  /// it used to be for one reason: eight tiles four across cost roughly two
  /// hundred vertical pixels, and every one of them pushed the lawyers — the
  /// thing this screen exists to show — further down the page.
  Widget _categoryStrip() {
    final services = _services.isNotEmpty
        ? [for (final s in _services) (name: s.name, slug: s.slug)]
        : [for (final g in RefData.services) (name: g.name, slug: g.slug)];

    final showMore = services.length > 8;
    final count = showMore ? 9 : services.length;

    return Transform.translate(
      // Lifted onto the seam of the navy panel, so the strip reads as part of
      // the header rather than as the first item of the list below it.
      offset: const Offset(0, -14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // 14 each side and 14 between, so the gap at the card's edge
            // matches the gap between tiles. At 12-and-6 the first tile sat
            // twice as far from the edge as its neighbour sat from it, which
            // is what made the row look unevenly spaced.
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: count,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              // The last tile is "More" rather than a ninth area — a strip
              // that simply stops leaves the reader unsure whether that was
              // all of them.
              if (showMore && i == 8) {
                return _categoryChip(
                  icon: Icons.more_horiz_rounded,
                  label: 'More',
                  tint: const Color(0xFF64748B),
                  onTap: () => context.go('/lawyers'),
                );
              }
              final service = services[i];
              return _categoryChip(
                icon: _iconForSlug(service.slug),
                label: _shortArea(service.name),
                tint: _tints[i % _tints.length],
                onTap: () => context.go(
                  '/lawyers?service=${Uri.encodeQueryComponent(service.name)}',
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _categoryChip({
    required IconData icon,
    required String label,
    required Color tint,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      // Wide enough for "Corporate" and "Property" at this size. At 64 they
      // ellipsised to "Corpora…", which reads as a truncation bug rather than
      // a category.
      width: 72,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 21, color: tint),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.15,
                fontWeight: FontWeight.w600,
                color: AppColors.ink.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A colour per practice area, cycled from a small fixed palette.
  ///
  /// Fixed rather than random so a category keeps the same colour between
  /// launches — a strip that recolours itself on every open is one the eye
  /// cannot learn, which defeats the point of having icons at all.
  static const List<Color> _tints = [
    Color(0xFFD4A017), // gold
    Color(0xFF16A34A), // green
    Color(0xFFDB2777), // pink
    Color(0xFF2563EB), // blue
    Color(0xFF7C3AED), // violet
    Color(0xFFEA580C), // orange
  ];

  /// A Material icon per practice area.
  ///
  /// The icon does not travel from the server — on the website a category
  /// carries a React component — so each is matched by slug here, and anything
  /// unrecognised falls back to the gavel rather than to a blank circle.
  /// A practice area's name, trimmed of the word that adds nothing.
  ///
  /// "Criminal Law" and "Family Law" are Criminal and Family on a 72px tile —
  /// every area is a law, so the word carries no information here. Anything
  /// that is not "<something> Law" keeps its full name across two lines rather
  /// than being cut to its first word.
  String _shortArea(String name) {
    final trimmed = name.trim();
    if (trimmed.toLowerCase().endsWith(' law')) {
      return trimmed.substring(0, trimmed.length - 4);
    }
    return trimmed;
  }

  IconData _iconForSlug(String slug) {
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
    if (slug.contains('labour') || slug.contains('employment')) {
      return Icons.engineering_outlined;
    }
    if (slug.contains('consumer')) return Icons.shopping_bag_outlined;
    if (slug.contains('constitution')) return Icons.account_balance_outlined;
    if (slug.contains('immigration')) return Icons.flight_takeoff_rounded;
    if (slug.contains('intellectual')) return Icons.lightbulb_outline_rounded;
    return Icons.gavel_rounded;
  }

  /// What to call the band, following what the server actually matched.
  ///
  /// The wording tracks `scope` exactly, the same rule the website's own band
  /// follows. A heading that says "in Gurugram" over lawyers from three states
  /// along is worse than one that never named the city: the reader believes
  /// it, calls one of them, and finds out the hard way.
  /// What the band above the list is actually showing.
  ///
  /// When the server fell back to the whole directory the heading must stop
  /// naming a place. It used to keep saying "Lawyers in Gurgaon" over a
  /// national list in one branch and drop to a bare "Verified lawyers" in
  /// another, so the reader either believed a false claim or lost the city
  /// entirely; now the heading says the country and the line under it says why.
  String _featuredTitle(LocationController location) {
    switch (_nearby.scope) {
      case 'city':
      case 'state':
        return 'Lawyers in ${_nearby.place}';
      case 'nearby':
        return location.label.isEmpty
            ? 'Lawyers near you'
            : 'Lawyers near ${location.label}';
      default:
        return location.hasCity
            ? 'Lawyers across India'
            : 'Verified lawyers';
    }
  }

  /// The best-rated in the country — the same people the Top Lawyers tab opens
  /// on, so the two agree.
  Widget _topRatedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Top lawyers',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: () => context.go('/lawyers?sort=rating'),
              child: const Text('See all'),
            ),
          ],
        ),
        Text(
          'Highest rated across India',
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.ink.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 12),
        for (final advocate in _topRated.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AdvocateCard(
              advocate: advocate,
              online: _online.isEmpty ? null : _online.contains(advocate.id),
            ),
          ),
      ],
    );
  }

  Widget _featuredSection(LocationController location) {
    // Nobody in reach, but the band still has lawyers in it — say so rather
    // than letting the visitor read a national list as a local one.
    final fellBack = _nearby.scope == 'all' &&
        (location.hasCity || location.hasLocation) &&
        _featured.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _featuredTitle(location),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: () => context.push('/lawyers'),
              child: const Text('See all'),
            ),
          ],
        ),
        if (fellBack)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Text(
              location.hasCity
                  ? 'No lawyer listed near ${location.city} yet — showing lawyers from across India'
                  : 'No lawyer listed near you yet — showing lawyers from across India',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 10),
        if (_loading)
          const SizedBox(height: 340, child: SkeletonList(count: 2, height: 150))
        else if (_error != null)
          ErrorView(
            compact: true,
            message: _error!.message,
            isNetwork: _error!.isNetwork,
            onRetry: _load,
          )
        else if (_featured.isEmpty)
          // By the time the band is empty the server has already tried the
          // city, the state, everyone within reach and then the directory
          // itself — so this is not "none near you", it is none at all, and
          // clearing the location would not produce any.
          const EmptyView(
            icon: Icons.person_search_rounded,
            title: 'No lawyers listed yet',
            message: 'Verified lawyers will appear here as they join.',
          )
        else
          for (final advocate in _featured.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AdvocateCard(
                advocate: advocate,
                online: _online.isEmpty ? null : _online.contains(advocate.id),
              ),
            ),
      ],
    );
  }

  /// Client quotes, as a carousel that admits it is one.
  ///
  /// The card width is a fraction of the screen rather than a fixed 280, so the
  /// next card always peeks past the right edge — on a narrow phone a fixed
  /// width filled the viewport exactly and the row looked like a single card
  /// that had been chopped off, which is what it was being read as.
  ///
  /// The list keeps its own horizontal padding and the section breaks out of
  /// the page's, so a card scrolling away passes under the screen edge instead
  /// of being clipped against an invisible 16px wall.
  Widget _testimonialsSection() {
    final width = MediaQuery.of(context).size.width;
    final cardWidth = (width * 0.74).clamp(240.0, 320.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What our clients say',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 3),
        Text(
          'Real feedback from people we have helped',
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.ink.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 14),
        // Negative margin cancels the page padding for this row only.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.zero,
              itemCount: _testimonials.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _testimonialCard(_testimonials[i], cardWidth),
            ),
          ),
        ),
      ],
    );
  }

  Widget _testimonialCard(Testimonial t, double width) {
    final byline = [t.role, t.city].where((s) => s.isNotEmpty).join(' · ');

    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RatingStars(rating: t.rating.toDouble(), size: 14, showValue: false),
          const SizedBox(height: 10),
          // Expanded, so the quote takes whatever is left after the fixed
          // furniture above and below rather than pushing them off the card.
          Expanded(
            child: Text(
              t.text,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          const Divider(height: 18),
          Row(
            children: [
              Avatar(name: t.name, size: 30),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (byline.isNotEmpty)
                      Text(
                        byline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.inkFaint,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _registerCta(AuthController auth) {
    if (auth.isAdvocate) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_rounded, size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(
                'Are you a lawyer?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Create a free verified profile and start receiving client '
            'consultations by chat, call and video.',
            style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Register as a lawyer',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => context.push('/advocate/register'),
          ),
        ],
      ),
    );
  }
}

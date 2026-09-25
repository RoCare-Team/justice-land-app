import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/advocate.dart';
import '../../models/account.dart';
import '../../services/advocate_service.dart';
import '../../services/content_service.dart';
import '../../state/location_controller.dart';
import '../../state/saved_lawyers_controller.dart';
import '../queries/ask_lawyer_sheet.dart';
import 'advocate_card.dart';
import 'filter_screen.dart';

/// The lawyer directory.
///
/// It opens unfiltered. A location the visitor picked earlier is remembered and
/// shown, but it does not narrow anything by itself — on the website a picked
/// location used to arrive with a 100 km radius already applied, and someone
/// opening the directory from a city with no nearby lawyers was met with "0
/// lawyers found within 100 km": a filter they never set, hiding every lawyer
/// on the site.
class LawyersScreen extends StatefulWidget {
  const LawyersScreen({
    super.key,
    this.initialCity = '',
    this.initialService = '',
    this.initialQuery = '',
  });

  final String initialCity;
  final String initialService;

  /// What the home screen's "What is your legal matter?" box was carrying. It
  /// arrives already applied rather than as text waiting to be submitted —
  /// someone who pressed Find Lawyer has already asked.
  final String initialQuery;

  @override
  State<LawyersScreen> createState() => _LawyersScreenState();
}

class _LawyersScreenState extends State<LawyersScreen> {
  late AdvocateQuery _query;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();

  List<Advocate> _advocates = [];
  Set<String> _online = {};
  int _total = 0;
  int _page = 1;
  int _totalPages = 1;

  bool _loading = true;
  bool _loadingMore = false;
  ApiException? _error;
  Timer? _debounce;

  /// Practice areas with their matters, for matching what is typed. The
  /// server's `q` looks at names and profile text only, so "Bail" alone finds
  /// one lawyer while 328 list "Bail Matters" — the matter has to be sent as
  /// a filter, and this is how the screen knows one was meant.
  List<LegalService> _areas = [];

  /// What the dropdown under the search box offers, from 3 letters on.
  List<_Suggestion> _suggestions = [];
  Timer? _suggestDebounce;
  int _suggestSeq = 0;
  bool _suggestLoading = false;

  /// While something is being typed the screen is the search: suggestions
  /// only, no chips or cards under them. The list comes back once a
  /// suggestion is picked, the search key pressed, or the box cleared.
  ///
  /// Not tied to focus: closing the keyboard is not finishing the search,
  /// and the list under it would still be the one from before the typing.
  bool _typing = false;
  bool get _searching => _typing && _searchController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _query = AdvocateQuery(
      city: widget.initialCity,
      service: widget.initialService,
    );
    _searchController.text = widget.initialQuery;
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Opened from Home's search box: straight into typing.
      if (GoRouterState.of(context).uri.queryParameters['focus'] == '1') {
        _searchFocus.requestFocus();
      }
      if (widget.initialQuery.trim().isEmpty) {
        _load();
        _loadAreas();
        return;
      }
      await _loadAreas();
      if (mounted) _submitSearch(widget.initialQuery);
    });
  }

  Future<void> _loadAreas() async {
    try {
      final areas = await context.read<ContentService>().services();
      if (mounted) _areas = areas;
    } catch (_) {
      // Without the matters, search simply stays a name search.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _suggestDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 400) return;
    if (_loadingMore || _loading || _page >= _totalPages) return;
    _loadMore();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context
          .read<AdvocateService>()
          .search(_query.copyWith(page: 1));
      if (!mounted) return;
      setState(() {
        _advocates = _withDistance(result.advocates);
        _total = result.total;
        _page = result.page;
        _totalPages = result.totalPages;
        _loading = false;
      });
      _refreshPresence();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final result = await context
          .read<AdvocateService>()
          .search(_query.copyWith(page: _page + 1));
      if (!mounted) return;
      setState(() {
        _advocates = [..._advocates, ..._withDistance(result.advocates)];
        _page = result.page;
        _totalPages = result.totalPages;
        _loadingMore = false;
      });
      _refreshPresence();
    } on ApiException {
      if (!mounted) return;
      // A failed page-2 must not throw away page 1.
      setState(() => _loadingMore = false);
    }
  }

  /// Presence is asked for separately, because it is the one thing that cannot
  /// be cached with the profile without going stale.
  Future<void> _refreshPresence() async {
    final ids = _advocates.map((a) => a.id).where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    try {
      final online = await context.read<AdvocateService>().onlineAmong(ids);
      if (!mounted) return;
      setState(() => _online = online);
    } on ApiException {
      // Presence is a nicety; failing to read it just hides the dots.
    }
  }

  /// Distance is left unset on purpose.
  ///
  /// The API publishes a lawyer's city, not their coordinates — an office
  /// address is not something to hand out precisely — so there is nothing to
  /// measure against. City matching does the narrowing instead, and it already
  /// counts the other cities a lawyer works in.
  List<Advocate> _withDistance(List<Advocate> list) => list;

  void _onSearchChanged(String value) {
    _typing = value.trim().isNotEmpty;
    _suggest(value);
    _debounce?.cancel();
    // The list is hidden while typing, so it is only re-run when the box is
    // emptied — to put back the lawyers a name search had narrowed away.
    if (value.trim().isEmpty && _query.query.isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 300), () => _applySearch(''));
    }
  }

  /// The live search while typing: text that names a matter or a practice
  /// area exactly becomes that filter; anything else is a name/keyword search.
  void _applySearch(String value) {
    final text = value.trim();
    final hit = _exactTopic(text);
    setState(() {
      _query = hit == null
          ? _query.copyWith(query: text, page: 1)
          : _withTopic(hit);
    });
    _load();
  }

  /// A search the visitor has committed to — Enter here, or the search box on
  /// Home. The server's `q` never looks at matters, so "divorce" as text finds
  /// 8 lawyers while 329 list Divorce: text that points at a matter or area
  /// becomes that filter (and a pill), and only the rest searches by name.
  void _submitSearch(String value) {
    final text = value.trim();
    final hit = _bestTopic(text);
    if (hit == null) {
      _applySearch(text);
      return;
    }
    _searchController.clear();
    setState(() => _query = _withTopic(hit));
    _load();
  }

  AdvocateQuery _withTopic(_Suggestion hit) => hit.isMatter
      ? _query.copyWith(query: '', subService: hit.label, page: 1)
      : _query.copyWith(query: '', service: hit.label, subService: '', page: 1);

  _Suggestion? _exactTopic(String text) {
    final t = text.toLowerCase();
    if (t.isEmpty) return null;
    for (final a in _areas) {
      if (a.name.toLowerCase() == t) return _Suggestion.area(a.name);
      for (final m in a.subServices) {
        if (m.name.toLowerCase() == t) return _Suggestion.matter(m.name, a.name);
      }
    }
    return null;
  }

  /// The matter or area the text most likely means: an exact name, else one
  /// that starts with it ("bail" → Bail Matters), else one that contains it —
  /// the shortest such name, being the least specific. Nothing under 3
  /// letters, which would match half the list.
  _Suggestion? _bestTopic(String text) {
    final exact = _exactTopic(text);
    if (exact != null) return exact;
    final t = text.toLowerCase();
    if (t.length < 3) return null;

    _Suggestion? best;
    var bestRank = 99;
    void consider(_Suggestion s) {
      final name = s.label.toLowerCase();
      if (!name.contains(t)) return;
      final rank = name.startsWith(t) ? 0 : 1;
      if (rank < bestRank ||
          (rank == bestRank && best != null && s.label.length < best!.label.length)) {
        best = s;
        bestRank = rank;
      }
    }

    for (final a in _areas) {
      consider(_Suggestion.area(a.name));
      for (final m in a.subServices) {
        consider(_Suggestion.matter(m.name, a.name));
      }
    }
    return best;
  }

  /// Matters and practice areas straight away, from the list already on the
  /// phone; lawyers by name a moment later, from the server.
  void _suggest(String value) {
    final text = value.trim();
    _suggestDebounce?.cancel();
    final seq = ++_suggestSeq;
    if (text.length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    final t = text.toLowerCase();
    final areas = <_Suggestion>[];
    final matters = <_Suggestion>[];
    final seen = <String>{};
    for (final a in _areas) {
      if (a.name.toLowerCase().contains(t)) areas.add(_Suggestion.area(a.name));
      for (final m in a.subServices) {
        // The same matter can sit under two areas; offer it once.
        if (m.name.toLowerCase().contains(t) && seen.add(m.name.toLowerCase())) {
          matters.add(_Suggestion.matter(m.name, a.name));
        }
      }
    }
    final local = [...matters.take(6), ...areas.take(3)];
    setState(() {
      _suggestions = local;
      _suggestLoading = true;
    });

    _suggestDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        // The server's q also matches profile text — "div" brings back
        // lawyers whose About mentions divorce — so ask for a wider page and
        // keep only the ones whose name has what was typed.
        final page = await context
            .read<AdvocateService>()
            .search(AdvocateQuery(query: text, perPage: 20));
        if (!mounted || seq != _suggestSeq) return;
        final byName = page.advocates
            .where((a) => a.name.toLowerCase().contains(t))
            .take(5);
        setState(() {
          _suggestions = [...local, for (final a in byName) _Suggestion.lawyer(a)];
          _suggestLoading = false;
        });
      } on ApiException {
        // Names are a nicety on top of the matters; keep what is shown.
        if (mounted && seq == _suggestSeq) setState(() => _suggestLoading = false);
      }
    });
  }

  void _pickSuggestion(_Suggestion s) {
    _typing = false;
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    _suggestDebounce?.cancel();
    _suggestSeq++;
    final lawyer = s.lawyer;
    if (lawyer != null) {
      setState(() => _suggestions = []);
      context.push('/lawyers/${lawyer.profilePath}');
      return;
    }
    // A topic becomes a filter pill, so the box is cleared rather than left
    // holding text that is no longer what the list is searched by.
    _searchController.clear();
    setState(() {
      _suggestions = [];
      _query = s.isMatter
          ? _query.copyWith(query: '', subService: s.label, page: 1)
          : _query.copyWith(query: '', service: s.label, subService: '', page: 1);
    });
    _load();
  }

  /// The filter set opens as a screen of its own — six filters, each with a
  /// list behind it, is more than a sheet can hold without stacking sheets on
  /// sheets. Nothing is applied until it closes, so a slow connection is not
  /// re-queried on every tap inside it.
  Future<void> _openFilters() async {
    final updated = await Navigator.of(context).push<AdvocateQuery>(
      MaterialPageRoute(builder: (_) => FilterScreen(query: _query)),
    );
    if (updated == null) return;
    setState(() => _query = updated.copyWith(page: 1));
    _load();
  }

  void _clearAll() {
    _searchController.clear();
    setState(() => _query = const AdvocateQuery());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final location = context.watch<LocationController>();

    // Back while typing leaves the search and puts the list back, rather than
    // leaving the app with the suggestions still up. A BackButtonListener,
    // not PopScope: this is a tab's root page, and go_router exits the app
    // from one without asking its PopScope.
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!_searching) return false;
        _cancelSearch();
        return true;
      },
      child: Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // 16 to sit on the same left edge as the search field and the cards
        // below it. At 0 — and this tab has no back button to take up the slack
        // — the heading ran flush into the screen's edge.
        titleSpacing: 16,
        // Two lines, because the title is the answer to "which lawyers am I
        // looking at" and that answer is two facts — the practice area and the
        // place. Squeezing them onto one line truncates the city, which is the
        // half a client is more likely to be checking.
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _headline(location),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        // The way back to whatever the heart has kept. Only once something is
        // saved: an empty shortlist is not worth a permanent button here.
        actions: [
          if (context.watch<SavedLawyersController>().count > 0)
            IconButton(
              tooltip: 'Saved lawyers',
              icon: const Icon(Icons.favorite_rounded, color: Color(0xFFEF4444)),
              onPressed: () => context.push('/saved'),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (v) {
                    _typing = false;
                    _debounce?.cancel();
                    _suggestSeq++;
                    setState(() => _suggestions = []);
                    _submitSearch(v);
                  },
                  decoration: InputDecoration(
                    hintText: 'Search by name, practice area or matter',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          ),
                  ),
                ),
                if (!_searching) const SizedBox(height: 10),
                if (!_searching) _sortChips(),
                if (!_searching && (_query.hasFilters || location.hasCity)) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        if (location.hasCity && _query.city.isEmpty)
                          _pill(
                            Icons.location_on_rounded,
                            location.label.isEmpty ? location.city : location.label,
                            onTap: () {
                              setState(() =>
                                  _query = _query.copyWith(city: location.city));
                              _load();
                            },
                          ),
                        if (_query.city.isNotEmpty)
                          _pill(Icons.location_city_rounded, _query.city,
                              onClear: () {
                            setState(() => _query = _query.copyWith(city: ''));
                            _load();
                          }),
                        if (_query.service.isNotEmpty)
                          _pill(Icons.gavel_rounded, _query.service, onClear: () {
                            setState(() => _query = _query.copyWith(service: ''));
                            _load();
                          }),
                        if (_query.subService.isNotEmpty)
                          _pill(Icons.topic_outlined, _query.subService, onClear: () {
                            setState(() => _query = _query.copyWith(subService: ''));
                            _load();
                          }),
                        if (_query.court.isNotEmpty)
                          _pill(Icons.account_balance_rounded, _query.court,
                              onClear: () {
                            setState(() => _query = _query.copyWith(court: ''));
                            _load();
                          }),
                        if (_query.availability.isNotEmpty)
                          _pill(
                            Icons.circle,
                            _query.availability == 'online' ? 'Online now' : 'Offline',
                            onClear: () {
                              setState(
                                  () => _query = _query.copyWith(availability: ''));
                              _load();
                            },
                          ),
                        if (_query.hasFilters)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: TextButton.icon(
                              onPressed: _clearAll,
                              icon: const Icon(Icons.close_rounded, size: 15),
                              label: const Text('Clear all'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // The count only. Sorting is the chip row above, and it used to be
          // *also* a dropdown here — two controls over one piece of state,
          // which is how they drifted apart: the chips set 'fee-low' and this
          // dropdown only ever listed 'fee', so tapping the Fee chip left the
          // dropdown holding a value it had no item for and Flutter asserted.
          // Its 'fee' was not a sort the server knows either, so "Lowest rate"
          // had never actually sorted by rate.
          if (_searching) Expanded(child: _searchResults()),
          if (!_searching && !_loading && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
              child: Text(
                '$_total ${_total == 1 ? 'lawyer' : 'lawyers'} found',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink.withValues(alpha: 0.55),
                ),
              ),
            ),
          if (!_searching) Expanded(child: _body()),
        ],
      ),
      ),
    );
  }

  void _cancelSearch() {
    _typing = false;
    _suggestDebounce?.cancel();
    _suggestSeq++;
    _searchFocus.unfocus();
    _searchController.clear();
    setState(() => _suggestions = []);
    if (_query.query.isNotEmpty) _applySearch('');
  }

  /// The whole screen below the box while typing: what the text could mean.
  Widget _searchResults() {
    final text = _searchController.text.trim();
    if (text.length < 3) {
      return _searchHint(Icons.keyboard_rounded, 'Keep typing — suggestions appear after 3 letters.');
    }
    if (_suggestions.isEmpty) {
      if (_suggestLoading) {
        return const Padding(
          padding: EdgeInsets.only(top: 32),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      return _searchHint(
        Icons.search_off_rounded,
        'No matter, practice area or lawyer matches "$text". '
        'Press search to look through lawyers\' profiles for it.',
      );
    }
    return _SuggestionList(suggestions: _suggestions, onPick: _pickSuggestion);
  }

  Widget _searchHint(IconData icon, String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
      child: Column(
        children: [
          Icon(icon, size: 28, color: AppColors.inkFaint),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }

  /// What this list is, in the reader's terms.
  ///
  /// Built from the filters actually applied, so it can never claim a
  /// narrowing that is not in force — a heading reading "Criminal Lawyers in
  /// New Delhi" over an unfiltered national list is the kind of thing a
  /// reader believes and acts on.
  String _headline(LocationController location) {
    final area = _query.service.trim();
    final city = _query.city.trim().isNotEmpty
        ? _query.city.trim()
        : (location.hasCity ? location.city : '');

    final what = area.isEmpty ? 'Lawyers' : '$area Lawyers';
    return city.isEmpty ? 'Find $what' : '$what in $city';
  }

  /// One filter button and the sorts the server actually supports.
  ///
  /// There is no "distance" chip, however natural it looks beside the others:
  /// the listing endpoint sorts by relevance, rating, experience and fee, and
  /// nothing else. A chip that quietly did nothing would be worse than its
  /// absence — the reader would believe the list in front of them was ordered
  /// by how near each lawyer is, and choose from the top of it.
  /// The sorts the server implements, and the only place they are named.
  ///
  /// These strings go straight into the query, so each must be one of
  /// ADVOCATE_SORTS in the web project's lib/advocateSearch.js — 'relevance',
  /// 'rating', 'experience', 'fee-low', 'fee-high'. A value that is not on
  /// that list is silently ignored by the server, which shows up as a sort
  /// button that does nothing rather than as an error.
  static const _sorts = [
    (value: 'rating', label: 'Top rated'),
    (value: 'experience', label: 'Most experienced'),
    (value: 'fee-low', label: 'Lowest fee'),
  ];

  Widget _sortChips() {
    const sorts = _sorts;

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(
            label: 'Filters',
            icon: Icons.tune_rounded,
            selected: _query.activeCount > 0,
            badge: _query.activeCount,
            onTap: _openFilters,
          ),
          for (final s in sorts)
            _chip(
              label: s.label,
              selected: _query.sort == s.value,
              onTap: () => setState(() {
                // Tapping the active sort clears it rather than doing nothing,
                // so the chip is a toggle and there is always a way back to
                // the default order.
                _query = _query.copyWith(
                  sort: _query.sort == s.value ? 'relevance' : s.value,
                  page: 1,
                );
                _load();
              }),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    int badge = 0,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 14,
                      color: selected ? Colors.white : AppColors.ink),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.ink,
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String label,
      {VoidCallback? onClear, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 5),
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(Icons.close_rounded, size: 14, color: AppColors.primary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const SkeletonList(count: 6, height: 168);

    final error = _error;
    if (error != null) {
      return ErrorView(
        message: error.message,
        isNetwork: error.isNetwork,
        onRetry: _load,
      );
    }

    if (_advocates.isEmpty) {
      return EmptyView(
        icon: Icons.person_search_rounded,
        title: _query.hasFilters ? 'No lawyers match your filters' : 'No lawyers listed yet',
        message: _query.hasFilters
            ? 'Try removing a filter or widening your search.'
            : 'Verified lawyers will appear here as they join.',
        action: _query.hasFilters
            ? OutlinedButton.icon(
                onPressed: _clearAll,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Clear all filters'),
              )
            // Nobody to compare yet — describing the problem still gets a call.
            : FilledButton.icon(
                onPressed: () => AskLawyerSheet.open(context, category: _query.service),
                icon: const Icon(Icons.question_answer_outlined, size: 16),
                label: const Text('Ask a lawyer free'),
              ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomGutter(context)),
        itemCount: _advocates.length + (_loadingMore ? 1 : 0),
        // After the second lawyer, for the visitor who would rather describe the
        // problem than compare profiles — seen without scrolling far, and never
        // above the lawyers they came for.
        separatorBuilder: (_, index) => index == 1
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: AskLawyerBanner(category: _query.service),
              )
            : const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= _advocates.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            );
          }
          final advocate = _advocates[index];
          return AdvocateCard(
            advocate: advocate,
            online: _online.isEmpty ? null : _online.contains(advocate.id),
          );
        },
      ),
    );
  }
}

/// One line in the search dropdown: a matter, a practice area, or a lawyer.
class _Suggestion {
  const _Suggestion._(this.label, this.detail, this.isMatter, this.lawyer);

  factory _Suggestion.matter(String name, String area) =>
      _Suggestion._(name, area, true, null);
  factory _Suggestion.area(String name) =>
      _Suggestion._(name, 'Practice area', false, null);
  factory _Suggestion.lawyer(Advocate a) => _Suggestion._(
        a.name,
        [a.specializations.take(2).join(', '), a.city]
            .where((s) => s.isNotEmpty)
            .join(' · '),
        false,
        a,
      );

  final String label;
  final String detail;
  final bool isMatter;
  final Advocate? lawyer;
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.suggestions, required this.onPick});

  final List<_Suggestion> suggestions;
  final ValueChanged<_Suggestion> onPick;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(0, 4, 0, bottomGutter(context)),
      itemCount: suggestions.length,
      separatorBuilder: (_, __) => Divider(height: 1, indent: 60, color: AppColors.border),
      itemBuilder: (_, i) {
        final s = suggestions[i];
        final icon = s.lawyer != null
            ? Icons.person_outline_rounded
            : s.isMatter
                ? Icons.topic_outlined
                : Icons.gavel_rounded;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary.withValues(alpha: 0.06),
            child: Icon(icon, size: 19, color: AppColors.primary),
          ),
          title: Text(
            s.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
          subtitle: s.detail.isEmpty
              ? null
              : Text(
                  s.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                ),
          trailing: Icon(Icons.north_west_rounded, size: 16, color: AppColors.inkFaint),
          onTap: () => onPick(s),
        );
      },
    );
  }
}

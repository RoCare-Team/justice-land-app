import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../../state/marketplace_controller.dart';
import 'service_widgets.dart';

/// The whole catalogue, searchable and filtered by shelf.
///
/// Separate from the landing page because the two answer different questions.
/// The landing page answers "what kinds of thing can I buy here"; this one
/// answers "show me all of them, and let me narrow it down" — and a single
/// screen trying to do both ends up a list of categories nobody can search and
/// a list of services nobody can scan.
class AllServicesScreen extends StatefulWidget {
  const AllServicesScreen({
    super.key,
    this.initialCategory = '',
    this.autofocusSearch = false,
  });

  final String initialCategory;

  /// Opens with the keyboard up, for the arrival from the search field on the
  /// landing page — tapping a search box and then having to tap another one is
  /// a step that should not exist.
  final bool autofocusSearch;

  @override
  State<AllServicesScreen> createState() => _AllServicesScreenState();
}

class _AllServicesScreenState extends State<AllServicesScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final market = context.read<MarketplaceController>();
      _search.text = market.query;
      market.setCategory(widget.initialCategory, replace: true);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Search as you type, but one request per pause rather than one per key —
  /// the catalogue is small and the server is not, and a request per keystroke
  /// arrives out of order as often as not.
  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) context.read<MarketplaceController>().search(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final market = context.watch<MarketplaceController>();

    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(
        title: const Text('All services'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  autofocus: widget.autofocusSearch,
                  textInputAction: TextInputAction.search,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search services…',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.muted,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 20, color: AppColors.ink.withValues(alpha: 0.4)),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _search.clear();
                              _onSearchChanged('');
                            },
                          ),
                    border: _border,
                    enabledBorder: _border,
                    focusedBorder: _border,
                  ),
                ),
                if (market.categories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _chipRow(market),
                ],
              ],
            ),
          ),
          Expanded(child: _body(market)),
        ],
      ),
    );
  }

  static final _border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  );

  Widget _chipRow(MarketplaceController market) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // 'All' plus one per shelf. 'All' is first because it is the way back,
        // and a way back that scrolls off the end is not one.
        itemCount: market.categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _Chip(
              label: 'All',
              selected: market.category.isEmpty,
              onTap: () => market.setCategory('', replace: true),
            );
          }
          final category = market.categories[i - 1];
          return _Chip(
            label: category.name,
            selected: market.category == category.name,
            onTap: () => market.setCategory(category.name),
          );
        },
      ),
    );
  }

  Widget _body(MarketplaceController market) {
    if (market.loading && market.services.isEmpty) {
      return const LoadingView(label: 'Loading services…');
    }
    if (market.error != null && market.services.isEmpty) {
      return ErrorView(message: market.error!, onRetry: market.load);
    }
    if (market.services.isEmpty) {
      return EmptyView(
        icon: Icons.search_off_rounded,
        title: 'Nothing matched',
        message: market.query.isEmpty
            ? 'There is nothing on this shelf yet. Try another category.'
            : 'No service matches “${market.query}”. Try a different word.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => market.load(silent: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        itemCount: market.services.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => ServiceCard(service: market.services[i]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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
      color: selected ? AppColors.primary : AppColors.muted,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.ink.withValues(alpha: 0.10),
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

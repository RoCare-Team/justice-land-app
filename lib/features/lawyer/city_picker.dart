import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

/// "Which cities do you practise in" — the lawyer's own city as a locked line,
/// the extra cities they have chosen as removable chips, and one-tap
/// suggestions or a search for the rest. Used by the onboarding and the profile
/// editor, so a city picked in one is shown as chosen in the other.
///
/// It holds no selection of its own: [selected] is the caller's list, and a tap
/// only asks the caller to [onAdd] or [onRemove] — the caller decides whether the
/// plan allows it.
class CityPicker extends StatefulWidget {
  const CityPicker({
    super.key,
    required this.options,
    required this.selected,
    required this.baseCity,
    required this.onAdd,
    required this.onRemove,
  });

  /// Every city that can be offered.
  final List<String> options;

  /// The extra cities chosen so far.
  final List<String> selected;

  /// The lawyer's own city. Always included, never offered again.
  final String baseCity;

  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<CityPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _isBase(String city) =>
      widget.baseCity.trim().isNotEmpty && city.trim().toLowerCase() == widget.baseCity.trim().toLowerCase();

  void _add(String city) {
    widget.onAdd(city);
    _search.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final chosen = [for (final c in widget.selected) if (!_isBase(c)) c];
    final available = [
      for (final c in widget.options)
        if (!_isBase(c) && !widget.selected.contains(c)) c,
    ];
    final query = _search.text.trim().toLowerCase();
    final matches = query.isEmpty
        ? const <String>[]
        : available.where((c) => c.toLowerCase().contains(query)).take(8).toList();
    final popular = available.take(12).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.baseCity.trim().isNotEmpty) _BaseCityPill(city: widget.baseCity.trim()),
        if (chosen.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final city in chosen) _CityPill(label: city, onRemove: () => widget.onRemove(city)),
            ],
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search any city to add',
            prefixIcon: const Icon(Icons.search_rounded, size: 21),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
        ),
        if (matches.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final city in matches) SelectableChip(label: city, selected: false, onTap: () => _add(city)),
            ],
          ),
        ] else if (query.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('No city matches that.', style: TextStyle(fontSize: 13, color: AppColors.inkFaint)),
        ],
        if (popular.isNotEmpty && query.isEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'POPULAR CITIES',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: AppColors.inkFaint),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final city in popular) SelectableChip(label: city, selected: false, onTap: () => _add(city)),
            ],
          ),
        ],
      ],
    );
  }
}

/// The lawyer's own city: always included, never removable, and never counted
/// against the plan's city allowance.
class _BaseCityPill extends StatelessWidget {
  const _BaseCityPill({required this.city});

  final String city;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(city, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          Text('Your base city · included', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
        ],
      ),
    );
  }
}

class _CityPill extends StatelessWidget {
  const _CityPill({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onRemove,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
              const SizedBox(width: 6),
              const Icon(Icons.close_rounded, size: 16, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../services/advocate_service.dart';
import '../../services/content_service.dart';

/// The whole filter set on one screen: pick, then Show Results.
///
/// A screen rather than a sheet because there are six of these and each opens
/// a list of its own — nested sheets on a phone leave you unsure which "back"
/// you are pressing. Nothing is applied while you are in here; the search runs
/// once, when you come out, which is also what keeps a slow connection from
/// re-querying on every tap.
///
/// The options come from the server (`GET /api/services` carries the practice
/// areas, the courts and the languages; `GET /api/cities` the cities), so this
/// screen offers exactly what the website's own filter bar offers. If the
/// network is down the lists bundled with the app stand in — see RefData in
/// core/config/reference_data.dart, which ContentService falls back to.
class FilterScreen extends StatefulWidget {
  const FilterScreen({super.key, required this.query});

  final AdvocateQuery query;

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

/// Years in practice, as floors. Offered as steps rather than a slider: nobody
/// searches for "at least 7 years", and a slider invites a precision the
/// underlying number does not have.
const List<int> _experienceSteps = [0, 3, 5, 10, 15, 20];

/// Ceilings on the per-minute rate.
const List<int> _feeSteps = [0, 25, 50, 100, 250, 500];

class _FilterScreenState extends State<FilterScreen> {
  late AdvocateQuery _draft = widget.query;

  List<String> _services = [];
  List<String> _cities = [];
  List<String> _courts = [];
  List<String> _languages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOptions());
  }

  Future<void> _loadOptions() async {
    final content = context.read<ContentService>();
    // Four lists, two requests: the practice areas, the courts and the
    // languages all arrive together in the one /api/services response, and
    // ContentService caches it so asking three times fetches once.
    final services = await content.services();
    final cities = await content.cities();
    final courts = await content.courts();
    final languages = await content.languages();

    if (!mounted) return;
    setState(() {
      _services = [for (final s in services) s.name];
      _cities = [for (final c in cities) c.name];
      _courts = courts;
      _languages = languages;
      _loading = false;
    });
  }

  /// Sub-services belong to the chosen practice area, so changing the area
  /// clears the matter under it — a stale pair filters to nobody.
  void _setService(String value) => setState(
        () => _draft = _draft.copyWith(service: value, subService: ''),
      );

  AdvocateQuery get _cleared => AdvocateQuery(query: _draft.query, sort: _draft.sort);

  void _set(AdvocateQuery Function(AdvocateQuery) change) => setState(() => _draft = change(_draft));

  @override
  Widget build(BuildContext context) {
    final active = _draft.activeCount;
    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(title: const Text('Filters')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          // The four list filters as a 2 × 2 grid: each is one tap to a list,
          // so they read better as tiles seen all at once than as a column of
          // rows pushing the chips below the fold.
          _Section(
            title: 'Find by',
            child: Column(
              children: [
                _TileRow(
                  left: _PickerTile(
                    icon: Icons.gavel_rounded,
                    label: 'Practice Area',
                    value: _draft.service,
                    loading: _loading,
                    options: _services,
                    onPick: _setService,
                  ),
                  right: _PickerTile(
                    icon: Icons.location_city_rounded,
                    label: 'City',
                    value: _draft.city,
                    loading: _loading,
                    options: _cities,
                    onPick: (v) => _set((q) => q.copyWith(city: v)),
                  ),
                ),
                const SizedBox(height: 10),
                _TileRow(
                  left: _PickerTile(
                    icon: Icons.account_balance_rounded,
                    label: 'Court',
                    value: _draft.court,
                    loading: _loading,
                    options: _courts,
                    onPick: (v) => _set((q) => q.copyWith(court: v)),
                  ),
                  right: _PickerTile(
                    icon: Icons.translate_rounded,
                    label: 'Language',
                    value: _draft.language,
                    loading: _loading,
                    options: _languages,
                    onPick: (v) => _set((q) => q.copyWith(language: v)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Experience',
            icon: Icons.workspace_premium_outlined,
            child: _StepRow(
              anyLabel: 'Any',
              value: _draft.minExperience,
              steps: _experienceSteps,
              format: (v) => '$v+ yrs',
              onPick: (v) => _set((q) => q.copyWith(minExperience: v)),
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Fee per minute',
            icon: Icons.currency_rupee_rounded,
            child: _StepRow(
              anyLabel: 'Any',
              value: _draft.maxFee,
              steps: _feeSteps,
              format: (v) => 'Up to ${Fmt.money(v)}',
              onPick: (v) => _set((q) => q.copyWith(maxFee: v)),
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            child: Column(
              children: [
                _Toggle(
                  icon: Icons.wifi_tethering_rounded,
                  iconColor: AppColors.success,
                  label: 'Online now',
                  note: 'Lawyers available to talk right now.',
                  value: _draft.availability == 'online',
                  onChanged: (on) => _set((q) => q.copyWith(availability: on ? 'online' : '')),
                ),
                Divider(height: 22, color: AppColors.border),
                _Toggle(
                  icon: Icons.verified_rounded,
                  iconColor: AppColors.info,
                  label: 'Verified lawyers only',
                  // Said plainly, because switching it on can legitimately
                  // return nobody — verification is done by hand by an
                  // administrator, not granted on registration.
                  note: 'Only lawyers an administrator has verified.',
                  value: _draft.verifiedOnly,
                  onChanged: (on) => _set((q) => q.copyWith(verifiedOnly: on)),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Padding(
          // The shell's tab bar floats over this screen, and its raised Top
          // Lawyers button sits higher still — clear both, not just the inset.
          padding: EdgeInsets.fromLTRB(16, 10, 16, bottomGutter(context, 34)),
          child: Row(
            children: [
              // Reset sits beside the action rather than up in the app bar,
              // where it was easy to miss. The typed search survives it: it is
              // what the visitor came looking for, not one of the filters.
              OutlinedButton(
                onPressed: active == 0 ? null : () => setState(() => _draft = _cleared),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                child: const Text('Reset'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(
                  label: active == 0 ? 'Show Results' : 'Show Results ($active)',
                  onPressed: () => Navigator.pop(context, _draft.copyWith(page: 1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A white card grouping one part of the filter set, with an optional heading.
class _Section extends StatelessWidget {
  const _Section({this.title, this.icon, required this.child});

  final String? title;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppColors.primary),
                  const SizedBox(width: 6),
                ],
                Text(title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }
}

/// One filter that opens a list, as a tile in the 2 × 2 grid. Shows "All" when
/// nothing is chosen, which is the truth about an unset filter rather than an
/// empty-looking control; a chosen one is highlighted and its ✕ clears it
/// without opening the list.
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onPick,
    required this.loading,
  });

  final IconData icon;
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onPick;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final chosen = value.isNotEmpty;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: chosen ? AppColors.primary.withValues(alpha: 0.45) : AppColors.border,
      ),
    );
    return Material(
      color: chosen ? AppColors.primary.withValues(alpha: 0.06) : AppColors.muted,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: loading ? null : () => _open(context),
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 15, color: AppColors.inkMuted),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (loading)
                        SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.inkFaint),
                        )
                      else
                        Text(
                          chosen ? _summary(value) : 'All',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: chosen ? AppColors.primary : AppColors.ink,
                          ),
                        ),
                    ],
                  ),
                ),
                if (chosen)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Clear $label',
                    icon: Icon(Icons.close_rounded, size: 18, color: AppColors.inkMuted),
                    onPressed: () => onPick(''),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.inkFaint),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _summary(String value) {
    final values = AdvocateQuery.valuesOf(value);
    return values.length < 2 ? values.first : '${values.first} +${values.length - 1}';
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      // Over the tab bar, not under it — its raised Top Lawyers button would
      // otherwise sit on top of Apply.
      useRootNavigator: true,
      builder: (_) => _OptionSheet(title: label, value: value, options: options),
    );
    if (picked != null) onPick(picked);
  }
}

/// The options for one filter, any number of them ticked — searchable once
/// there are enough to be worth scrolling (the city list runs past a hundred).
/// Nothing changes until Apply, so ticking through a long list does not
/// re-run anything; "All" clears the ticks.
class _OptionSheet extends StatefulWidget {
  const _OptionSheet({
    required this.title,
    required this.value,
    required this.options,
  });

  final String title;

  /// The current choice, several values joined as [AdvocateQuery] keeps them.
  final String value;
  final List<String> options;

  @override
  State<_OptionSheet> createState() => _OptionSheetState();
}

class _OptionSheetState extends State<_OptionSheet> {
  String _search = '';
  late final Set<String> _picked = AdvocateQuery.valuesOf(widget.value).toSet();

  @override
  Widget build(BuildContext context) {
    final searchable = widget.options.length > 12;
    final needle = _search.trim().toLowerCase();
    final rows = needle.isEmpty
        ? widget.options
        : widget.options.where((o) => o.toLowerCase().contains(needle)).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            height: 4,
            width: 40,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_picked.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_picked.clear),
                    child: const Text('Clear'),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Select one or more',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
              ),
            ),
          ),
          if (searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: TextField(
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search ${widget.title.toLowerCase()}',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.only(bottom: 12),
              // "All" first: how a filter is removed without unticking each.
              itemCount: rows.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return _tile(
                    label: 'All',
                    selected: _picked.isEmpty,
                    onTap: () => setState(_picked.clear),
                  );
                }
                final option = rows[i - 1];
                return _tile(
                  label: option,
                  selected: _picked.contains(option),
                  onTap: () => setState(() {
                    if (!_picked.remove(option)) _picked.add(option);
                  }),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: PrimaryButton(
              label: _picked.isEmpty ? 'Show all' : 'Apply (${_picked.length})',
              // Kept in the list's own order, so the pill and the tile read
              // the same way however the ticks were made.
              onPressed: () => Navigator.pop(
                context,
                AdvocateQuery.join(widget.options.where(_picked.contains)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return CheckboxListTile(
      value: selected,
      onChanged: (_) => onTap(),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      activeColor: AppColors.primary,
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? AppColors.primary : AppColors.ink,
        ),
      ),
    );
  }
}

/// A filter chosen from a handful of steps, laid out as chips.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.anyLabel,
    required this.value,
    required this.steps,
    required this.format,
    required this.onPick,
  });

  final String anyLabel;
  final int value;
  final List<int> steps;
  final String Function(int) format;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final step in steps)
          SelectableChip(
            label: step == 0 ? anyLabel : format(step),
            selected: value == step,
            onTap: () => onPick(step),
          ),
      ],
    );
  }
}

/// An on/off filter. The whole row toggles it, not just the switch.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.note,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String note;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(note, style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint)),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

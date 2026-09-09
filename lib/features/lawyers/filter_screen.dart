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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Lawyer'),
        actions: [
          if (_draft.activeCount > 0)
            TextButton(
              onPressed: () => setState(
                // The typed search survives a reset: it is what the visitor
                // came looking for, not one of the filters they are clearing.
                () => _draft = AdvocateQuery(query: _draft.query, sort: _draft.sort),
              ),
              child: const Text('Clear all'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          _PickerRow(
            label: 'Practice Area',
            value: _draft.service,
            loading: _loading,
            options: _services,
            onPick: _setService,
          ),
          _PickerRow(
            label: 'City',
            value: _draft.city,
            loading: _loading,
            options: _cities,
            onPick: (v) => setState(() => _draft = _draft.copyWith(city: v)),
          ),
          _PickerRow(
            label: 'Court',
            value: _draft.court,
            loading: _loading,
            options: _courts,
            onPick: (v) => setState(() => _draft = _draft.copyWith(court: v)),
          ),
          _PickerRow(
            label: 'Language',
            value: _draft.language,
            loading: _loading,
            options: _languages,
            onPick: (v) => setState(() => _draft = _draft.copyWith(language: v)),
          ),

          const SizedBox(height: 18),
          _StepRow(
            label: 'Experience',
            anyLabel: 'Any',
            value: _draft.minExperience,
            steps: _experienceSteps,
            format: (v) => '$v+ yrs',
            onPick: (v) => setState(() => _draft = _draft.copyWith(minExperience: v)),
          ),
          const SizedBox(height: 18),
          _StepRow(
            label: 'Fee / Minute',
            anyLabel: 'Any',
            value: _draft.maxFee,
            steps: _feeSteps,
            format: (v) => 'Up to ${Fmt.money(v)}',
            onPick: (v) => setState(() => _draft = _draft.copyWith(maxFee: v)),
          ),

          const SizedBox(height: 18),
          _Toggle(
            label: 'Online Now Only',
            note: 'Lawyers who have their availability switched on right now.',
            value: _draft.availability == 'online',
            onChanged: (on) => setState(
              () => _draft = _draft.copyWith(availability: on ? 'online' : ''),
            ),
          ),
          Divider(height: 24, color: AppColors.border),
          _Toggle(
            label: 'Verified Lawyers Only',
            // Said plainly, because switching it on can legitimately return
            // nobody — verification is done by hand by an administrator, not
            // granted on registration.
            note: 'Only lawyers an administrator has verified.',
            value: _draft.verifiedOnly,
            onChanged: (on) => setState(() => _draft = _draft.copyWith(verifiedOnly: on)),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: PrimaryButton(
          label: 'Show Results',
          onPressed: () => Navigator.pop(context, _draft.copyWith(page: 1)),
        ),
      ),
    );
  }
}

/// One filter that opens a list. Shows "All" when nothing is chosen, which is
/// the truth about an unset filter rather than an empty-looking control.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onPick,
    required this.loading,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onPick;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            if (loading)
              SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.inkFaint,
                ),
              )
            else
              Flexible(
                child: Text(
                  value.isEmpty ? 'All' : value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: value.isEmpty ? FontWeight.w400 : FontWeight.w600,
                    color: value.isEmpty ? AppColors.inkFaint : AppColors.primary,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OptionSheet(title: label, value: value, options: options),
    );
    if (picked != null) onPick(picked);
  }
}

/// The options for one filter, searchable once there are enough of them to be
/// worth scrolling — the city list runs past a hundred.
class _OptionSheet extends StatefulWidget {
  const _OptionSheet({
    required this.title,
    required this.value,
    required this.options,
  });

  final String title;
  final String value;
  final List<String> options;

  @override
  State<_OptionSheet> createState() => _OptionSheetState();
}

class _OptionSheetState extends State<_OptionSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final searchable = widget.options.length > 12;
    final needle = _search.trim().toLowerCase();
    final rows = needle.isEmpty
        ? widget.options
        : widget.options.where((o) => o.toLowerCase().contains(needle)).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
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
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
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
              padding: const EdgeInsets.only(bottom: 24),
              // One extra row at the top: "All", which is how a filter is
              // removed. Without it the only way out of a choice is Clear all.
              itemCount: rows.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return _tile(context, label: 'All', value: '', selected: widget.value.isEmpty);
                }
                final option = rows[i - 1];
                return _tile(
                  context,
                  label: option,
                  value: option,
                  selected: option == widget.value,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required String label,
    required String value,
    required bool selected,
  }) {
    return ListTile(
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          color: selected ? AppColors.primary : AppColors.ink,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check_rounded, size: 20, color: AppColors.primary)
          : null,
      onTap: () => Navigator.pop(context, value),
    );
  }
}

/// A filter chosen from a handful of steps, laid out as chips.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.anyLabel,
    required this.value,
    required this.steps,
    required this.format,
    required this.onPick,
  });

  final String label;
  final String anyLabel;
  final int value;
  final List<int> steps;
  final String Function(int) format;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(
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
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.note,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String note;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
    );
  }
}

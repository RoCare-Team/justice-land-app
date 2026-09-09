import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/config/reference_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../state/location_controller.dart';

/// Choosing a location.
///
/// Three ways in — the device's position, a PIN code, or a city from the list.
/// Whichever is used, the result only says *where you are*. It does not filter
/// the directory by distance on its own; that is a separate, deliberate choice.
class LocationSheet extends StatefulWidget {
  const LocationSheet({super.key});

  static Future<void> open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const LocationSheet(),
    );
  }

  @override
  State<LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<LocationSheet> {
  final _pincode = TextEditingController();
  final _search = TextEditingController();
  String _stateFilter = '';

  @override
  void dispose() {
    _pincode.dispose();
    _search.dispose();
    super.dispose();
  }

  List<(String city, String state)> get _cities {
    final query = _search.text.trim().toLowerCase();
    final out = <(String, String)>[];
    for (final state in RefData.states) {
      if (_stateFilter.isNotEmpty && state != _stateFilter) continue;
      for (final city in RefData.citiesIn(state)) {
        if (query.isEmpty || city.toLowerCase().contains(query)) {
          out.add((city, state));
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final location = context.watch<LocationController>();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            height: 4,
            width: 40,
            decoration: BoxDecoration(
              color: AppColors.ink.withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Text('Your location',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                if (location.hasCity || location.hasLocation)
                  TextButton(
                    onPressed: () async {
                      await context.read<LocationController>().clear();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                OutlinedButton.icon(
                  onPressed: location.locating
                      ? null
                      : () async {
                          final ok = await context
                              .read<LocationController>()
                              .useCurrentLocation();
                          if (ok && context.mounted) Navigator.of(context).pop();
                        },
                  icon: location.locating
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(location.locating
                      ? 'Finding you…'
                      : 'Use my current location'),
                ),
                if (location.error != null) ...[
                  const SizedBox(height: 12),
                  NoticeBanner(
                    message: location.error!,
                    tone: ChipTone.warning,
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pincode,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'PIN code',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: location.locating
                            ? null
                            : () async {
                                final ok = await context
                                    .read<LocationController>()
                                    .setFromPincode(_pincode.text);
                                if (ok && context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                        child: const Text('Go'),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 30),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search for a city',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SelectableChip(
                          label: 'All states',
                          selected: _stateFilter.isEmpty,
                          onTap: () => setState(() => _stateFilter = ''),
                        ),
                      ),
                      for (final state in RefData.states)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SelectableChip(
                            label: state,
                            selected: _stateFilter == state,
                            onTap: () => setState(
                                () => _stateFilter = _stateFilter == state ? '' : state),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (final (city, state) in _cities.take(120))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      Icons.location_city_rounded,
                      size: 18,
                      color: AppColors.inkFaint,
                    ),
                    title: Text(city, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      state,
                      style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                    ),
                    trailing: location.city == city
                        ? const Icon(Icons.check_rounded,
                            size: 18, color: AppColors.primary)
                        : null,
                    onTap: () async {
                      await context
                          .read<LocationController>()
                          .setCity(city, label: city);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                if (_cities.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        'No city matches that search.',
                        style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
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
}

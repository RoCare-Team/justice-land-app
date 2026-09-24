import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/states.dart';
import '../../models/advocate.dart';
import '../../services/advocate_service.dart';
import '../../state/saved_lawyers_controller.dart';
import 'advocate_card.dart';

/// The lawyers this client kept with the heart.
///
/// The shortlist itself is only identifiers, so each profile is fetched fresh
/// rather than drawn from whatever was cached when it was saved: rates change,
/// plans lapse and lawyers go offline, and a shortlist that quotes last
/// month's price is worse than one that takes a moment to load.
///
/// A saved lawyer whose profile no longer loads is simply left out of the
/// list — unpublished or deleted, they are not someone the client can book.
class SavedLawyersScreen extends StatefulWidget {
  const SavedLawyersScreen({super.key});

  @override
  State<SavedLawyersScreen> createState() => _SavedLawyersScreenState();
}

class _SavedLawyersScreenState extends State<SavedLawyersScreen> {
  final Map<String, Advocate> _loaded = {};
  Set<String> _online = {};
  bool _busy = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final saved = context.read<SavedLawyersController>();
    await saved.load();
    if (!mounted) return;

    final wanted = saved.items;
    if (wanted.isEmpty) {
      setState(() {
        _busy = false;
        _error = '';
        _loaded.clear();
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });

    final service = context.read<AdvocateService>();
    final results = await Future.wait(
      wanted.map((s) async {
        try {
          return await service.profile(s.path);
        } catch (_) {
          return null;
        }
      }),
    );
    if (!mounted) return;

    final found = results.whereType<Advocate>().toList();
    // Every profile failing on a non-empty list is a connection problem, not
    // a shortlist of lawyers who have all left.
    if (found.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'Could not load your saved lawyers.';
      });
      return;
    }

    Set<String> online = {};
    try {
      online = await service.onlineAmong(found.map((a) => a.id).toList());
    } catch (_) {
      // Presence is decoration here; the list is still worth showing.
    }
    if (!mounted) return;

    setState(() {
      _loaded
        ..clear()
        ..addEntries(found.map((a) => MapEntry(a.id, a)));
      _online = online;
      _busy = false;
      _error = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<SavedLawyersController>();
    // Driven by the shortlist, not by what was fetched, so unsaving a lawyer
    // takes their card off this screen the moment the heart is tapped.
    final advocates = saved.items
        .map((s) => _loaded[s.id])
        .whereType<Advocate>()
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Lawyers')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _body(saved, advocates),
      ),
    );
  }

  Widget _body(SavedLawyersController saved, List<Advocate> advocates) {
    if (saved.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 70),
          EmptyView(
            icon: Icons.favorite_border_rounded,
            title: 'No saved lawyers yet',
            message:
                'Tap the heart on any lawyer to keep them here while you decide.',
            action: FilledButton(
              onPressed: () => context.go('/lawyers'),
              child: const Text('Browse lawyers'),
            ),
          ),
        ],
      );
    }

    if (_busy && advocates.isEmpty) {
      return const SkeletonList(count: 4);
    }

    if (_error.isNotEmpty && advocates.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 70),
          ErrorView(message: _error, onRetry: _load, isNetwork: true),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      itemCount: advocates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final advocate = advocates[i];
        return AdvocateCard(
          advocate: advocate,
          online: _online.isEmpty ? null : _online.contains(advocate.id),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/states.dart';
import '../../models/marketplace.dart';
import '../../state/marketplace_controller.dart';

/// One service, in full: what it is, what you get, what you will be asked for,
/// and what happens after you pay.
///
/// The price in the sticky bar is the pre-tax figure, labelled as such. GST is
/// added on the summary screen and shown as its own line there — quoting a
/// tax-inclusive number here and a different one at checkout is how a client
/// ends up feeling overcharged by an amount that was always correct.
class ServiceDetailScreen extends StatefulWidget {
  const ServiceDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  ServiceProduct? _service;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service =
          await context.read<MarketplaceController>().detail(widget.slug);
      if (!mounted) return;
      setState(() {
        _service = service;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;

    return Scaffold(
      backgroundColor: AppColors.muted,
      body: _loading
          ? const LoadingView(label: 'Loading…')
          : service == null
              ? ErrorView(
                  message: _error ?? 'That service could not be loaded.',
                  onRetry: _load,
                )
              : _body(service),
      bottomNavigationBar: service == null ? null : _payBar(service),
    );
  }

  Widget _body(ServiceProduct service) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: service.banner.isEmpty ? 0 : 190,
          pinned: true,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: service.banner.isEmpty ? Text(service.title) : null,
          flexibleSpace: service.banner.isEmpty
              ? null
              : FlexibleSpaceBar(
                  background: RemoteImage(
                    source: service.banner,
                    fallback: Container(color: AppColors.primary),
                  ),
                ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          sliver: SliverList.list(
            children: [
              if (service.category.isNotEmpty) ...[
                _pill(service.category),
                const SizedBox(height: 10),
              ],
              Text(
                service.title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              if (service.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  service.summary,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: AppColors.ink.withValues(alpha: 0.65),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _facts(service),
              if (service.description.isNotEmpty) ...[
                const SizedBox(height: 20),
                _section(
                  'About this service',
                  Text(
                    service.description,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.6,
                      color: AppColors.ink.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              ],
              if (service.includes.isNotEmpty) ...[
                const SizedBox(height: 20),
                _section(
                  "What's included",
                  Column(
                    children: [
                      for (final item in service.includes)
                        _bullet(item, Icons.check_circle_rounded,
                            AppColors.success),
                    ],
                  ),
                ),
              ],
              if (service.howItWorks.isNotEmpty) ...[
                const SizedBox(height: 20),
                _section('How it works', _steps(service.howItWorks)),
              ],
              if (service.documentsRequired.isNotEmpty) ...[
                const SizedBox(height: 20),
                _section(
                  'Documents you will need',
                  Column(
                    children: [
                      for (final item in service.documentsRequired)
                        _bullet(item, Icons.insert_drive_file_outlined,
                            AppColors.primary),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Turnaround, rating and how many have bought it — each dropped when it has
  /// nothing honest to say rather than shown as a zero.
  Widget _facts(ServiceProduct service) {
    final facts = <Widget>[
      if (service.turnaround.isNotEmpty)
        _fact(Icons.schedule_rounded, service.turnaround, 'Turnaround'),
      if (service.hasRating)
        _fact(Icons.star_rounded, Fmt.rating(service.rating),
            '${service.reviews} reviews'),
      if (service.purchased > 0)
        _fact(Icons.verified_rounded, '${service.purchased}', 'Purchased'),
    ];

    if (facts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < facts.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 30,
                color: AppColors.ink.withValues(alpha: 0.08),
              ),
            Expanded(child: facts[i]),
          ],
        ],
      ),
    );
  }

  Widget _fact(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 17, color: AppColors.accent),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            color: AppColors.ink.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _section(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.ink.withValues(alpha: 0.07)),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _bullet(String text, IconData icon, Color tint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.ink.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _steps(List<ServiceStep> steps) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // The rail joins one step to the next, so the list reads as
                    // a sequence rather than four unrelated cards.
                    if (i < steps.length - 1)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: AppColors.primary.withValues(alpha: 0.15),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        bottom: i < steps.length - 1 ? 18 : 0, top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].title,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (steps[i].description.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            steps[i].description,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: AppColors.ink.withValues(alpha: 0.62),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _pill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.warning,
        ),
      ),
    );
  }

  Widget _payBar(ServiceProduct service) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      Fmt.money(service.price),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    if (service.hasOffer) ...[
                      const SizedBox(width: 6),
                      Text(
                        Fmt.money(service.mrp),
                        style: TextStyle(
                          fontSize: 12.5,
                          decoration: TextDecoration.lineThrough,
                          color: AppColors.ink.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '+ 18% GST',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.ink.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton(
                onPressed: () => context.push('/services/${service.slug}/order'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Next'),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, size: 17),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

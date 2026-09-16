import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../models/advocate.dart';

/// One lawyer, as the directory shows them.
///
/// A square portrait on the left with everything stacked to its right, and a
/// fixed portrait height, because a list of these is read by scanning down one
/// column of faces — a card whose height moves with the length of a tagline
/// breaks that column and makes the list feel unsorted.
///
/// Prices are slot prices, not per-minute rates. The website stopped charging
/// by the minute: a booking buys a block of time and is billed against that
/// block's price. Quoting ₹/min here would show a figure the server does not
/// use, and a card that prices a consultation differently from the checkout is
/// worse than a card with no price on it at all.
class AdvocateCard extends StatelessWidget {
  const AdvocateCard({
    super.key,
    required this.advocate,
    this.online,
    this.onTap,
    this.saved = false,
    this.onSave,
  });

  final Advocate advocate;

  /// Null means "not known yet" rather than "offline" — presence arrives on a
  /// separate call, and a grey pill on a lawyer whose status has not loaded
  /// reads as offline when they may well be there.
  final bool? online;

  final VoidCallback? onTap;
  final bool saved;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    // The card leads with chat, the cheapest way in and the channel most
    // clients start on, then call. Video lives on the profile, where there is
    // room for all nine figures.
    //
    // These are the lawyer's own per-minute rates, the same figures the
    // website quotes beside each channel. The card used to read them out of
    // `slotPrices`, but no record the directory returns carries that field —
    // it is absent on the website's own payload too — so every lawyer fell
    // through to the 10-minute default and every card in the list quoted the
    // same ₹200, whether the lawyer charges ₹10 a minute or ₹1,000.
    final chatRate = advocate.chatRate;
    final callRate = advocate.audioRate;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap ?? () => context.push('/lawyers/${advocate.profilePath}'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.ink.withValues(alpha: 0.07)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _portrait(),
              const SizedBox(width: 12),
              Expanded(child: _details(chatRate, callRate)),
            ],
          ),
        ),
      ),
    );
  }

  /// The photograph, with the presence pill across its lower edge.
  ///
  /// On the photograph rather than beside the name because that is where the
  /// eye already is while scanning faces, and because "online" is the single
  /// most decision-changing fact on this card: it is the difference between
  /// talking to someone now and leaving a message.
  Widget _portrait() {
    return SizedBox(
      width: 78,
      height: 94,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 78,
              height: 94,
              // Through RemoteImage, because the list endpoint sends this as
              // a path relative to the API host and the detail endpoint sends
              // the same photograph as inline bytes. Handing either straight
              // to CachedNetworkImage is what used to leave every lawyer
              // showing their initial.
              child: RemoteImage(
                source: advocate.photo,
                width: 78,
                height: 94,
                placeholder: Container(
                  color: AppColors.primary.withValues(alpha: 0.06),
                ),
                fallback: _fallbackPortrait(),
              ),
            ),
          ),
          if (online != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: -7,
              child: Center(child: _presencePill(online!)),
            ),
        ],
      ),
    );
  }

  Widget _fallbackPortrait() => Container(
        color: AppColors.primary.withValues(alpha: 0.07),
        alignment: Alignment.center,
        child: Text(
          _initial,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      );

  String get _initial {
    final clean = advocate.name.replaceFirst(RegExp(r'^Adv\.?\s*'), '').trim();
    return clean.isEmpty ? '?' : clean[0].toUpperCase();
  }

  Widget _presencePill(bool isOnline) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isOnline ? AppColors.success : const Color(0xFF94A3B8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _details(int chatRate, int callRate) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name and badge share one flexible slot, with the save button
            // outside it. They used to be a Flexible beside a Spacer, and two
            // flex children of equal weight split the free space evenly — so a
            // name ellipsised at half the card's width while the other half
            // sat empty.
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      advocate.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  if (advocate.verified)
                    const Padding(
                      padding: EdgeInsets.only(left: 4, top: 2),
                      child: Icon(Icons.verified_rounded,
                          size: 15, color: AppColors.primary),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 26,
              height: 22,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 18,
                onPressed: onSave,
                icon: Icon(
                  saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: saved
                      ? const Color(0xFFEF4444)
                      : AppColors.ink.withValues(alpha: 0.28),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          _speciality,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.ink.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 5),
        _ratingLine(),
        if (_place.isNotEmpty) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(Icons.place_outlined,
                  size: 12, color: AppColors.ink.withValues(alpha: 0.4)),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  _place,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.ink.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 9),
        Row(
          children: [
            _pricePill(Icons.chat_bubble_outline_rounded, 'Chat', chatRate),
            const SizedBox(width: 8),
            _pricePill(Icons.call_outlined, 'Call', callRate),
          ],
        ),
      ],
    );
  }

  /// The lawyer's own tagline when they wrote one, otherwise their practice
  /// areas. Never invented — a lawyer with neither is simply "Advocate".
  String get _speciality {
    if (advocate.tagline.trim().isNotEmpty) return advocate.tagline.trim();
    if (advocate.specializations.isEmpty) return 'Advocate';
    return advocate.specializations.take(2).join(' & ');
  }

  /// Distance when the server worked one out, otherwise the city.
  ///
  /// Never both invented: "2 km away" on a lawyer whose distance was never
  /// computed is a number the reader will act on, and being wrong about how
  /// far away a lawyer is costs them a journey.
  String get _place {
    final km = advocate.distanceKm;
    if (km != null && km > 0) {
      final rounded = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
      return advocate.city.isEmpty
          ? '$rounded km away'
          : '$rounded km · ${advocate.city}';
    }
    return advocate.city;
  }

  Widget _ratingLine() {
    final bits = <Widget>[];

    // A rating of zero means nobody has reviewed them, not that they scored
    // nothing — so it is left out rather than shown as 0.0.
    if (advocate.rating > 0) {
      bits.addAll([
        const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
        const SizedBox(width: 2),
        Text(
          advocate.rating.toStringAsFixed(1),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        if (advocate.reviews > 0) ...[
          const SizedBox(width: 3),
          Text(
            '(${_compact(advocate.reviews)})',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.ink.withValues(alpha: 0.45),
            ),
          ),
        ],
      ]);
    }

    if (advocate.experience > 0) {
      if (bits.isNotEmpty) {
        bits.add(Text(
          '  ·  ',
          style: TextStyle(
            fontSize: 11.5,
            color: AppColors.ink.withValues(alpha: 0.3),
          ),
        ));
      }
      bits.add(Text(
        '${advocate.experience} Yrs',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.ink.withValues(alpha: 0.6),
        ),
      ));
    }

    if (bits.isEmpty) return const SizedBox.shrink();
    return Row(children: bits);
  }

  static String _compact(int n) {
    if (n >= 1000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k < 10 ? 1 : 0)}K';
    }
    return '$n';
  }

  /// "💬 ₹50 /min" — the icon says which channel, the large number what a
  /// minute of it costs.
  ///
  /// The unit has to be there: "₹50" alone reads as the price of the whole
  /// consultation, and on a twenty-minute call that misreading is out by a
  /// factor of twenty.
  ///
  /// A lawyer who has not set a rate gets the channel's name instead of a
  /// price, the way the website leaves the figure off rather than quoting ₹0 —
  /// which would read as "free" for someone who simply has not priced it yet.
  Widget _pricePill(IconData icon, String channel, int perMinute) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 5),
          if (perMinute <= 0)
            Text(
              channel,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            )
          else ...[
            Text(
              Fmt.money(perMinute),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            Text(
              '/min',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.primary.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

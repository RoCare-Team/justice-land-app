import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Bottom padding for a scrollable that may sit under the shell's tab bar.
///
/// The shell Scaffold sets `extendBody`, so the tab bar floats over the body
/// and the last row of any list would otherwise finish behind it — which is
/// exactly where a call-to-action or the last lawyer in a page ends up.
/// Scaffold reports the bar's height as the body's bottom padding, so reading
/// it here clears the bar on a shell screen and the home indicator on a pushed
/// one, without either screen having to know which it is.
double bottomGutter(BuildContext context, [double extra = 28]) =>
    MediaQuery.paddingOf(context).bottom + extra;

/// A screen whose own coloured header runs up under the status bar.
///
/// Android draws every app edge to edge, so a list scrolls under the clock and
/// the battery icon unless something stops it — which is how rows of lawyer
/// cards ended up with the signal bars printed across their names. This lays a
/// band the height of the status bar in the header's own colour over the top of
/// the page: against the header it is invisible, and once the header has
/// scrolled away it is what the rows pass behind instead of under the icons.
class HeaderStatusBand extends StatelessWidget {
  const HeaderStatusBand({
    super.key,
    required this.child,
    this.color = AppColors.primary,
    this.gradient,
  });

  final Widget child;

  /// Matches the header the band sits in front of.
  final Color color;

  /// For a header that is not one flat colour. Painting a solid band over a
  /// gradient leaves a seam across the top of the screen, so a screen with a
  /// gradient header hands its own here; [color] is ignored when this is set.
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The band is the darkest thing under the status bar, so the icons on it
      // have to be the light ones whether the header is in view or not.
      value: SystemUiOverlayStyle.light,
      child: Stack(
        children: [
          child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: MediaQuery.paddingOf(context).top,
                decoration: BoxDecoration(
                  color: gradient == null ? color : null,
                  gradient: gradient,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Any image the backend hands us, however it chose to hand it over.
///
/// This platform serves the same photograph three different ways depending on
/// which endpoint you asked, and every one of them needs different handling:
///
///   `/api/advocates/<id>/photo`   a path relative to the API host — the list
///                                 endpoint sends this, because the photos are
///                                 megabytes and must not travel inside a
///                                 directory payload
///   `data:image/jpeg;base64,...`  the bytes inline — the detail endpoint sends
///                                 this, since it is reading the one document
///                                 anyway
///   `https://...`                 an absolute URL
///
/// Every call site used to pick one of those and get the other two wrong.
/// `CachedNetworkImage` cannot load a `data:` URI at all, and it cannot load a
/// bare `/api/...` path either, so lawyers with a photograph were showing their
/// initials on the cards *and* on their own profile. Deciding this once, here,
/// is what stops that from coming back the next time an endpoint changes which
/// form it sends.
class RemoteImage extends StatelessWidget {
  const RemoteImage({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.fallback,
  });

  /// Whatever the API gave us: a path, a data URI, or an absolute URL.
  final String? source;

  final BoxFit fit;
  final double? width;
  final double? height;

  /// Shown while a network image loads. Never shown for inline bytes, which
  /// are already here.
  final Widget? placeholder;

  /// Shown when there is no image, or when one fails to load.
  final Widget? fallback;

  /// Absolute URL for a network image, or '' when [raw] is empty or inline.
  ///
  /// Returns '' for a `data:` URI on purpose: those carry their own bytes and
  /// have no URL to resolve. Prepending the API host to one — which is what
  /// this used to do — produces a nonsense address that always 404s.
  static String resolveUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';
    if (value.startsWith('data:')) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('//')) return 'https:$value';
    return '${AppConfig.baseUrl}${value.startsWith('/') ? '' : '/'}$value';
  }

  /// The bytes of a `data:` URI, or null for anything else.
  ///
  /// Malformed base64 returns null rather than throwing: one corrupt record
  /// should cost that lawyer their photograph, not blank the whole screen.
  static Uint8List? inlineBytes(String? raw) {
    final value = (raw ?? '').trim();
    if (!value.startsWith('data:')) return null;
    final comma = value.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(value.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  /// True when there is something to draw — so a caller can lay out a slot for
  /// an image only when one exists.
  static bool has(String? raw) =>
      resolveUrl(raw).isNotEmpty || inlineBytes(raw) != null;

  @override
  Widget build(BuildContext context) {
    final empty = fallback ?? const SizedBox.shrink();

    final bytes = inlineBytes(source);
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => empty,
      );
    }

    final url = resolveUrl(source);
    if (url.isEmpty) return empty;

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      placeholder: (_, __) => placeholder ?? Container(color: AppColors.muted),
      errorWidget: (_, __, ___) => empty,
    );
  }
}

/// A lawyer or client photo, falling back to their initial.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.photo,
    this.size = 44,
    this.online,
    this.onDark = false,
  });

  final String name;
  final String? photo;
  final double size;

  /// Null hides the dot entirely — "unknown" and "offline" are different
  /// things, and a grey dot on a lawyer whose status has not loaded reads as
  /// unavailable.
  final bool? online;

  /// Set on a dark header. The fallback is navy lettering on a navy tint,
  /// which is meant for a white page — on the lawyer header both halves were
  /// the same colour as the background and the circle read as empty.
  final bool onDark;

  /// Kept as the name every caller already uses; the rule itself lives in
  /// [RemoteImage] so there is one answer to "what is this image".
  static String resolveUrl(String? raw) => RemoteImage.resolveUrl(raw);

  @override
  Widget build(BuildContext context) {
    final initial = Text(
      Fmt.initial(name),
      style: TextStyle(
        fontSize: size * 0.38,
        fontWeight: FontWeight.w700,
        color: onDark ? Colors.white : AppColors.primary,
      ),
    );

    final avatar = Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onDark
            ? Colors.white.withValues(alpha: 0.16)
            : AppColors.primary.withValues(alpha: 0.10),
        border: Border.all(
          color: onDark ? Colors.white24 : AppColors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: RemoteImage(
        source: photo,
        width: size,
        height: size,
        fallback: initial,
      ),
    );

    if (online == null) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            height: size * 0.28,
            width: size * 0.28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online! ? AppColors.success : AppColors.inkFaint,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// Five stars plus the numeric rating, as on the profile header.
class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.reviews,
    this.size = 15,
    this.showValue = true,
  });

  final double rating;
  final int? reviews;
  final double size;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i <= rating.round() ? AppColors.accent : AppColors.ink.withOpacity(0.18),
          ),
        if (showValue) ...[
          const SizedBox(width: 6),
          Text(
            Fmt.rating(rating),
            style: TextStyle(
              fontSize: size * 0.85,
              fontWeight: FontWeight.w600,
              color: AppColors.inkStrong,
            ),
          ),
        ],
        if (reviews != null) ...[
          const SizedBox(width: 4),
          Text(
            '($reviews)',
            style: TextStyle(fontSize: size * 0.8, color: AppColors.inkFaint),
          ),
        ],
      ],
    );
  }
}

/// A small status pill. Colour carries meaning, so the tone is chosen from the
/// status rather than passed in ad hoc at each call site.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  final String label;
  final ChipTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsFor(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: colors.$2),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: colors.$2,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _colorsFor(ChipTone tone) {
    switch (tone) {
      case ChipTone.success:
        return (AppColors.successSoft, AppColors.success);
      case ChipTone.warning:
        return (AppColors.warningSoft, AppColors.warning);
      case ChipTone.danger:
        return (AppColors.dangerSoft, AppColors.danger);
      case ChipTone.info:
        return (AppColors.primary.withOpacity(0.08), AppColors.primary);
      case ChipTone.neutral:
        return (AppColors.ink.withOpacity(0.06), AppColors.inkMuted);
    }
  }
}

enum ChipTone { success, warning, danger, info, neutral }

/// A tappable filter chip, used for practice areas, courts and languages.
class SelectableChip extends StatelessWidget {
  const SelectableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary.withOpacity(0.09) : AppColors.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.primary.withOpacity(0.55) : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 15, color: AppColors.primary),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? AppColors.primary
                      : (enabled ? AppColors.inkStrong : AppColors.inkFaint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled panel — the mobile equivalent of the site's card sections.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: Theme.of(context).textTheme.titleLarge),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// A labelled value row, for profile details.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.inkFaint),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps a list of chips with sensible spacing.
class ChipWrap extends StatelessWidget {
  const ChipWrap({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Text('—', style: TextStyle(color: AppColors.inkFaint));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: children);
  }
}

/// A read-only tag.
class Tag extends StatelessWidget {
  const Tag({super.key, required this.label, this.tone});

  final String label;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
      ),
    );
  }
}

/// A full-width primary button that shows its own progress, so callers never
/// have to build a "disabled + spinner" state by hand.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// An inline message strip — the amber "awaiting approval" note, the red
/// "insufficient balance" warning.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.message,
    this.tone = ChipTone.info,
    this.icon,
    this.action,
  });

  final String message;
  final ChipTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    switch (tone) {
      case ChipTone.success:
        bg = AppColors.successSoft;
        fg = AppColors.success;
      case ChipTone.warning:
        bg = AppColors.warningSoft;
        fg = AppColors.warning;
      case ChipTone.danger:
        bg = AppColors.dangerSoft;
        fg = AppColors.danger;
      case ChipTone.info:
        bg = AppColors.primary.withOpacity(0.06);
        fg = AppColors.primary;
      case ChipTone.neutral:
        bg = AppColors.ink.withOpacity(0.05);
        fg = AppColors.inkMuted;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline_rounded, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, height: 1.45, color: fg),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

/// A Material icon for a practice area, chosen by its slug.
///
/// The website draws these from a React component stored on each category,
/// which cannot be serialised and would mean nothing here — so `/api/services`
/// deliberately does not send one and the mapping lives on this side instead.
///
/// Matching is on the slug rather than the display name because a slug is the
/// stable half: a category can be renamed on the web without its URL changing,
/// and an icon that survives a rename is worth more than one that reads nicely
/// in this table. Anything unrecognised — a practice area added after this
/// build — gets the gavel, which is at least true of all of them.
IconData serviceIcon(String slug) {
  switch (slug) {
    case 'civil-lawyer':
      return Icons.account_balance_outlined;
    case 'criminal-lawyer':
      return Icons.gavel_rounded;
    case 'family-lawyer':
      return Icons.family_restroom_rounded;
    case 'property-lawyer':
      return Icons.home_work_outlined;
    case 'corporate-lawyer':
      return Icons.business_center_outlined;
    case 'tax-lawyer':
      return Icons.receipt_long_outlined;
    case 'labour-lawyer':
      return Icons.engineering_outlined;
    case 'constitutional-lawyer':
      return Icons.menu_book_rounded;
    case 'consumer-lawyer':
      return Icons.shopping_bag_outlined;
    case 'intellectual-property-lawyer':
      return Icons.lightbulb_outline_rounded;
    case 'real-estate-lawyer':
      return Icons.apartment_rounded;
    case 'immigration-lawyer':
      return Icons.flight_takeoff_rounded;
    default:
      return Icons.gavel_rounded;
  }
}

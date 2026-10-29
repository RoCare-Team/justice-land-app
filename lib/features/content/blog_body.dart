import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';

/// An article's body, drawn natively: headings, paragraphs, bullet lists,
/// **bold** and tappable links.
///
/// Articles arrive either as the website's plain format ("## " headings,
/// blank lines between paragraphs, `[text](url)` links, `**bold**`) or, for
/// older posts, as HTML. HTML is first turned into the plain format, so both
/// render the same way and no web view is involved.
///
/// A link to a Justiceland page the app has (an article, a lawyer, a legal
/// service) opens that screen in the app; anything else opens outside.
class BlogBody extends StatefulWidget {
  const BlogBody({super.key, required this.content});

  final String content;

  @override
  State<BlogBody> createState() => _BlogBodyState();
}

class _BlogBodyState extends State<BlogBody> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final blocks = _toPlain(widget.content)
        .split(RegExp(r'\n{2,}'))
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty);

    const body = TextStyle(fontSize: 15, height: 1.7, color: AppColors.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks)
          if (block.startsWith('## '))
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Text.rich(_inline(block.substring(3).trim(),
                  const TextStyle(fontSize: 18, height: 1.35, fontWeight: FontWeight.w800, color: AppColors.ink))),
            )
          else if (block.split('\n').every((l) => l.trimLeft().startsWith('•')))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in block.split('\n'))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 10, right: 10),
                            child: CircleAvatar(radius: 2.5, backgroundColor: AppColors.accent),
                          ),
                          Expanded(child: Text.rich(_inline(line.trimLeft().substring(1).trim(), body))),
                        ],
                      ),
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text.rich(_inline(block, body)),
            ),
      ],
    );
  }

  /// Links and bold inside one block, as spans.
  TextSpan _inline(String text, TextStyle base) {
    final re = RegExp(
      r'\[([^\]\n]+)\]\(((?:[^()\s]|\([^()\s]*\))+)\)' // [text](url)
      r'|\*\*([^*\n]+)\*\*' // **bold**
      r'''|((?:https?://|www\.)[^\s<>"]*[^\s<>".,;:!?'")\]])''', // bare address
    );
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      if (m.group(1) != null) {
        spans.add(_link(m.group(1)!, m.group(2)!));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(text: m.group(3), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else {
        spans.add(_link(m.group(4)!, m.group(4)!));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: base, children: spans);
  }

  InlineSpan _link(String label, String href) {
    final url = _safe(href);
    if (url == null) return TextSpan(text: label);
    final recognizer = TapGestureRecognizer()..onTap = () => _open(url);
    _recognizers.add(recognizer);
    return TextSpan(
      text: label,
      recognizer: recognizer,
      style: const TextStyle(
        color: AppColors.info,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.info,
      ),
    );
  }

  /// A web address, a path on the site, mailto: or tel: — never anything else.
  static String? _safe(String href) {
    final u = href.trim();
    if (RegExp(r'^https?://[^\s<>"]+$', caseSensitive: false).hasMatch(u)) return u;
    if (RegExp(r'^www\.[^\s<>"]+\.[^\s<>"]+$', caseSensitive: false).hasMatch(u)) return 'https://$u';
    if (RegExp(r'^/(?!/)[^\s<>"]*$').hasMatch(u)) return u;
    if (RegExp(r'^(mailto|tel):', caseSensitive: false).hasMatch(u)) return u;
    return null;
  }

  /// In-app screens for the site's own pages, the outside world for the rest.
  void _open(String url) {
    var path = url;
    final own = RegExp(r'^https?://(www\.)?justiceland\.online', caseSensitive: false);
    if (own.hasMatch(path)) path = path.replaceFirst(own, '');
    if (path.isEmpty) path = '/';

    if (path.startsWith('/')) {
      const inApp = ['/blogs', '/lawyers', '/services', '/document-review', '/consultations', '/wallet', '/contact'];
      final clean = path.split('#').first.split('?').first;
      final known = clean == '/' || inApp.any((p) => clean == p || clean.startsWith('$p/'));
      if (known) {
        context.push(clean);
        return;
      }
      launchUrl(Uri.parse('https://www.justiceland.online$path'), mode: LaunchMode.externalApplication);
      return;
    }
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// HTML (older posts) to the plain format; plain text passes through.
  static String _toPlain(String input) {
    if (!RegExp(r'</?[a-z][^>]*>', caseSensitive: false).hasMatch(input)) return input;
    var s = input.replaceAll('\r\n', '\n');
    s = s.replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), '');
    s = s.replaceAllMapped(
      RegExp(r'''<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>([\s\S]*?)</a>''', caseSensitive: false),
      (m) {
        final label = _strip(m.group(4) ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        final href = (m.group(1) ?? m.group(2) ?? m.group(3) ?? '').trim();
        return label.isEmpty ? href : '[$label]($href)';
      },
    );
    s = s.replaceAllMapped(RegExp(r'<(strong|b)\b[^>]*>([\s\S]*?)</\1>', caseSensitive: false),
        (m) => '**${_strip(m.group(2) ?? '').trim()}**');
    s = s.replaceAllMapped(RegExp(r'<h[1-6][^>]*>([\s\S]*?)</h[1-6]>', caseSensitive: false),
        (m) => '\n\n## ${_strip(m.group(1) ?? '').replaceAll(RegExp(r'\s+'), ' ').trim()}\n\n');
    s = s.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</(p|div|ul|ol|blockquote|section)>', caseSensitive: false), '\n\n');
    s = _strip(s)
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&mdash;', '—');
    return s
        .split('\n')
        .map((l) => l.trim())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAllMapped(RegExp(r'(\n• [^\n]*)\n\n(?=• )'), (m) => '${m.group(1)}\n')
        .trim();
  }

  static String _strip(String s) => s.replaceAll(RegExp(r'</?[a-z][^>]*>', caseSensitive: false), '');
}

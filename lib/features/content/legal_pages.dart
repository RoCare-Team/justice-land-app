import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';

/// About, Privacy, Terms, Disclaimer and Refund — shown inside the app.
///
/// These used to open the website in Safari, which App Review reads as the
/// app being a wrapper around the site (Guideline 4.3). They are now native
/// screens. The wording is the website's own (src/app/<page>/page.js in the
/// web repo); when a policy changes there, change it here too.

const String _supportEmail = 'support@justiceland.online';

/// One block of a page: a heading, a paragraph, or a list of bullets.
/// `**text**` inside a paragraph or bullet is bold.
sealed class _Block {
  const _Block();
}

class _H extends _Block {
  const _H(this.text);
  final String text;
}

class _P extends _Block {
  const _P(this.text);
  final String text;
}

class _Bullets extends _Block {
  const _Bullets(this.items);
  final List<String> items;
}

class _Steps extends _Block {
  const _Steps(this.items);
  final List<({String title, String text})> items;
}

class _LegalDoc {
  const _LegalDoc({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.blocks,
    this.updated = '',
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String updated;
  final List<_Block> blocks;
}

const _contactLine = 'Questions? Email $_supportEmail.';

final Map<String, _LegalDoc> _docs = {
  'about': const _LegalDoc(
    title: 'About Justiceland',
    subtitle: 'Connecting India with trusted lawyers.',
    icon: Icons.balance_rounded,
    blocks: [
      _P('A directory where every advocate is verified before they are listed, states their fee upfront, '
          'and can be consulted without you giving up your name.'),
      _H('A directory, not a law firm'),
      _P('Finding a lawyer in India usually runs on whoever a relative happens to know. Justiceland lets you '
          'search verified advocates by practice area, city, language and fee, compare them, and consult them '
          'by chat, phone call or video — at a rate shown before you book.'),
      _H('What we stand for'),
      _Steps([
        (title: 'Verified before published', text: 'A profile is reviewed against the Bar Council details it claims before it appears in the directory at all.'),
        (title: 'Findable by what matters', text: 'Filter by practice area, city, language, years in practice and fee — not by who paid for placement.'),
        (title: 'Fair to advocates too', text: 'Advocates set their own rates for chat, call and video. We do not fix them.'),
        (title: 'Ask without saying who you are', text: 'Anonymity is a setting, not a marketing line — you can consult without sharing your name.'),
      ]),
      _H('Three ways to consult'),
      _Steps([
        (title: 'Live chat', text: 'A text session with the advocate. The conversation is saved, so booking the same advocate again picks up where you left off.'),
        (title: 'Phone call', text: 'Talk to the advocate in the app. Neither side sees the other\'s number.'),
        (title: 'Video call', text: 'A face-to-face consultation inside the app, peer to peer.'),
      ]),
      _H('How it works for clients'),
      _Steps([
        (title: 'Search', text: 'By practice area and city, or by what your matter actually is — bail, maintenance, eviction, a cheque that bounced.'),
        (title: 'Compare', text: 'Years in practice, courts, languages, reviews and the fee, before you commit.'),
        (title: 'Top up your wallet', text: 'Nothing is charged until an advocate accepts your request.'),
        (title: 'Consult', text: 'The advocate accepts, the session opens, and you pay only for the minutes it runs.'),
      ]),
      _H('How it works for advocates'),
      _Steps([
        (title: 'Register', text: 'Bar Council number, practice areas, courts, languages, city and your fee.'),
        (title: 'Get reviewed', text: 'Your profile stays private until it has been checked.'),
        (title: 'Take clients', text: 'Go online when you are available, accept the requests that suit you, and earnings are credited as sessions run.'),
      ]),
      _H('Contact'),
      _P(_contactLine),
    ],
  ),
  'privacy': const _LegalDoc(
    title: 'Privacy Policy',
    subtitle: 'How we collect, use and protect your information.',
    icon: Icons.shield_outlined,
    updated: '9 July 2026',
    blocks: [
      _P('Justiceland ("we", "us") respects your privacy. This policy explains what information we collect '
          'when you use our lawyer directory platform and how we use it.'),
      _H('Information we collect'),
      _Bullets([
        '**Lawyer accounts:** name, email, phone, city, bar council number, professional details, photos and any profile content you provide.',
        '**Visitors:** search queries and basic usage data to improve the service.',
        '**Contact requests:** details you submit through our contact or enquiry forms.',
      ]),
      _H('How we use your information'),
      _Bullets([
        'To create and display lawyer profiles in the public directory.',
        'To let clients discover and contact lawyers.',
        'To operate, secure and improve the platform.',
        'To send account-related messages such as password reset codes.',
      ]),
      _H('Public profiles'),
      _P('Information a lawyer adds to their profile (including name, city, contact details and photos) is '
          '**publicly visible** by design, so that clients can find and reach them. Do not add information you '
          'do not want to be public.'),
      _H('Data security'),
      _P('Passwords are stored only as secure hashes and are never visible to us. We use reasonable technical '
          'measures to protect your data, but no online service can be guaranteed 100% secure.'),
      _H('Your choices'),
      _P('You can edit your profile at any time, or permanently delete your account from the app '
          '(More → Delete account). To raise any privacy request, contact us at $_supportEmail.'),
      _H('Contact'),
      _P('Questions about this policy? Email $_supportEmail.'),
    ],
  ),
  'terms': const _LegalDoc(
    title: 'Terms of Service',
    subtitle: 'The terms that govern your use of our platform.',
    icon: Icons.description_outlined,
    updated: '9 July 2026',
    blocks: [
      _P('By accessing or using Justiceland, you agree to these Terms. If you do not agree, please do not use the platform.'),
      _H('About the platform'),
      _P('Justiceland is a lawyer discovery and directory platform. We are **not a law firm** and do not provide '
          'legal advice, representation or referrals. We simply help clients find and contact lawyers.'),
      _H('Lawyer accounts'),
      _Bullets([
        'You must provide accurate, up-to-date information and be entitled to practise as a lawyer.',
        'You are responsible for your account credentials and all activity under your account.',
        'You must not post false, misleading, unlawful or infringing content.',
        'We may suspend or remove profiles that violate these Terms.',
      ]),
      _H('Client use'),
      _P('Listings do not constitute endorsements. You are responsible for independently verifying a lawyer\'s '
          'credentials and for any engagement you enter into with them.'),
      _H('Intellectual property'),
      _P('The platform, its design and branding belong to Justiceland. Content you submit remains yours, but you '
          'grant us a licence to display it on the platform.'),
      _H('Limitation of liability'),
      _P('The platform is provided "as is". To the extent permitted by law, we are not liable for any dealings '
          'between clients and lawyers, or for any loss arising from use of the platform.'),
      _H('Changes'),
      _P('We may update these Terms from time to time. Continued use of the platform means you accept the updated Terms.'),
      _H('Contact'),
      _P(_contactLine),
    ],
  ),
  'disclaimer': const _LegalDoc(
    title: 'Disclaimer',
    subtitle: 'Please read this before relying on any information on the platform.',
    icon: Icons.gavel_rounded,
    updated: '9 July 2026',
    blocks: [
      _H('Not a law firm'),
      _P('Justiceland is a lawyer discovery and directory platform. It is **not a law firm** and does not provide '
          'legal advice, opinions, representation or referrals. Nothing on this platform should be treated as legal advice.'),
      _H('No attorney–client relationship'),
      _P('Browsing profiles or contacting a lawyer through this platform does not create an attorney–client '
          'relationship. Such a relationship is formed only directly between you and the lawyer, on terms you agree with them.'),
      _H('Accuracy of listings'),
      _P('Profile information is provided by lawyers themselves. While we encourage accuracy, we do not independently '
          'guarantee the qualifications, experience, availability or conduct of any lawyer. Listings do not constitute '
          'endorsements. Please verify credentials independently before engaging anyone.'),
      _H('Your responsibility'),
      _P('Any decision you make based on information found here is at your own discretion and risk. We are not '
          'responsible for the outcome of any engagement between clients and lawyers.'),
      _H('Contact'),
      _P('Questions about this disclaimer? Email $_supportEmail.'),
    ],
  ),
  'refund': const _LegalDoc(
    title: 'Refund & Cancellation Policy',
    subtitle: 'How payments, refunds and cancellations work.',
    icon: Icons.currency_rupee_rounded,
    updated: '9 July 2026',
    blocks: [
      _H('Free directory listing'),
      _P('Creating a lawyer profile and appearing in the Justiceland directory is currently **free of charge**. '
          'There is nothing to refund for a free listing.'),
      _H('Paid plans (when available)'),
      _P('If we introduce paid or premium plans in future, the following will apply unless stated otherwise at the time of purchase:'),
      _Bullets([
        'You may cancel a subscription at any time from your dashboard; it will not renew for the next cycle.',
        'Fees already paid for the current billing period are generally non-refundable.',
        'If you are charged in error or due to a technical fault, contact us and we will review and, where appropriate, refund it.',
      ]),
      _H('Consultation fees'),
      _P('Any consultation or professional fee you pay **directly to a lawyer** is between you and that lawyer. '
          'Justiceland does not collect these fees and is not responsible for their refund. Please discuss fee and '
          'refund terms directly with the lawyer.'),
      _H('How to request a refund'),
      _P('For any eligible refund, email $_supportEmail with your account email and payment details. Approved refunds '
          'are processed to the original payment method, typically within 5–7 working days.'),
    ],
  ),
};

/// The ids [LegalPageScreen] knows — for routes and menus.
const legalPageIds = ['about', 'privacy', 'terms', 'disclaimer', 'refund'];

class LegalPageScreen extends StatelessWidget {
  const LegalPageScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final doc = _docs[id];
    if (doc == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: TextButton(onPressed: () => context.go('/'), child: const Text('Back to home')),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(title: Text(doc.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(colors: [AppColors.primaryLight, AppColors.primaryDark]),
            ),
            child: Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(doc.icon, color: AppColors.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.title,
                        style: const TextStyle(
                          fontFamily: AppText.display,
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(doc.subtitle, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
                      if (doc.updated.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('Last updated ${doc.updated}',
                            style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final b in doc.blocks) _block(context, b)],
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse('mailto:$_supportEmail')),
            icon: const Icon(Icons.mail_outline_rounded, size: 18),
            label: const Text('Email $_supportEmail'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          ),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, _Block b) {
    const body = TextStyle(fontSize: 14.5, height: 1.6, color: AppColors.ink);
    return switch (b) {
      _H(:final text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
        ),
      _P(:final text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text.rich(_rich(text, body)),
        ),
      _Bullets(:final items) => Column(
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 8, right: 10),
                      child: CircleAvatar(radius: 2.5, backgroundColor: AppColors.accent),
                    ),
                    Expanded(child: Text.rich(_rich(item, body))),
                  ],
                ),
              ),
          ],
        ),
      _Steps(:final items) => Column(
          children: [
            for (var i = 0; i < items.length; i++)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 26,
                      width: 26,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: Text('${i + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(items[i].title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(items[i].text, style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
    };
  }

  /// `**bold**` inside a line, as spans.
  static TextSpan _rich(String text, TextStyle base) {
    final parts = text.split('**');
    return TextSpan(
      style: base,
      children: [
        for (var i = 0; i < parts.length; i++)
          TextSpan(text: parts[i], style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null),
      ],
    );
  }
}

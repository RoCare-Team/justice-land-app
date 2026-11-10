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
    subtitle: 'What we collect, why, who can see it, how long we keep it and your rights.',
    icon: Icons.shield_outlined,
    updated: '2 November 2026',
    blocks: [
      _H('1. Introduction'),
      _P('Justice Land ("we" and "us") respects your privacy and is committed to handling your personal data responsibly. This Privacy Notice explains what personal information we collect when you use the Justice Land website and mobile app, why we collect it, how we use and protect it, who can see it, how long we keep it, and what rights and choices you have.'),
      _P('Justice Land is a real-time talk platform that provides legal assistance through direct interaction with verified lawyers across India via call and chat, and also provides draft legal documents as needed. Please read this notice carefully before you use the portal or give your consent.'),
      _P('This notice is given under the Digital Personal Data Protection Act, 2023 (the "DPDP Act") and the rules made under it. For the personal data described here, Justice Land is the **Data Fiduciary** and you are the **Data Principal**. You can ask us for this notice in English or in any language listed in the Eighth Schedule to the Constitution of India.'),
      _P('Justice Land is an online directory of advocates. It does not rank, badge or endorse any advocate, does not make promises about the outcome of any matter, and does not run offers or discounts on legal services.'),
      _H('2. Who This Notice Applies To'),
      _P('This notice applies to every individual who enrols, or begins to enrol, on Justice Land as a lawyer. That includes:'),
      _Bullets([
        'Advocates, attorneys and other legal practitioners licensed to practise in India, whether they practise alone or through a law firm, chambers or legal aid organization.',
        'Staff or representatives (for example, firm administrators, clerks or marketing personnel) who create or manage a profile on a lawyer\'s behalf, in respect of their own data as well as the lawyer\'s.',
      ]),
      _P('It covers personal data we collect through the Justice Land website (https://www.justiceland.online/), our mobile apps, emails, phone calls and any other channel connected with your enrolment, whether online or offline.'),
      _H('3. Information We Collect'),
      _Bullets([
        '**Identity and contact details:** full name, photograph, email address, phone number, office address, city and state, preferred language(s).',
        '**Professional credentials:** Bar Council/bar association enrolment number, state bar of registration, year of enrolment, court(s) of practice, copies of your enrolment certificate and certificate of practice or equivalent, and identity proof used to verify you.',
        '**Professional profile:** practice areas, years of experience, education, languages, firm name, awards, publications, areas of specialization, consultation fees, availability, and a short biography.',
        '**Account details:** username, password (stored in encrypted form), security questions, and notification preferences.',
        '**Payment and billing details:** billing name, GST or tax number (if applicable), and payment information processed by our payment partners. We do not store full card numbers.',
        '**Communications:** messages you send to us, to Clients through the platform, support requests, reviews and feedback.',
      ]),
      _H('3.1 Information we collect automatically'),
      _Bullets([
        '**Device and usage data:** IP address, browser type, device identifiers, operating system, pages viewed, time spent, referring pages, and actions taken on the platform.',
        '**Cookies and tracking:** see Section 10.',
        '**Approximate location:** derived from your IP address or, with your permission, your device, to show you relevant matters and to show Clients nearby Lawyers.',
      ]),
      _H('3.2 Information we collect from other sources'),
      _Bullets([
        '**Verification sources:** Bar Councils, court records, and other public registers, to confirm your enrolment and good standing.',
        '**Clients:** where a Client contacts or reviews you, we receive the details they provide about the inquiry and their feedback about you.',
        '**Public sources:** professional information you have made public, such as your firm website or professional directories, used to check or enrich your profile.',
      ]),
      _P('We do not intentionally collect sensitive categories of personal data beyond what is needed to verify your professional identity. If you provide any, such as disciplinary history or health information, you do so voluntarily, and we will treat it with additional care.'),
      _H('4. How We Use Your Information and Why'),
      _Bullets([
        '**Creating and managing your account:** Registration, login, authentication, account support. Ground: Your consent.',
        '**Verifying your credentials:** Checking enrolment and good standing, preventing impersonation. Ground: Your consent; compliance with law.',
        '**Listing you in the directory:** Displaying your profile in directory search results, passing Client requests to you. Ground: Your consent.',
        '**Facilitating communication:** Passing Client inquiries to you, enabling calls and messaging, scheduling consultations. Ground: Your consent.',
        '**Payments and invoicing:** Subscription fees, refunds, tax records. Ground: Your consent; compliance with law.',
        '**Improving Justice Land:** Analytics, fixing bugs, testing features. Ground: Your consent.',
        '**Safety, fraud prevention and security:** Detecting fake profiles, misuse, unauthorized access. Ground: Your consent; compliance with law.',
        '**Service updates:** Product news and newsletters (you can opt out at any time). Ground: Your consent.',
        '**Legal compliance:** Responding to lawful requests, maintaining records required by law. Ground: Legitimate use under Section 7 of the DPDP Act (compliance with law, a judgment or an order).',
      ]),
      _P('We do not use your personal data for purposes that are incompatible with those listed above without telling you and, where required, obtaining your consent.'),
      _P('**Your consent.** Where we rely on consent, it is free, specific, informed, unconditional and unambiguous, and limited to the personal data needed for the stated purpose. You can withdraw it at any time, as easily as you gave it, from your account settings or by contacting us (Section 15). You may also give, manage or withdraw consent through a Consent Manager registered with the Data Protection Board of India. After you withdraw consent, we stop processing the data for that purpose within a reasonable time, unless the law requires us to keep it.'),
      _H('5. What Clients Can See'),
      _P('When you enrol, the following parts of your profile are public or visible to Clients: your name, photograph, practice areas, location, languages, experience, firm name, biography, fees (if you choose to list them), and ratings or reviews. We do not show badges, rankings or labels that promote one advocate over another.'),
      _P('Your enrolment certificate, identity proof, billing information, and account credentials are never shown to Clients.'),
      _P('Your contact details (phone and email) are shared with a Client only when you choose to publish them on your profile. You can control your visibility in your account settings.'),
      _P('Public profile information may be indexed by search engines. You can ask us to limit this, subject to the technical limits of search engines.'),
      _H('6. Who We Share Your Information With'),
      _P('We do not sell your personal data. We share it only as follows:'),
      _Bullets([
        '**Clients:** profile information and, where applicable, contact details, as described in Section 5.',
        '**Service providers (processors):** companies that help us run Justice Land, such as cloud hosting, payment processing, identity verification, email and SMS delivery, analytics, customer support and security. They may process your data only on our instructions and under confidentiality and security obligations.',
        '**Professional bodies and verification authorities:** Bar Councils or similar bodies, to verify your credentials or to respond to a complaint or inquiry.',
        '**Legal and regulatory authorities:** courts, law enforcement, or government bodies, where we are legally required to or believe disclosure is necessary to protect rights, safety, or property.',
        '**Business transfers:** a successor entity if Justice Land is involved in a merger, acquisition, financing, or sale of assets, subject to this notice continuing to apply or you being notified of any change.',
        '**With your consent:** any other third party, where you have asked or agreed to it.',
      ]),
      _H('7. Client Confidentiality and Your Professional Duties'),
      _P('Justice Land is a directory and communication platform. We are not a law firm and do not provide legal advice or form attorney-client relationships.'),
      _P('Please do not upload or send privileged or confidential client information through Justice Land unless a feature is expressly designed for that purpose. You remain solely responsible for complying with your professional duties of confidentiality and with the rules of your Bar Council or regulatory body, including rules on advertising, solicitation, and fee disclosure.'),
      _H('8. International Transfers'),
      _P('Your data may be stored or processed on servers located in India and in other countries, including by our service providers. Where data is transferred outside your country, we take steps to ensure it remains protected, in line with applicable law and any government restrictions on cross-border transfers.'),
      _H('9. How Long We Keep Your Information'),
      _Bullets([
        '**Account and profile data:** until you delete your account.',
        '**Verification documents:** until verification is complete and 3 years afterwards, or as required by law.',
        '**Payment and tax records:** 3 years, or as required by tax and accounting law.',
        '**Client inquiry and communication records:** 3 years.',
        '**Support records:** 3 years.',
        '**Logs and security records:** 3 years.',
      ]),
      _P('When data is no longer needed, we delete or anonymize it. We may keep limited records longer where necessary for legal claims, fraud prevention, or to comply with the law.'),
      _H('10. Cookies and Tracking'),
      _P('We use cookies and similar technologies to keep you signed in, remember your preferences, secure the platform, understand how Justice Land is used, and measure our marketing. You can manage cookies through your browser settings. Disabling some cookies may affect how the platform works. We honour browser signals and legal requirements for consent to non-essential cookies where applicable.'),
      _H('11. How We Protect Your Information'),
      _P('We use reasonable technical and organizational safeguards, including encryption in transit, access controls, regular security reviews, staff confidentiality obligations, and secure storage of credentials. No system is completely secure. Please use a strong, unique password and tell us immediately if you suspect unauthorized access to your account.'),
      _P('If a personal data breach affects you, we will inform you without delay, along with what happened, its likely impact and the steps you can take, and we will report it to the Data Protection Board of India, as the DPDP Act and its rules require.'),
      _H('12. Your Rights and Choices'),
      _P('Under the DPDP Act (Sections 11 to 14) and other applicable law, you may:'),
      _Bullets([
        '**Access** a summary of the personal data we hold about you and how it is processed.',
        '**Correct or update** inaccurate or incomplete data. You can edit most details directly in your account.',
        '**Erase** your data when it is no longer needed for the purpose it was collected, or when you withdraw consent, unless we must retain it by law.',
        '**Withdraw consent** at any time. This does not affect processing already carried out, and may limit your ability to use some features.',
        '**Object to or restrict** certain processing, such as direct marketing.',
        '**Data portability**, where applicable, receiving your data in a commonly used format.',
        '**Nominate** another person to exercise your rights on your behalf in the event of your death or incapacity, where the law allows.',
        '**Grievance redressal:** raise a complaint with us (see Section 15) and, if unresolved, with the relevant data protection authority (e.g., the Data Protection Board of India).',
      ]),
      _P('To exercise any right, contact us using the details in Section 15. We may need to verify your identity before acting on your request, and we will respond within 30 days or the period required by law.'),
      _P('**Your duties.** Under Section 15 of the DPDP Act, you must not impersonate another person, suppress material information or give false details (including about your enrolment or credentials), or file a false or frivolous grievance or complaint.'),
      _H('13. Account Closure'),
      _P('You may close your account at any time from your settings or by contacting us. After closure, your profile will no longer be visible to Clients. We will delete or anonymize your data in accordance with Section 9. Reviews or messages already exchanged with Clients may be retained in anonymized form or where needed to protect the other party\'s rights.'),
      _H('14. Children'),
      _P('Justice Land is intended for qualified legal professionals and is not directed at anyone under 18. We do not knowingly collect personal data from minors. If you believe a minor has provided data, please contact us, and we will delete it.'),
      _H('15. Contact Us and Grievance Redressal'),
      _P('For questions, requests, or complaints about this notice or your data:'),
      _Bullets([
        '**Email:** support@justiceland.online',
        '**Phone:** +91 85100 99972',
        '**Grievance Officer (contact for questions about your personal data):** Yogita Yadav, Associate',
        '**Registered address:** Unit 831, JMD Megapolis, Sohna Road, Sector 48, Gurugram, Haryana 122018',
        '**Response time:** we aim to acknowledge complaints within 48 hours and resolve them within 30 days.',
      ]),
      _P('If you are not satisfied with our response, you may complain to the Data Protection Board of India after first using our grievance process.'),
      _H('16. Changes to This Notice'),
      _P('We may update this notice from time to time. If changes are significant, we will notify you by email or through the platform before they take effect and, where required, ask for fresh consent. The "Last updated" date at the top shows when this notice was last revised. Continued use of Justice Land after changes take effect means you accept the updated notice, where the law permits.'),
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

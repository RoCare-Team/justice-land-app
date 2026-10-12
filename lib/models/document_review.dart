import 'json.dart';

/// Document reviews — the two ways a client has a legal document checked.
///
///  * `ai` — **Smart Document Check**: an AI reads every clause and lists
///    risks, red flags and missing terms in about a minute. Flat price.
///  * `expert` — **Advocate Document Opinion**: a verified lawyer reads it
///    and writes an opinion within a day. Priced by the page.
///
/// Mirrors the website's /api/document-review exactly.

class ReviewArea {
  const ReviewArea(this.value, this.label);
  final String value;
  final String label;

  factory ReviewArea.fromJson(Map<String, dynamic> j) =>
      ReviewArea(J.str(j['value']), J.str(j['label']));
}

/// What the two products cost and accept, from the server — never hard-coded,
/// so a price change on the website reaches the app without a release.
class ReviewPricing {
  const ReviewPricing({
    required this.aiFee,
    required this.aiMaxPages,
    required this.aiAvailable,
    required this.ratePerPage,
    required this.ratePerPageLong,
    required this.longFromPages,
    required this.deliveryHours,
    required this.maxBytes,
    required this.areas,
  });

  final int aiFee;
  final int aiMaxPages;
  final bool aiAvailable;
  final int ratePerPage;
  final int ratePerPageLong;
  final int longFromPages;
  final int deliveryHours;
  final int maxBytes;
  final List<ReviewArea> areas;

  /// The website's figures, for the moment before the server answers.
  static const fallback = ReviewPricing(
    aiFee: 199,
    aiMaxPages: 50,
    aiAvailable: true,
    ratePerPage: 149,
    ratePerPageLong: 99,
    longFromPages: 11,
    deliveryHours: 24,
    maxBytes: 5 * 1024 * 1024,
    areas: [
      ReviewArea('property', 'Property (sale deed, rent / lease agreement)'),
      ReviewArea('corporate', 'Business (contract, NDA, partnership, MoU)'),
      ReviewArea('employment', 'Employment (offer letter, appointment, exit)'),
      ReviewArea('family', 'Family (will, gift deed, settlement)'),
      ReviewArea('notice', 'Legal notice or court paper'),
      ReviewArea('other', 'Something else'),
    ],
  );

  /// What a lawyer opinion on [pages] pages costs.
  int expertPrice(int pages) {
    final n = pages < 1 ? 1 : pages;
    return n * (n >= longFromPages ? ratePerPageLong : ratePerPage);
  }

  factory ReviewPricing.fromJson(Map<String, dynamic> j) {
    final ai = J.map(j['ai']);
    final expert = J.map(j['expert']);
    final areas = J.models(j['areas'], ReviewArea.fromJson);
    return ReviewPricing(
      aiFee: J.int$(ai['fee'], fallback.aiFee),
      aiMaxPages: J.int$(ai['maxPages'], fallback.aiMaxPages),
      aiAvailable: J.flag(ai['available'], true),
      ratePerPage: J.int$(expert['ratePerPage'], fallback.ratePerPage),
      ratePerPageLong: J.int$(expert['ratePerPageLong'], fallback.ratePerPageLong),
      longFromPages: J.int$(expert['longFromPages'], fallback.longFromPages),
      deliveryHours: J.int$(expert['deliveryHours'], fallback.deliveryHours),
      maxBytes: J.int$(j['maxBytes'], fallback.maxBytes),
      areas: areas.isEmpty ? fallback.areas : areas,
    );
  }
}

class ReviewFlag {
  const ReviewFlag({required this.title, this.detail = '', this.severity = ''});
  final String title;
  final String detail;

  /// 'low' | 'medium' | 'high' on red flags; empty on missing clauses.
  final String severity;

  factory ReviewFlag.fromJson(Map<String, dynamic> j) => ReviewFlag(
        title: J.str(j['title']),
        detail: J.str(j['detail']),
        severity: J.str(j['severity']),
      );
}

/// The AI's reading of the document.
class AiFindings {
  const AiFindings({
    this.documentType = '',
    this.summary = '',
    this.riskLevel = '',
    this.redFlags = const [],
    this.missingClauses = const [],
    this.keyTerms = const [],
    this.suggestions = const [],
    this.error = '',
  });

  final String documentType;
  final String summary;

  /// 'low' | 'medium' | 'high'.
  final String riskLevel;
  final List<ReviewFlag> redFlags;
  final List<ReviewFlag> missingClauses;
  final List<({String label, String value})> keyTerms;
  final List<String> suggestions;

  /// Set when the read failed; the review can be opened again to retry.
  final String error;

  factory AiFindings.fromJson(Map<String, dynamic> j) => AiFindings(
        documentType: J.str(j['documentType']),
        summary: J.str(j['summary']),
        riskLevel: J.str(j['riskLevel']),
        redFlags: J.models(j['redFlags'], ReviewFlag.fromJson),
        missingClauses: J.models(j['missingClauses'], ReviewFlag.fromJson),
        keyTerms: J
            .mapList(j['keyTerms'])
            .map((t) => (label: J.str(t['label']), value: J.str(t['value'])))
            .toList(),
        suggestions: J.strList(j['suggestions']),
        error: J.str(j['error']),
      );
}

class DocumentReview {
  const DocumentReview({
    required this.id,
    required this.kind,
    required this.status,
    this.fileName = '',
    this.mimeType = '',
    this.size = 0,
    this.pages = 1,
    this.hasFile = false,
    this.signedFileUrl = '',
    this.area = 'other',
    this.areaLabel = '',
    this.question = '',
    this.amount = 0,
    this.paidAt,
    this.ai,
    this.advocateName = '',
    this.assignedAt,
    this.report = '',
    this.deliveredAt,
    this.earning = 0,
    this.userName = '',
    this.createdAt,
  });

  final String id;

  /// 'ai' or 'expert'.
  final String kind;

  /// pending → paid → (ai: done) | (expert: assigned → delivered) · cancelled
  final String status;
  final String fileName;
  final String mimeType;
  final int size;
  final int pages;
  final bool hasFile;

  /// Opens the uploaded document in the phone's browser/viewer without the
  /// app's cookie.
  final String signedFileUrl;
  final String area;
  final String areaLabel;
  final String question;
  final int amount;
  final DateTime? paidAt;
  final AiFindings? ai;
  final String advocateName;
  final DateTime? assignedAt;
  final String report;
  final DateTime? deliveredAt;

  /// The lawyer's share, on their own list.
  final int earning;
  final String userName;
  final DateTime? createdAt;

  bool get isAi => kind == 'ai';
  String get productName => isAi ? 'Smart Document Check' : 'Advocate Document Opinion';

  /// The result is in: the AI's findings, or the lawyer's written opinion.
  bool get isReady =>
      isAi ? (status == 'done' && ai != null && ai!.error.isEmpty) : status == 'delivered';

  /// A paid AI review whose read has not run (or failed) — opening it runs it.
  bool get aiPending => isAi && (status == 'paid' || (ai?.error.isNotEmpty ?? false));

  String get statusLabel => switch (status) {
        'pending' => 'Awaiting payment',
        'paid' => isAi ? 'Reading your document…' : 'Paid · finding a lawyer',
        'assigned' => 'Lawyer reviewing',
        'done' || 'delivered' => 'Report ready',
        'cancelled' => 'Cancelled',
        _ => status,
      };

  factory DocumentReview.fromJson(Map<String, dynamic> j) => DocumentReview(
        id: J.id(j['id']),
        kind: J.str(j['kind'], 'ai'),
        status: J.str(j['status']),
        fileName: J.str(j['fileName']),
        mimeType: J.str(j['mimeType']),
        size: J.int$(j['size']),
        pages: J.int$(j['pages'], 1),
        hasFile: J.flag(j['hasFile']),
        signedFileUrl: J.str(j['signedFileUrl']),
        area: J.str(j['area'], 'other'),
        areaLabel: J.str(j['areaLabel']),
        question: J.str(j['question']),
        amount: J.int$(j['amount']),
        paidAt: J.date(j['paidAt']),
        ai: j['ai'] is Map ? AiFindings.fromJson(J.map(j['ai'])) : null,
        advocateName: J.str(j['advocateName']),
        assignedAt: J.date(j['assignedAt']),
        report: J.str(j['report']),
        deliveredAt: J.date(j['deliveredAt']),
        earning: J.int$(j['earning']),
        userName: J.str(j['userName']),
        createdAt: J.date(j['createdAt']),
      );
}

/// What starting a review returned: either paid already from the wallet, or
/// a Razorpay order to open.
class ReviewStart {
  const ReviewStart({
    required this.reviewId,
    required this.paid,
    required this.price,
    this.pages = 1,
    this.orderId = '',
    this.amountPaise = 0,
    this.currency = 'INR',
    this.keyId = '',
    this.prefillName = '',
    this.prefillEmail = '',
    this.prefillContact = '',
  });

  final String reviewId;
  final bool paid;
  final int price;
  final int pages;
  final String orderId;
  final int amountPaise;
  final String currency;
  final String keyId;
  final String prefillName;
  final String prefillEmail;
  final String prefillContact;

  factory ReviewStart.fromJson(Map<String, dynamic> j) {
    final prefill = J.map(j['prefill']);
    return ReviewStart(
      reviewId: J.str(j['reviewId']),
      paid: J.flag(j['paid']),
      price: J.int$(j['price']),
      pages: J.int$(j['pages'], 1),
      orderId: J.str(j['orderId']),
      amountPaise: J.int$(j['amount']),
      currency: J.str(j['currency'], 'INR'),
      keyId: J.str(j['keyId']),
      prefillName: J.str(prefill['name']),
      prefillEmail: J.str(prefill['email']),
      prefillContact: J.str(prefill['contact']),
    );
  }
}

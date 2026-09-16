import 'json.dart';

/// A legal problem posted from the "Ask a lawyer" form.
///
/// In the open pool the server masks it: `askedBy` is "Rahul S." and
/// `phoneMasked` the last four digits. The full name, phone and email only
/// arrive for the lawyer who has taken it.
class LegalQuery {
  const LegalQuery({
    required this.id,
    required this.category,
    required this.city,
    required this.message,
    required this.status,
    required this.askedBy,
    required this.phoneMasked,
    required this.hasEmail,
    required this.age,
    required this.name,
    required this.phone,
    required this.email,
    required this.createdAt,
    required this.claimedAt,
    required this.resolvedAt,
    required this.resolutionNote,
  });

  final String id;
  final String category;
  final String city;
  final String message;

  /// 'open' | 'claimed' | 'resolved' | 'closed'
  final String status;
  final String askedBy;
  final String phoneMasked;
  final bool hasEmail;

  /// "5 min ago", worded by the server.
  final String age;

  // Only for the lawyer holding the claim.
  final String name;
  final String phone;
  final String email;

  final DateTime? createdAt;
  final DateTime? claimedAt;
  final DateTime? resolvedAt;
  final String resolutionNote;

  String get displayName => name.isNotEmpty ? name : (askedBy.isNotEmpty ? askedBy : 'Client');

  factory LegalQuery.fromJson(Map<String, dynamic> j) => LegalQuery(
        id: J.id(j['id'] ?? j['_id']),
        category: J.str(j['category']),
        city: J.str(j['city']),
        message: J.str(j['message']),
        status: J.str(j['status'], 'open'),
        askedBy: J.str(j['askedBy']),
        phoneMasked: J.str(j['phoneMasked']),
        hasEmail: J.flag(j['hasEmail']),
        age: J.str(j['age']),
        name: J.str(j['name']),
        phone: J.str(j['phone']),
        email: J.str(j['email']),
        createdAt: J.date(j['createdAt']),
        claimedAt: J.date(j['claimedAt']),
        resolvedAt: J.date(j['resolvedAt']),
        resolutionNote: J.str(j['resolutionNote']),
      );
}

/// This month's query credits. One credit takes one query.
class QueryCredits {
  const QueryCredits({
    required this.hasPlan,
    required this.planId,
    required this.planName,
    required this.allowance,
    required this.used,
    required this.left,
    required this.resetsAt,
  });

  static const none = QueryCredits(
    hasPlan: false,
    planId: 'free',
    planName: 'Starter',
    allowance: 0,
    used: 0,
    left: 0,
    resetsAt: null,
  );

  final bool hasPlan;
  final String planId;
  final String planName;
  final int allowance;
  final int used;
  final int left;
  final DateTime? resetsAt;

  bool get isTopPlan => planId == 'premium';

  factory QueryCredits.fromJson(Map<String, dynamic> j) => QueryCredits(
        hasPlan: J.flag(j['hasPlan']),
        planId: J.str(j['planId'], 'free'),
        planName: J.str(j['planName'], 'Starter'),
        allowance: J.int$(j['allowance']),
        used: J.int$(j['used']),
        left: J.int$(j['left']),
        resetsAt: J.date(j['resetsAt']),
      );
}

/// Everything the Client Queries screen shows, in one read.
class QueryBoard {
  const QueryBoard({
    required this.open,
    required this.mine,
    required this.resolved,
    required this.openTotal,
    required this.categories,
    required this.locked,
    required this.credits,
  });

  static const empty = QueryBoard(
    open: [],
    mine: [],
    resolved: [],
    openTotal: 0,
    categories: [],
    locked: true,
    credits: QueryCredits.none,
  );

  /// Masked, and empty when [locked].
  final List<LegalQuery> open;
  final List<LegalQuery> mine;
  final List<LegalQuery> resolved;

  /// Every open query on the platform — shown even when locked, so a lawyer
  /// on Starter knows what a plan would open up.
  final int openTotal;
  final List<String> categories;

  /// No plan with query credits: the pool is hidden.
  final bool locked;
  final QueryCredits credits;

  factory QueryBoard.fromJson(Map<String, dynamic> j) => QueryBoard(
        open: J.models(j['open'], LegalQuery.fromJson),
        mine: J.models(j['mine'], LegalQuery.fromJson),
        resolved: J.models(j['resolved'], LegalQuery.fromJson),
        openTotal: J.int$(j['openTotal']),
        categories: J.strList(j['categories']),
        locked: J.flag(j['locked'], true),
        credits: QueryCredits.fromJson(J.map(j['credits'])),
      );
}

/// A lawyer membership plan, as /api/membership/plans describes it.
class MembershipPlan {
  const MembershipPlan({
    required this.id,
    required this.name,
    required this.tagline,
    required this.monthly,
    required this.queryCredits,
    required this.placement,
    required this.features,
    required this.yearBase,
    required this.yearGst,
    required this.yearTotal,
  });

  final String id;
  final String name;
  final String tagline;
  final int monthly;
  final int queryCredits;
  final String placement;
  final List<String> features;

  /// What a year costs: base + GST = total. Razorpay is opened for the total.
  final int yearBase;
  final int yearGst;
  final int yearTotal;

  bool get isFree => monthly == 0;

  factory MembershipPlan.fromJson(Map<String, dynamic> j) {
    final price = J.map(j['price']);
    return MembershipPlan(
      id: J.str(j['id']),
      name: J.str(j['name']),
      tagline: J.str(j['tagline']),
      monthly: J.int$(j['monthly']),
      queryCredits: J.int$(j['queryCredits']),
      placement: J.str(j['placement']),
      features: J.strList(j['features']),
      yearBase: J.int$(price['base']),
      yearGst: J.int$(price['gst']),
      yearTotal: J.int$(price['total']),
    );
  }
}

/// The plans on sale plus the signed-in lawyer's own.
class PlanCatalog {
  const PlanCatalog({
    required this.plans,
    required this.currentPlanId,
    required this.currentPlanName,
    required this.expiresAt,
    required this.credits,
  });

  final List<MembershipPlan> plans;
  final String currentPlanId;
  final String currentPlanName;
  final DateTime? expiresAt;
  final QueryCredits credits;

  factory PlanCatalog.fromJson(Map<String, dynamic> j) {
    final current = J.map(j['current']);
    return PlanCatalog(
      plans: J.models(j['plans'], MembershipPlan.fromJson),
      currentPlanId: J.str(current['planId'], 'free'),
      currentPlanName: J.str(current['planName'], 'Starter'),
      expiresAt: J.date(current['expiresAt']),
      credits: QueryCredits.fromJson(J.map(current['credits'])),
    );
  }
}

import 'json.dart';

/// The legal-services marketplace: fixed-price work, sold outright.
///
/// A service is not a consultation. A consultation is time with a particular
/// lawyer, billed by the block, and lives in `consultation.dart`. A service is
/// a known job at a known price — an incorporation, a trademark filing, a rent
/// agreement — with no lawyer attached at the point of sale.
///
/// Every figure in this file arrives from the server. Nothing here computes a
/// price, a discount or a tax: the app shows what the order summary endpoint
/// returned, and sends back only the slug, the coupon code and whether to
/// spend the wallet. A total worked out on the phone would be a total a
/// modified build could change.

/// One catalogue entry.
class ServiceProduct {
  const ServiceProduct({
    required this.id,
    required this.slug,
    required this.title,
    required this.category,
    required this.summary,
    required this.banner,
    required this.price,
    required this.mrp,
    required this.discountPercent,
    required this.rating,
    required this.reviews,
    required this.purchased,
    required this.turnaround,
    this.description = '',
    this.includes = const [],
    this.documentsRequired = const [],
    this.howItWorks = const [],
  });

  final String id;
  final String slug;
  final String title;
  final String category;
  final String summary;
  final String banner;

  /// What the client pays, in whole rupees, before tax.
  final int price;

  /// The struck-through figure. Zero when there is no offer on — the server
  /// only sends one when it is genuinely above the price, so a card can show
  /// it without checking.
  final int mrp;
  final int discountPercent;

  final double rating;
  final int reviews;
  final int purchased;

  /// "7–10 working days". Free text, because it varies by service.
  final String turnaround;

  // Detail-screen fields. Empty on a card, because the list endpoint does not
  // send them — a catalogue of forty services would otherwise carry forty long
  // descriptions nobody has asked to read yet.
  final String description;
  final List<String> includes;
  final List<String> documentsRequired;
  final List<ServiceStep> howItWorks;

  bool get hasOffer => mrp > price;

  /// True once enough people have rated it to be worth showing. A service
  /// nobody has rated shows nothing rather than a 0.0 that reads as a bad one.
  bool get hasRating => rating > 0 && reviews > 0;

  factory ServiceProduct.fromJson(Map<String, dynamic> j) => ServiceProduct(
        id: J.id(j['id'] ?? j['_id']),
        slug: J.str(j['slug']),
        title: J.str(j['title']),
        category: J.str(j['category']),
        summary: J.str(j['summary']),
        banner: J.str(j['banner']),
        price: J.int$(j['price']),
        mrp: J.int$(j['mrp']),
        discountPercent: J.int$(j['discountPercent']),
        rating: J.dbl(j['rating']),
        reviews: J.int$(j['reviews']),
        purchased: J.int$(j['purchased']),
        turnaround: J.str(j['turnaround']),
        description: J.str(j['description']),
        includes: J.strList(j['includes']),
        documentsRequired: J.strList(j['documentsRequired']),
        howItWorks: J.models(j['howItWorks'], ServiceStep.fromJson),
      );
}

/// One numbered step of "How it works".
class ServiceStep {
  const ServiceStep({required this.title, required this.description});

  final String title;
  final String description;

  factory ServiceStep.fromJson(Map<String, dynamic> j) => ServiceStep(
        title: J.str(j['title']),
        description: J.str(j['description']),
      );
}

/// A shelf in the catalogue, with how many services are on it.
class ServiceCategory {
  const ServiceCategory({required this.name, required this.count});

  final String name;
  final int count;

  factory ServiceCategory.fromJson(Map<String, dynamic> j) => ServiceCategory(
        name: J.str(j['name']),
        count: J.int$(j['count']),
      );
}

/// The catalogue and its shelves, from one request.
class ServiceCatalogue {
  const ServiceCatalogue({required this.services, required this.categories});

  final List<ServiceProduct> services;
  final List<ServiceCategory> categories;

  static const empty = ServiceCatalogue(services: [], categories: []);

  factory ServiceCatalogue.fromJson(Map<String, dynamic> j) => ServiceCatalogue(
        services: J.models(j['services'], ServiceProduct.fromJson),
        categories: J.models(j['categories'], ServiceCategory.fromJson),
      );
}

/// Every line of an order, exactly as the server worked it out.
///
///   base − discount = taxable;  taxable + gst = payable;
///   payable − walletUsed = razorpayAmount
///
/// The summary screen prints these; it does not add them up itself. Two places
/// computing the same total is two places for them to disagree, and the one
/// the client would notice is an invoice whose lines do not sum.
class OrderAmounts {
  const OrderAmounts({
    required this.base,
    required this.discount,
    required this.gst,
    required this.gstRate,
    required this.payable,
    required this.walletUsed,
    required this.razorpayAmount,
  });

  final int base;
  final int discount;
  final int gst;

  /// 0.18. Sent so the label can read "GST (18%)" without the app deciding
  /// what the rate is.
  final double gstRate;

  /// What the order comes to, tax included, before any wallet is applied.
  final int payable;
  final int walletUsed;

  /// The part to collect through Razorpay. Zero when the wallet covers it all.
  final int razorpayAmount;

  static const zero = OrderAmounts(
    base: 0,
    discount: 0,
    gst: 0,
    gstRate: 0.18,
    payable: 0,
    walletUsed: 0,
    razorpayAmount: 0,
  );

  int get gstPercent => (gstRate * 100).round();

  factory OrderAmounts.fromJson(Map<String, dynamic> j) => OrderAmounts(
        base: J.int$(j['base']),
        discount: J.int$(j['discount']),
        gst: J.int$(j['gst']),
        gstRate: J.dbl(j['gstRate'], 0.18),
        payable: J.int$(j['payable']),
        walletUsed: J.int$(j['walletUsed']),
        razorpayAmount: J.int$(j['razorpayAmount']),
      );
}

/// A coupon the server accepted, as it should be shown back to the client.
class AppliedCoupon {
  const AppliedCoupon({
    required this.code,
    required this.label,
    required this.type,
    required this.value,
  });

  final String code;
  final String label;

  /// 'percent' | 'flat'
  final String type;
  final int value;

  factory AppliedCoupon.fromJson(Map<String, dynamic> j) => AppliedCoupon(
        code: J.str(j['code']),
        label: J.str(j['label']),
        type: J.str(j['type']),
        value: J.int$(j['value']),
      );
}

/// The priced order summary, before anything is placed.
class ServiceQuote {
  const ServiceQuote({
    required this.amounts,
    required this.coupon,
    required this.couponError,
    required this.walletBalance,
    required this.canOrder,
  });

  final OrderAmounts amounts;
  final AppliedCoupon? coupon;

  /// Whether the session behind this quote could actually place the order.
  ///
  /// A price is public, so anyone can see one — a visitor with no account and
  /// a signed-in lawyer both get a full breakdown. Only a client account can
  /// buy, and the screen needs to know which of those it is looking at to say
  /// the right thing rather than showing an error.
  final bool canOrder;

  /// Why a code was refused. The rest of the quote is still valid — the server
  /// prices the order without the coupon rather than refusing to price it.
  final String couponError;

  final int walletBalance;

  factory ServiceQuote.fromJson(Map<String, dynamic> j) {
    final coupon = J.map(j['coupon']);
    return ServiceQuote(
      amounts: OrderAmounts.fromJson(J.map(j['amounts'])),
      coupon: coupon.isEmpty ? null : AppliedCoupon.fromJson(coupon),
      couponError: J.str(j['couponError']),
      walletBalance: J.int$(j['walletBalance']),
      canOrder: J.flag(j['canOrder']),
    );
  }
}

/// Where the paperwork goes and who the invoice is made out to.
class BillingAddress {
  const BillingAddress({
    this.name = '',
    this.email = '',
    this.phone = '',
    this.line1 = '',
    this.line2 = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.gstin = '',
  });

  final String name;
  final String email;
  final String phone;
  final String line1;
  final String line2;
  final String city;
  final String state;
  final String pincode;
  final String gstin;

  static const empty = BillingAddress();

  /// Enough to place an order. The street lines are what the paperwork
  /// actually needs; the GSTIN is only for a client claiming input credit.
  bool get isComplete =>
      name.trim().isNotEmpty &&
      phone.trim().isNotEmpty &&
      line1.trim().isNotEmpty &&
      city.trim().isNotEmpty &&
      state.trim().isNotEmpty &&
      pincode.trim().length == 6;

  String get oneLine => [line1, line2, city, state, pincode]
      .where((p) => p.trim().isNotEmpty)
      .join(', ');

  BillingAddress copyWith({
    String? name,
    String? email,
    String? phone,
    String? line1,
    String? line2,
    String? city,
    String? state,
    String? pincode,
    String? gstin,
  }) =>
      BillingAddress(
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        line1: line1 ?? this.line1,
        line2: line2 ?? this.line2,
        city: city ?? this.city,
        state: state ?? this.state,
        pincode: pincode ?? this.pincode,
        gstin: gstin ?? this.gstin,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'phone': phone,
        'line1': line1,
        'line2': line2,
        'city': city,
        'state': state,
        'pincode': pincode,
        'gstin': gstin,
      };

  factory BillingAddress.fromJson(Map<String, dynamic> j) => BillingAddress(
        name: J.str(j['name']),
        email: J.str(j['email']),
        phone: J.str(j['phone']),
        line1: J.str(j['line1']),
        line2: J.str(j['line2']),
        city: J.str(j['city']),
        state: J.str(j['state']),
        pincode: J.str(j['pincode']),
        gstin: J.str(j['gstin']),
      );
}

/// A placed order.
///
/// The service is a snapshot taken when the order was placed, not a live
/// lookup — a catalogue entry can be repriced or withdrawn, and none of that
/// may change what an order from last month says was bought.
class ServiceOrder {
  const ServiceOrder({
    required this.id,
    required this.reference,
    required this.status,
    required this.serviceTitle,
    required this.serviceSlug,
    required this.serviceCategory,
    required this.amounts,
    required this.couponCode,
    required this.address,
    required this.notes,
    this.createdAt,
    this.paidAt,
    this.completedAt,
  });

  final String id;

  /// "LS-1042" — what a client quotes when they ring up about it.
  final String reference;

  /// 'pending' | 'paid' | 'inProgress' | 'completed' | 'cancelled' | 'refunded'
  final String status;

  final String serviceTitle;
  final String serviceSlug;
  final String serviceCategory;

  final OrderAmounts amounts;
  final String couponCode;
  final BillingAddress address;
  final String notes;

  final DateTime? createdAt;
  final DateTime? paidAt;
  final DateTime? completedAt;

  bool get isPaid =>
      status == 'paid' || status == 'inProgress' || status == 'completed';
  bool get isOpen => status == 'paid' || status == 'inProgress';
  bool get isDone => status == 'completed';

  /// The status in the words a client would use for it.
  String get statusLabel => switch (status) {
        'pending' => 'Payment pending',
        'paid' => 'Confirmed',
        'inProgress' => 'In progress',
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        'refunded' => 'Refunded',
        _ => status,
      };

  factory ServiceOrder.fromJson(Map<String, dynamic> j) {
    final service = J.map(j['service']);
    return ServiceOrder(
      id: J.id(j['id'] ?? j['_id']),
      reference: J.str(j['reference']),
      status: J.str(j['status']),
      serviceTitle: J.str(service['title']),
      serviceSlug: J.str(service['slug']),
      serviceCategory: J.str(service['category']),
      amounts: OrderAmounts.fromJson(J.map(j['amounts'])),
      couponCode: J.str(j['couponCode']),
      address: BillingAddress.fromJson(J.map(j['address'])),
      notes: J.str(j['notes']),
      createdAt: J.date(j['createdAt']),
      paidAt: J.date(j['paidAt']),
      completedAt: J.date(j['completedAt']),
    );
  }
}

/// What the server hands back when an order still needs paying: everything the
/// Razorpay sheet needs, and nothing the app had to decide.
///
/// The key id travels with it rather than being compiled in, so a key rotated
/// in the admin panel takes effect on the very next checkout without a new
/// build — the same reason the wallet top-up carries one.
class ServiceCheckout {
  const ServiceCheckout({
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.keyId,
    required this.prefillName,
    required this.prefillEmail,
    required this.prefillContact,
  });

  final String orderId;
  final int amountPaise;
  final String currency;
  final String keyId;
  final String prefillName;
  final String prefillEmail;
  final String prefillContact;

  factory ServiceCheckout.fromJson(Map<String, dynamic> j) {
    final prefill = J.map(j['prefill']);
    return ServiceCheckout(
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

/// The answer to placing an order: either it is already paid for out of the
/// wallet, or there is a sheet to open.
class PlacedOrder {
  const PlacedOrder({
    required this.order,
    required this.paid,
    required this.checkout,
  });

  final ServiceOrder order;

  /// True when the wallet covered the whole thing and no checkout is needed.
  final bool paid;

  final ServiceCheckout? checkout;

  factory PlacedOrder.fromJson(Map<String, dynamic> j) {
    final checkout = J.map(j['checkout']);
    return PlacedOrder(
      order: ServiceOrder.fromJson(J.map(j['order'])),
      paid: J.flag(j['paid']),
      checkout: checkout.isEmpty ? null : ServiceCheckout.fromJson(checkout),
    );
  }
}

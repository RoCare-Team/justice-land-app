import 'json.dart';
import 'marketplace.dart';

/// A client account. Identity here is the mobile number: an account is created
/// the first time a number passes OTP verification, so there is no sign-up
/// form and name/email may simply be absent.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.photo,
    required this.city,
    required this.anonymous,
    required this.billingAddress,
    required this.walletBalance,
    required this.walletTransactions,
    this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String photo;
  final String city;

  /// When on, lawyers see 'Anonymous' instead of the real name — set once in
  /// the account and applied to every booking.
  final bool anonymous;

  /// The address a service order prefills from. Only a default: the address
  /// printed on an order is copied onto that order when it is placed, so
  /// editing this one never rewrites an invoice already issued.
  final BillingAddress billingAddress;

  final int walletBalance;
  final List<WalletTransaction> walletTransactions;
  final DateTime? createdAt;

  /// A brand-new account has no name yet; the login flow asks for one.
  bool get needsName => name.trim().isEmpty;

  String get displayName => needsName ? 'Your account' : name;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: J.id(j['id'] ?? j['_id']),
        name: J.str(j['name']),
        email: J.str(j['email']),
        phone: J.str(j['phone']),
        photo: J.str(j['photo']),
        city: J.str(j['city']),
        anonymous: J.flag(j['anonymous']),
        billingAddress: BillingAddress.fromJson(J.map(j['billingAddress'])),
        walletBalance: J.int$(j['walletBalance']),
        walletTransactions:
            J.models(j['walletTransactions'], WalletTransaction.fromJson),
        createdAt: J.date(j['createdAt']),
      );
}

/// One line of the wallet ledger — money added, or spent on a consultation.
class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.note,
    required this.paymentId,
    this.createdAt,
  });

  final String id;

  /// 'credit' | 'debit'
  final String type;

  final int amount;
  final String note;

  /// The Razorpay payment behind a top-up. Empty for spends and for manual
  /// adjustments — it is also what makes crediting idempotent server-side.
  final String paymentId;

  final DateTime? createdAt;

  bool get isCredit => type == 'credit';

  String get title =>
      note.isNotEmpty ? note : (isCredit ? 'Added to wallet' : 'Spent');

  factory WalletTransaction.fromJson(Map<String, dynamic> j) =>
      WalletTransaction(
        id: J.id(j['id'] ?? j['_id']),
        type: J.str(j['type'], 'credit'),
        amount: J.int$(j['amount']),
        note: J.str(j['note']),
        paymentId: J.str(j['paymentId']),
        createdAt: J.date(j['createdAt']),
      );
}

/// The wallet as /api/wallet returns it.
class Wallet {
  const Wallet({required this.balance, required this.transactions});

  final int balance;
  final List<WalletTransaction> transactions;

  static const Wallet empty = Wallet(balance: 0, transactions: []);

  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
        balance: J.int$(j['balance']),
        transactions: J.models(j['transactions'], WalletTransaction.fromJson),
      );
}

/// A Razorpay order opened by /api/wallet/order. Nothing is charged yet — this
/// is what the checkout sheet is handed.
class WalletOrder {
  const WalletOrder({
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.keyId,
    required this.prefillName,
    required this.prefillEmail,
    required this.prefillContact,
  });

  final String orderId;

  /// Paise, straight from Razorpay — never re-derived on the client.
  final int amountPaise;

  final String currency;

  /// The key the server is actually configured with, so rotating it in the
  /// admin panel takes effect on the very next top-up.
  final String keyId;

  final String prefillName;
  final String prefillEmail;
  final String prefillContact;

  factory WalletOrder.fromJson(Map<String, dynamic> j) {
    final prefill = J.map(j['prefill']);
    return WalletOrder(
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

/// An enquiry a client sends a lawyer from their profile.
class Enquiry {
  const Enquiry({
    required this.id,
    required this.advocateId,
    required this.name,
    required this.phone,
    required this.email,
    required this.preferredDate,
    required this.message,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String advocateId;
  final String name;
  final String phone;
  final String email;
  final String preferredDate;
  final String message;

  /// 'new' | 'pending' | 'confirmed' | 'declined'
  final String status;

  final DateTime? createdAt;

  factory Enquiry.fromJson(Map<String, dynamic> j) => Enquiry(
        id: J.id(j['id'] ?? j['_id']),
        advocateId: J.id(j['advocateId']),
        name: J.str(j['name']),
        phone: J.str(j['phone']),
        email: J.str(j['email']),
        preferredDate: J.str(j['preferredDate']),
        message: J.str(j['message']),
        status: J.str(j['status'], 'new'),
        createdAt: J.date(j['createdAt']),
      );
}

/// A city with its own directory page.
class City {
  const City({
    required this.name,
    required this.slug,
    required this.state,
    required this.image,
    required this.lawyerCount,
  });

  final String name;
  final String slug;
  final String state;
  final String image;

  /// Lawyers actually registered in this city — the figure the website prints
  /// on its own city tiles, counted from the directory rather than stored.
  ///
  /// Not the `advocates` number on the older built-in city records: that is a
  /// seed figure from before anyone had registered and is not a count of
  /// anything, which is why /api/cities does not send it.
  final int lawyerCount;

  factory City.fromJson(Map<String, dynamic> j) => City(
        name: J.str(j['name']),
        slug: J.str(j['slug']),
        state: J.str(j['state']),
        image: J.str(j['image']),
        lawyerCount: J.int$(j['count']),
      );
}

/// A practice area, with the matters filed under it.
class LegalService {
  const LegalService({
    required this.name,
    required this.slug,
    required this.description,
    required this.lawyerCount,
    required this.subServices,
  });

  final String name;
  final String slug;
  final String description;

  /// Lawyers who list this practice area.
  final int lawyerCount;
  final List<SubService> subServices;

  /// No `icon`: on the website a category carries a React component there,
  /// which does not serialise and would mean nothing here. The app picks its
  /// own icon from the slug.
  factory LegalService.fromJson(Map<String, dynamic> j) => LegalService(
        name: J.str(j['name']),
        slug: J.str(j['slug']),
        description: J.str(j['description']),
        lawyerCount: J.int$(j['count']),
        subServices: J.models(j['subServices'], SubService.fromJson),
      );
}

class SubService {
  const SubService({required this.name, required this.slug});

  final String name;
  final String slug;

  factory SubService.fromJson(Map<String, dynamic> j) => SubService(
        name: J.str(j['name'] ?? j['title']),
        slug: J.str(j['slug']),
      );
}

/// A blog post.
class BlogPost {
  const BlogPost({
    required this.id,
    required this.title,
    required this.slug,
    required this.excerpt,
    required this.content,
    required this.image,
    required this.category,
    required this.author,
    required this.readTime,
    this.publishedAt,
  });

  final String id;
  final String title;
  final String slug;
  final String excerpt;

  /// HTML from the admin editor. Rendered as readable text on mobile.
  final String content;

  final String image;
  final String category;
  final String author;
  final String readTime;
  final DateTime? publishedAt;

  factory BlogPost.fromJson(Map<String, dynamic> j) => BlogPost(
        id: J.id(j['id'] ?? j['_id']),
        title: J.str(j['title']),
        slug: J.str(j['slug']),
        excerpt: J.str(j['excerpt']),
        content: J.str(j['content'] ?? j['body']),
        image: J.str(j['image'] ?? j['coverImage']),
        category: J.str(j['category']),
        author: J.str(j['author']),
        readTime: J.str(j['readTime']),
        publishedAt: J.date(j['publishedAt'] ?? j['createdAt']),
      );
}

/// A platform review shown in "What Our Clients Say".
class Testimonial {
  const Testimonial({
    required this.id,
    required this.name,
    required this.role,
    required this.city,
    required this.rating,
    required this.text,
    required this.date,
  });

  final String id;
  final String name;
  final String role;
  final String city;
  final int rating;
  final String text;
  final String date;

  factory Testimonial.fromJson(Map<String, dynamic> j) => Testimonial(
        id: J.id(j['id'] ?? j['_id']),
        name: J.str(j['name']),
        role: J.str(j['role']),
        city: J.str(j['city']),
        rating: J.int$(j['rating'], 5),
        text: J.str(j['text']),
        date: J.str(j['date']),
      );
}

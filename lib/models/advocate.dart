import 'json.dart';

/// A lawyer, as `buildAdvocateProfile()` returns them from the backend.
///
/// Two shapes come back from the same endpoint family: a lean row in the
/// directory and a full profile on the detail page. Rather than two classes
/// that drift, this one holds both — the list fields are always present, the
/// profile-only ones are empty until the detail call fills them in.
class Advocate {
  Advocate({
    required this.id,
    required this.legalCareId,
    required this.name,
    required this.slug,
    required this.profilePath,
    required this.city,
    required this.state,
    required this.photo,
    required this.coverImage,
    required this.tagline,
    required this.about,
    required this.experience,
    required this.rating,
    required this.reviews,
    required this.verified,
    required this.available,
    required this.status,
    required this.barCouncilNumber,
    required this.consultationFee,
    required this.chatRate,
    required this.audioRate,
    required this.videoRate,
    required this.slotPrices,
    required this.specializations,
    required this.subSpecializations,
    required this.languages,
    required this.courts,
    required this.practiceCities,
    required this.office,
    required this.contact,
    required this.education,
    required this.awards,
    required this.certificates,
    required this.gallery,
    required this.officeTiming,
    required this.faqs,
    required this.reviewsList,
    required this.socialLinks,
    required this.planId,
    required this.planExpiresAt,
    this.distanceKm,
  });

  final String id;

  /// The public identifier — JUSLD04. Also the path segment the reviews
  /// endpoint is keyed on.
  final String legalCareId;

  final String name;
  final String slug;

  /// `advocate-manoj-sharma-jusld04` — slug plus id, the canonical URL segment.
  final String profilePath;

  final String city;
  final String state;
  final String photo;
  final String coverImage;
  final String tagline;
  final String about;
  final int experience;
  final double rating;
  final int reviews;
  final bool verified;

  /// The lawyer's own availability switch. Not the same as being reachable
  /// right now — that comes from /api/presence, because these reads are cached
  /// and a "live" flag baked into them goes stale.
  final bool available;

  /// 'pending' until an admin approves, then 'published'.
  final String status;

  final String barCouncilNumber;
  final int consultationFee;

  /// ₹ per minute per channel. 0 means the lawyer does not offer that channel
  /// at all — the booking sheet hides it rather than showing a free option.
  /// Per-minute rates. Legacy: the website stopped pricing bookings by the
  /// minute and now charges for a slot, so these are display history rather
  /// than what a consultation costs. Kept because most records still carry
  /// them and nothing is gained by dropping the data.
  final int chatRate;
  final int audioRate;
  final int videoRate;

  /// What a block of this lawyer's time costs, keyed either by bare minutes
  /// ("10") or by channel and minutes ("chat:10"). Absent for almost every
  /// lawyer today, which simply means the platform's prices apply — see
  /// `core/config/consultation_slots.dart`, which does that resolution.
  final Map<String, dynamic> slotPrices;

  final List<String> specializations;
  final List<String> subSpecializations;
  final List<String> languages;
  final List<String> courts;

  /// Other cities they take cases in. A client searching one of these finds
  /// them, exactly as on the website.
  final List<String> practiceCities;

  final AdvocateOffice office;
  final AdvocateContact contact;
  final List<Credential> education;
  final List<Credential> awards;
  final List<Credential> certificates;
  final List<String> gallery;
  final List<OfficeHours> officeTiming;
  final List<Faq> faqs;
  final List<Review> reviewsList;
  final Map<String, String> socialLinks;

  /// The membership the lawyer pays for — 'free', 'professional' (Silver) or
  /// 'premium' (Gold) — and the day it runs out. Public on purpose: the paid
  /// plans are sold on a badge clients can see, so the directory needs both to
  /// draw it, and [paidPlanId] is what decides whether it appears.
  final String planId;
  final DateTime? planExpiresAt;

  /// Filled in on the client when a location is known and a distance filter is
  /// in play. Never sent by the server.
  final double? distanceKm;

  /// The paid plan this lawyer is actually on today, or '' for none.
  ///
  /// A plan whose date has passed reads as Starter — the same rule the website
  /// applies in `activePlan()` — so the badge disappears the day the plan
  /// expires rather than advertising a membership that has lapsed. An empty
  /// expiry is treated as running: admin-granted plans are set without one.
  String get paidPlanId {
    if (planId.isEmpty || planId == 'free') return '';
    final until = planExpiresAt;
    if (until != null && until.isBefore(DateTime.now())) return '';
    return planId;
  }

  /// Whether the lawyer has put up a profile photograph. Clients are only
  /// offered a call or video call with a lawyer whose face they can see.
  bool get hasPhoto {
    final p = photo.trim();
    return p.isNotEmpty && p != 'null';
  }

  bool get offersChat => chatRate > 0;
  bool get offersAudio => audioRate > 0;
  bool get offersVideo => videoRate > 0;
  bool get offersAnyLiveChannel => offersChat || offersAudio || offersVideo;
  bool get isPublished => status == 'published';

  int rateFor(String type) {
    switch (type) {
      case 'video':
        return videoRate;
      case 'audio':
        return audioRate;
      default:
        return chatRate;
    }
  }

  /// The cheapest live channel on offer — what the directory card quotes.
  int? get lowestRate {
    final rates = [chatRate, audioRate, videoRate].where((r) => r > 0).toList();
    if (rates.isEmpty) return null;
    return rates.reduce((a, b) => a < b ? a : b);
  }

  /// Does this lawyer serve `cityName`? Base city or any practice city,
  /// compared case-insensitively — the same rule the website applies.
  bool servesCity(String? cityName) {
    final target = (cityName ?? '').trim().toLowerCase();
    if (target.isEmpty) return true;
    if (city.trim().toLowerCase() == target) return true;
    return practiceCities.any((c) => c.trim().toLowerCase() == target);
  }

  Advocate copyWith({double? distanceKm}) => Advocate(
        id: id,
        legalCareId: legalCareId,
        name: name,
        slug: slug,
        profilePath: profilePath,
        city: city,
        state: state,
        photo: photo,
        coverImage: coverImage,
        tagline: tagline,
        about: about,
        experience: experience,
        rating: rating,
        reviews: reviews,
        verified: verified,
        available: available,
        status: status,
        barCouncilNumber: barCouncilNumber,
        consultationFee: consultationFee,
        chatRate: chatRate,
        audioRate: audioRate,
        videoRate: videoRate,
        slotPrices: slotPrices,
        specializations: specializations,
        subSpecializations: subSpecializations,
        languages: languages,
        courts: courts,
        practiceCities: practiceCities,
        office: office,
        contact: contact,
        education: education,
        awards: awards,
        certificates: certificates,
        gallery: gallery,
        officeTiming: officeTiming,
        faqs: faqs,
        reviewsList: reviewsList,
        socialLinks: socialLinks,
        planId: planId,
        planExpiresAt: planExpiresAt,
        distanceKm: distanceKm ?? this.distanceKm,
      );

  factory Advocate.fromJson(Map<String, dynamic> j) {
    return Advocate(
      id: J.id(j['id'] ?? j['_id']),
      legalCareId: J.str(j['legalCareId']),
      name: J.str(j['name']),
      slug: J.str(j['slug']),
      profilePath: J.str(j['profilePath']),
      city: J.str(j['city']),
      state: J.str(j['state']),
      photo: J.str(j['photo']),
      coverImage: J.str(j['coverImage']),
      tagline: J.str(j['tagline']),
      about: J.str(j['about']),
      experience: J.int$(j['experience']),
      rating: J.dbl(j['rating']),
      reviews: J.int$(j['reviews']),
      verified: J.flag(j['verified']),
      available: J.flag(j['available']),
      status: J.str(j['status'], 'published'),
      barCouncilNumber: J.str(j['barCouncilNumber']),
      consultationFee: J.int$(j['consultationFee']),
      chatRate: J.int$(j['chatRate']),
      audioRate: J.int$(j['audioRate']),
      videoRate: J.int$(j['videoRate']),
      slotPrices: J.map(j['slotPrices']),
      specializations: J.strList(j['specializations']),
      subSpecializations: J.strList(j['subSpecializations']),
      languages: J.strList(j['languages']),
      courts: J.strList(j['courts']),
      practiceCities: J.strList(j['practiceCities']),
      office: AdvocateOffice.fromJson(J.map(j['office'])),
      contact: AdvocateContact.fromJson(J.map(j['contact'])),
      education: J.models(j['education'], Credential.education),
      awards: J.models(j['awards'], Credential.award),
      certificates: J.models(j['certificates'], Credential.certificate),
      gallery: J.strList(j['gallery']),
      officeTiming: J.models(j['officeTiming'], OfficeHours.fromJson),
      faqs: J.models(j['faqs'], Faq.fromJson),
      reviewsList: J.models(j['reviewsList'], Review.fromJson),
      planId: J.str(j['planId'], 'free'),
      planExpiresAt: J.date(j['planExpiresAt']),
      socialLinks: J.map(j['socialLinks'])
          .map((k, v) => MapEntry(k, J.str(v)))
        ..removeWhere((_, v) => v.isEmpty),
    );
  }
}

class AdvocateOffice {
  const AdvocateOffice({
    required this.name,
    required this.address,
    required this.area,
    required this.pincode,
  });

  final String name;
  final String address;
  final String area;
  final String pincode;

  bool get isEmpty => name.isEmpty && address.isEmpty;

  String get fullAddress =>
      [address, area, pincode].where((s) => s.isNotEmpty).join(', ');

  factory AdvocateOffice.fromJson(Map<String, dynamic> j) => AdvocateOffice(
        name: J.str(j['name']),
        address: J.str(j['address']),
        area: J.str(j['area']),
        pincode: J.str(j['pincode']),
      );
}

class AdvocateContact {
  const AdvocateContact({
    required this.phone,
    required this.email,
    required this.whatsapp,
  });

  final String phone;
  final String email;
  final String whatsapp;

  factory AdvocateContact.fromJson(Map<String, dynamic> j) => AdvocateContact(
        phone: J.str(j['phone']),
        email: J.str(j['email']),
        whatsapp: J.str(j['whatsapp'], J.str(j['phone'])),
      );
}

/// Education, awards and certificates share a shape — a title, who it is from,
/// and a year — so one model covers all three with the right field names.
class Credential {
  const Credential({
    required this.title,
    required this.subtitle,
    required this.year,
  });

  final String title;
  final String subtitle;
  final String year;

  static Credential education(Map<String, dynamic> j) => Credential(
        title: J.str(j['degree']),
        subtitle: J.str(j['institute']),
        year: J.str(j['year']),
      );

  static Credential award(Map<String, dynamic> j) => Credential(
        title: J.str(j['title']),
        subtitle: J.str(j['org']),
        year: J.str(j['year']),
      );

  static Credential certificate(Map<String, dynamic> j) => Credential(
        title: J.str(j['title']),
        subtitle: J.str(j['issuer']),
        year: J.str(j['year']),
      );
}

class OfficeHours {
  const OfficeHours({required this.day, required this.hours, required this.open});

  final String day;
  final String hours;
  final bool open;

  factory OfficeHours.fromJson(Map<String, dynamic> j) => OfficeHours(
        day: J.str(j['day']),
        hours: J.str(j['hours']),
        open: J.flag(j['open'], true),
      );
}

class Faq {
  const Faq({required this.question, required this.answer});

  final String question;
  final String answer;

  factory Faq.fromJson(Map<String, dynamic> j) => Faq(
        question: J.str(j['q']),
        answer: J.str(j['a']),
      );
}

class Review {
  const Review({
    required this.id,
    required this.author,
    required this.rating,
    required this.text,
    required this.date,
    this.createdAt,
  });

  final String id;
  final String author;
  final int rating;
  final String text;

  /// Pre-formatted "2 months ago" from the server.
  final String date;
  final DateTime? createdAt;

  factory Review.fromJson(Map<String, dynamic> j) => Review(
        id: J.id(j['id'] ?? j['_id']),
        author: J.str(j['author']),
        rating: J.int$(j['rating']),
        text: J.str(j['text']),
        date: J.str(j['date']),
        createdAt: J.date(j['createdAt']),
      );
}

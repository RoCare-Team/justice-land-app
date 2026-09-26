/// Every backend path the app calls, in one place.
///
/// All of them are the website's own routes on the website's own server. The
/// app carries no backend of its own, defines no API of its own, and holds no
/// copy of any rule the server enforces — bookings, billing, status
/// transitions, wallet credits and the WebRTC handshake are all decided
/// server-side, exactly as they are for the website.
///
/// A few of these were added to the web project so a phone could read lists
/// the website renders on the server and therefore never needed as JSON —
/// /api/advocates, /api/cities, /api/services, /api/blogs, and GETs on the
/// enquiries and testimonials routes that already existed. They live in
/// `src/app/api/` in the web repo like every other route, and they call the
/// same library functions the pages call, so there is one directory, one city
/// list and one set of filter rules rather than a web copy and an app copy.
class Endpoints {
  const Endpoints._();

  // ── Session ──────────────────────────────────────────────────────────────
  /// GET → { role: 'advocate'|'user'|null, advocate, user }
  static const String me = '/api/auth/me';
  static const String logout = '/api/auth/logout';

  // ── Client (user) sign-in: mobile number + OTP ───────────────────────────
  /// POST { phone } → { ok }
  static const String userOtpSend = '/api/auth/user/otp/send';

  /// POST { phone, otp } → { ok, created, needsName, user }
  /// `created` is true only the first time a number is seen — that is the
  /// signal the account was just made, and what the web app reports as a
  /// registration conversion.
  static const String userOtpVerify = '/api/auth/user/otp/verify';

  /// PATCH { name?, anonymous?, billingAddress? } — the name a brand-new
  /// account has not got yet, the anonymity switch, and the address that
  /// prefills a service checkout.
  static const String userMe = '/api/user/me';

  // ── Lawyer (advocate) sign-in: mobile number + OTP ───────────────────────
  //
  // There is no password anywhere in this flow any more. The website removed
  // /api/auth/login, /api/auth/register, /api/auth/check-availability and both
  // password-reset routes when it moved lawyers onto the same one-time-code
  // sign-in clients already used; those paths now 404, which is why the app
  // could no longer register or sign in a lawyer at all.

  /// POST { phone } → { ok, sentTo, resendIn }
  /// 429 { error: 'too-soon', retryAfter } | { error: 'rate-limited' }
  static const String advocateOtpSend = '/api/auth/advocate/otp/send';

  /// POST { phone, otp } →
  ///   { ok, registered: true,  name, redirect }  — the number has an account
  ///   { ok, registered: false, phone }           — it does not, so sign up
  ///
  /// On the second answer the server also sets a short-lived httpOnly cookie
  /// proving this browser just verified that number. `advocateSignup` will not
  /// create an account without it, which is why the app must never post a
  /// phone number to the signup route itself.
  static const String advocateOtpVerify = '/api/auth/advocate/otp/verify';

  /// POST { name, email, city } → 201 { ok, advocate: { id, name, legalCareId },
  /// redirect }. The number comes from the proof cookie, never from the body.
  /// 401 { error: 'expired' } — the proof timed out, verify again.
  /// 409 { error: 'email-taken' | 'phone-taken' | 'duplicate', message }
  static const String advocateSignup = '/api/auth/advocate/signup';

  // ── Lawyer directory ─────────────────────────────────────────────────────
  /// GET ?q=&city=&service=&subService=&court=&availability=&sort=&page=&perPage=
  /// → { advocates, total, page, perPage, totalPages }
  ///
  /// Filtered and sorted by lib/advocateSearch on the server — the same module
  /// the website's own /lawyers listing runs, so the same query gives the same
  /// lawyers in the same order in both places.
  static const String advocates = '/api/advocates';

  /// GET /api/advocates/<profilePath | legalCareId | legacy slug> → { advocate }
  /// Resolved by the same function that serves /lawyers/<slug> on the web, so a
  /// link shared from the website opens the same lawyer here.
  static String advocate(String idOrPath) => '/api/advocates/$idOrPath';

  /// GET ?city=&state=&lat=&lng=&limit= → { scope, place, total, advocates }
  /// Lawyers where the visitor actually is, for the home screen.
  static const String advocatesNearby = '/api/advocates/nearby';

  /// POST { author, rating, text } — the path segment is the Justiceland ID.
  static String advocateReviews(String legalCareId) =>
      '/api/advocates/$legalCareId/reviews';

  // ── Content ──────────────────────────────────────────────────────────────
  /// GET → { cities } — every city with a directory page, in the website's own
  /// order, each with the count of lawyers actually registered there.
  static const String cities = '/api/cities';

  /// GET → { services, courts, languages } — the practice areas with their
  /// matters, plus the other two filter dropdowns in the same response.
  static const String services = '/api/services';

  /// GET ?category=&page=&perPage= → { blogs, total, page, totalPages }
  static const String blogs = '/api/blogs';

  /// GET → { blog }
  static String blog(String slug) => '/api/blogs/$slug';

  /// GET → { testimonials } · POST { name, role, city, rating, text }
  static const String testimonials = '/api/testimonials';

  // ── Consultations ────────────────────────────────────────────────────────
  /// GET → lawyer's live inbox (pending + active). Doubles as the presence
  /// heartbeat: calling it is what marks the lawyer online.
  static const String consultationInbox = '/api/consultations';

  /// POST { advocateId, type, resumeFrom? } → { ok, session }
  /// Per minute at the lawyer's rate: 400 if they do not offer the channel,
  /// 402 `insufficient` when the wallet cannot cover the first minute.
  static const String consultationCreate = '/api/consultations';

  /// GET ?scope=mine → { consultations } — the signed-in participant's own
  /// history. Which history is decided by the session, never by the parameter:
  /// a client gets what they booked, a lawyer what they took.
  static const Map<String, dynamic> consultationHistoryQuery = {'scope': 'mine'};

  /// GET → { session } · PATCH { action } · DELETE (hide from my list)
  static String consultation(String id) => '/api/consultations/$id';

  /// POST { text }
  static String consultationMessages(String id) =>
      '/api/consultations/$id/messages';

  /// POST {} — "I am typing": the other side sees it for a few seconds.
  static String consultationTyping(String id) => '/api/consultations/$id/typing';

  /// POST { upTo } — everything received up to this moment has been read.
  static String consultationRead(String id) => '/api/consultations/$id/read';

  /// GET ?since= · POST { action: start|accept|reject|end|signal, … }
  static String consultationCall(String id) => '/api/consultations/$id/call';

  /// GET → the saved transcript of an ended session.
  static String consultationTranscript(String id) =>
      '/api/consultations/$id/transcript';

  /// POST (multipart: file, callId) → upload one call attempt's recording.
  static String consultationRecording(String id) =>
      '/api/consultations/$id/recording';

  /// GET ?advocateId=&type= → { resumable } — free leftover time, if any.
  static const String resumable = '/api/consultations/resumable';

  /// GET → ICE servers for the WebRTC video call.
  static const String webrtcIce = '/api/webrtc/ice';

  /// GET ?ids=a,b,c → which lawyers are online right now.
  static const String presence = '/api/presence';

  // ── Wallet ───────────────────────────────────────────────────────────────
  /// GET → { balance, transactions }
  static const String wallet = '/api/wallet';

  /// POST { amount } → { orderId, amount, currency, keyId, prefill }
  static const String walletOrder = '/api/wallet/order';

  /// POST { razorpay_order_id, razorpay_payment_id, razorpay_signature }
  static const String walletVerify = '/api/wallet/verify';

  // ── Legal services marketplace ───────────────────────────────────────────
  //
  // Fixed-price work — an incorporation, a trademark filing, a rent agreement
  // — sold outright, as opposed to a consultation, which is time with a
  // particular lawyer billed by the block. Different product, different
  // routes; the two share nothing but the wallet.
  //
  // Every rupee of an order is computed on the server from the catalogue and
  // the coupon table. The app sends a slug, a coupon code and a yes/no on the
  // wallet, and nothing else reaches the price — so there is no field here a
  // client could edit to pay less.

  /// GET ?category=&q=&limit= → { services, categories }
  static const String marketplaceServices = '/api/marketplace/services';

  /// GET → { service } — with the description, what is included, the documents
  /// the client will need and the numbered steps.
  static String marketplaceService(String slug) =>
      '/api/marketplace/services/$slug';

  /// POST { slug, couponCode?, useWallet? } →
  ///   { service, amounts, coupon, couponError, walletBalance }
  ///
  /// The order-summary breakdown. A rejected coupon comes back as
  /// `couponError` with the totals intact rather than as a failed request, so
  /// the summary still renders with the reason beside the coupon field.
  static const String marketplaceQuote = '/api/marketplace/quote';

  /// GET → { orders } · POST { slug, couponCode?, useWallet?, address, notes }
  ///
  /// POST answers one of two ways:
  ///   { order, paid: true }             — the wallet covered it outright
  ///   { order, paid: false, checkout }  — `checkout` opens the Razorpay sheet
  static const String marketplaceOrders = '/api/marketplace/orders';

  /// POST { razorpay_order_id, razorpay_payment_id, razorpay_signature }
  /// → { ok, applied, order }
  static const String marketplaceOrderVerify =
      '/api/marketplace/orders/verify';

  /// POST → { ok, refunded }
  ///
  /// Called when the client dismisses the checkout sheet. An unpaid order
  /// holds whatever wallet share it was going to spend, and this gives it
  /// straight back instead of making them wait out the server's half-hour
  /// sweep for money they can see is missing.
  static String marketplaceOrderCancel(String id) =>
      '/api/marketplace/orders/$id/cancel';

  // ── Enquiries ────────────────────────────────────────────────────────────
  /// GET → { enquiries } — a lawyer gets the ones sent to them, a client the
  /// ones they sent; the session decides which.
  /// POST { advocateId, name, phone, email?, preferredDate?, message }
  static const String enquiries = '/api/enquiries';

  /// PATCH { status } — 'new' | 'pending' | 'confirmed' | 'declined'
  static String enquiry(String id) => '/api/enquiries/$id';

  // ── Client queries ("Ask a lawyer") ──────────────────────────────────────
  //
  // A legal problem posted by anyone — no account needed — into a pool every
  // lawyer on a paid plan can see. The first lawyer to take one spends a query
  // credit, gets the client's contact details, and it leaves everyone else's
  // list; once resolved it leaves the pool for good.

  /// POST { name, phone, email?, category?, city?, message } → 201 { ok, id }
  /// 400 validation · 429 too many questions from this number / network.
  static const String askQuery = '/api/queries';

  /// GET ?category=&city= → { open, mine, resolved, openTotal, categories,
  /// locked, credits: { hasPlan, planId, planName, allowance, used, left,
  /// resetsAt } }. `locked` (no plan with credits) empties `open`.
  static const String lawyerQueries = '/api/dashboard/queries';

  /// PATCH { action: 'claim' | 'release' | 'resolve', note? } → { ok, query }
  /// 402 code no_plan | no_credits · 409 code taken.
  static String lawyerQuery(String id) => '/api/dashboard/queries/$id';

  // ── Lawyer dashboard ─────────────────────────────────────────────────────
  /// GET → the lawyer's editable profile
  /// PUT → save it · PATCH → availability toggle · DELETE → close account
  static const String dashboardProfile = '/api/dashboard/profile';

  /// GET → { documents: [{ id, kind, label, fileName, mimeType, size, uploadedAt }] }
  /// POST multipart { kind: 'bar_council_certificate' | 'government_id', file }
  /// → 201 { document }. PDF, JPG or PNG, max 5 MB; uploading a kind again
  /// replaces it. Stored privately — only the lawyer and admins can open them.
  static const String verificationDocuments = '/api/dashboard/verification-documents';

  /// POST { token } — registers this device's Firebase Cloud Messaging token
  /// against the signed-in lawyer, so a new request or an incoming call still
  /// reaches them with the app backgrounded or closed.
  /// DELETE { token } — removes it, on sign-out.
  static const String fcmToken = '/api/dashboard/fcm-token';

  // ── Membership plans (lawyers) ───────────────────────────────────────────
  //
  // What a plan buys is how much of a practice may be listed and where it
  // ranks — never anything about consultations, which work identically on
  // every plan. Prices are computed server-side from the plan table; the app
  // sends a plan id and nothing else, so it cannot name its own price.

  /// GET → { plans: [{ id, name, tagline, monthly, queryCredits, placement,
  /// features, price: { base, gst, total, monthly } }], current: { planId,
  /// planName, expiresAt, credits } | null }
  static const String membershipPlans = '/api/membership/plans';

  /// POST { planId } → { orderId, amount, currency, keyId, plan, price, prefill }
  static const String membershipOrder = '/api/membership/order';

  /// POST { razorpay_order_id, razorpay_payment_id, razorpay_signature }
  /// → { ok, planId, planName, expiresAt, price }
  static const String membershipVerify = '/api/membership/verify';

  // ── Lawyer profile helpers ───────────────────────────────────────────────

  /// POST → { about } — drafts the About paragraph from what is already on the
  /// profile. Returns the text; saving it is a separate, deliberate act.
  static const String aboutGenerate = '/api/dashboard/about/generate';

  /// POST { holderName, accountNumber, ifsc, bankName?, pan? } → { account } —
  /// adds a bank account for payouts. The number is sealed on the server; only
  /// the last four digits come back.
  static const String bankAccounts = '/api/dashboard/bank-accounts';

  /// GET → the lawyer's balance, payouts and `bankAccounts` (last four only).
  static const String payouts = '/api/dashboard/payouts';

  // ── Voice search ─────────────────────────────────────────────────────────
  /// POST multipart `audio` (or JSON { transcript, city }) → the spoken
  /// problem understood, and the lawyers for it. Speech-to-text and the
  /// classification both run on the server; nothing here needs an AI key.
  static const String voiceLegalSearch = '/api/voice/legal-search';

  // ── Misc ─────────────────────────────────────────────────────────────────
  /// POST { name, email, phone, subject, message }
  static const String contact = '/api/contact';

  /// GET ?code= → { pincode, city, state } — used by the location picker and
  /// the lawyer onboarding. The parameter is `code`, not `pincode`: the server
  /// answers 400 to anything else.
  static const String pincode = '/api/pincode';

  /// GET ?lat=&lng= → reverse geocode to a city.
  static const String geocode = '/api/geocode';

  /// POST — image upload, returns { url }.
  static const String upload = '/api/admin/upload';
}

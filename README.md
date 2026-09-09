# Justiceland — Flutter app

The mobile version of the Justiceland platform. Same backend, same data, same
rules — only the UI is rebuilt for a phone.

**Nothing here has been compiled.** This is source only — no `pub get`, no
build, no emulator, and no Flutter SDK was available where it was written, so
nothing has been through `flutter analyze`. Expect to fix a few analyzer
complaints on the first run.

What *has* been checked is the part that fails silently rather than at compile
time: every endpoint the app calls exists on the web backend and answers the
method the app sends, and the reference lists bundled in the app still match the
website's. Both checks are scripts in `tool/` — see below.

---

## State of the redesign (read this first)

The app is **part-way through** a visual rebuild onto the new JusticeLand
mockup. It is functional throughout — every screen talks to the real backend —
but only some screens wear the new design yet.

**Rebuilt to the new design**

- Role selection (new screen)
- Lawyer sign-in / registration — mobile + OTP
- Home — greeting, search, compact category strip, lawyers directly beneath
- Lawyer card and profile pricing
- Brand palette applied app-wide (navy `#0B1F3A`, gold `#D4A017`)
- Legal Services — catalogue, service detail, order summary, my orders (new)

**Still on the previous design** — working, but not yet restyled

Splash, user sign-in, lawyer list, lawyer profile layout, booking sheet, chat,
audio call, video call, wallet, consultations, profile, bottom navigation.

### Two things that were broken and are now fixed

**Lawyer auth could not work at all.** The website removed passwords for
lawyers: `/api/auth/login`, `/api/auth/register`, `/api/auth/check-availability`
and both password-reset routes no longer exist. The app was still calling all
five, so registration and sign-in returned 404. It now uses the same one-time
code flow the website does — see `lib/features/auth/advocate_auth_screen.dart`.

**Prices were quoted from the wrong field.** The website stopped charging by
the minute; a booking now buys a block of time and is billed against that
block's price, per channel. The app was still showing `chatRate` as "₹20/min",
so a card promised one figure and the checkout charged another. Slot pricing
now lives in `lib/core/config/consultation_slots.dart`, which mirrors the
website's `src/constants/consultationSlots.js` rule for rule.

The profile screen also used to hide Chat/Call/Video when the matching
per-minute rate was zero. On the website every lawyer is bookable on every
channel — an unset price simply means the platform's applies — so roughly sixty
lawyers had their call and video buttons hidden for no reason. They are always
shown now.

### Deliberately not built

Two screens in the mockup ask for things the backend has no home for, and were
left out rather than faked:

- **Document upload** (bar council certificate, Aadhaar/PAN). There is no
  document field on the advocate record and no upload endpoint for it.
  Verification is an admin toggle.
- **Appointment date/time.** Consultations are instant — the server creates a
  live session when the lawyer is online. There is no scheduling model.

User registration also asks only for a name, because that is all the website's
client signup collects. No gender field exists on the user record.

---

## Legal Services (the fixed-price marketplace)

A second thing to buy, alongside consultations, and a deliberately different
one. A **consultation** is time with a particular lawyer, billed by the block.
A **service** is a known job at a known price — an incorporation, a trademark
filing, a rent agreement — with no lawyer chosen at the point of sale. They
share the wallet and nothing else: separate models, separate routes, separate
screens.

The backend for this was added to the web project in the same pass, under
`/api/marketplace`. It is the website's own code, in `src/app/api/marketplace/`
and `src/lib/legalServices.js`, called by the same server the rest of the app
talks to. The app carries no pricing rule of its own.

| Screen | Route | File |
|---|---|---|
| Catalogue + Talk to a Lawyer | `/services` | `features/services/services_screen.dart` |
| Service detail | `/services/<slug>` | `features/services/service_detail_screen.dart` |
| Order summary | `/services/<slug>/order` | `features/services/order_summary_screen.dart` |
| My orders | `/orders` | `features/services/my_orders_screen.dart` |

### How the money works

The app never sends a price. It sends a slug, a coupon code and a yes/no on
the wallet; the server prices the order from the catalogue and the coupon
table, adds GST, and decides what to collect. There is no field a modified
build could edit to pay less.

    POST /api/marketplace/quote    { slug, couponCode?, useWallet? }
      -> { amounts: { base, discount, gst, gstRate, payable,
                      walletUsed, razorpayAmount }, coupon, couponError,
           walletBalance }

    POST /api/marketplace/orders   { slug, couponCode?, useWallet?,
                                     address, notes? }
      -> { order, paid: true }              wallet covered it outright
      -> { order, paid: false, checkout }   open the Razorpay sheet

    POST /api/marketplace/orders/verify
         { razorpay_order_id, razorpay_payment_id, razorpay_signature }
      -> { ok, applied, order }

`applied: false` is not an error. It means Razorpay's webhook confirmed the
payment before the app got back — the order is paid either way, and both paths
are keyed on the payment id so only one of them can take effect.

Three things about this are worth knowing before changing any of it:

- **The wallet share is taken when the order is opened, not after checkout.**
  Otherwise the balance could be spent elsewhere mid-checkout and the Razorpay
  leg, fixed when the order was created, would no longer cover the rest.
- **An abandoned checkout must be released.** `MarketplaceController` calls
  `POST /api/marketplace/orders/<id>/cancel` when the sheet closes unpaid, so
  the hold comes straight back rather than waiting out the server's half-hour
  sweep. If that call fails, the sweep still gets it.
- **A swept order can still be paid.** Someone who sits on the sheet past the
  half hour has their order cancelled and their hold returned, and can then
  finish paying. The server revives the order and takes the wallet share
  again; if the balance has gone, the order still stands and the shortfall is
  recorded on it for an admin to chase. Refusing at that point would be taking
  the money and delivering nothing.

### Images

Every image on this platform arrives in one of three shapes and they are not
interchangeable:

- `/api/advocates/<id>/photo` — a path relative to the API host. The *list*
  endpoint sends this, because photographs are megabytes and must not travel
  inside a directory payload.
- `data:image/jpeg;base64,...` — the bytes inline. The *detail* endpoint sends
  the same photograph this way, since it is reading the one document anyway.
- An absolute `https://` URL.

`CachedNetworkImage` handles only the third. Use `RemoteImage` from
`core/widgets/common.dart` for all of them — it decodes inline bytes, resolves
relative paths against the API host, and falls back cleanly. Passing a raw
value straight to `CachedNetworkImage` is what had every lawyer showing their
initial instead of their face.

### Talk to a Lawyer

The grid at the top of `/services` is **not** part of the marketplace. Each
tile opens the lawyer directory filtered to that practice area — the same
listing the Find Lawyer tab shows, from `GET /api/advocates`. No price is
printed on those tiles, because what a consultation costs depends on which
lawyer is picked.

### Not built here either

- **Document upload for an order.** The order model has a documents-required
  *list* — what the client will be asked for — but there is no upload endpoint
  and nowhere to put a file. A field that quietly discarded an attachment
  would be worse than no field.
- **Order tracking beyond a status.** An order moves pending → paid →
  in progress → completed, set by an admin. There is no per-step timeline,
  because nothing records step timestamps.

---

## Getting it running

This is `lib/` plus its manifest — there is no `android/` or `ios/` folder in
the repo, because those are generated and every Flutter version generates them
slightly differently. Make them once, on your machine, before the first run:

```bash
# Generates android/ and ios/ around the existing lib/ and pubspec.yaml.
# It will not touch either of them.
flutter create --platforms=android,ios .
```

Then the Android permissions and iOS usage strings below go into the files it
just created, and after that:

```bash
flutter pub get

# Android emulator — 10.0.2.2 is how the emulator reaches the host's localhost
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000

# A physical device on the same Wi-Fi
flutter run --dart-define=API_BASE_URL=http://192.168.1.55:3000

# Against production (the default if you pass nothing)
flutter run
```

The default is `https://www.justiceland.online`. See
`lib/core/config/app_config.dart`.

### The backend

There isn't a separate one. The app talks to the Next.js server the website
runs on, calls the website's own routes, and holds no copy of any rule that
server enforces — bookings, billing, status transitions, wallet credits and the
WebRTC handshake are all decided there, exactly as they are for the web client.

The read endpoints a phone needs and a server-rendered page does not
(`/api/advocates`, `/api/cities`, `/api/services`, `/api/blogs`, and GETs on the
enquiries, testimonials and consultations routes) live in `src/app/api/` in the
**web repo**, alongside every other route, and call the same library functions
the pages call. There is one directory, one city list and one set of filter
rules — `lib/advocateSearch.js` on the server is what both `/lawyers` and
`GET /api/advocates` run.

Two checks keep it that way, and both are worth running after any backend
change:

```bash
node tool/check_api_contract.mjs      # every path the app calls exists server-side
node tool/check_reference_data.mjs    # the bundled lists still match src/data
```

### Before it will work end to end

1. **Android permissions** — add these to
   `android/app/src/main/AndroidManifest.xml` inside `<manifest>`:

   ```xml
   <uses-permission android:name="android.permission.INTERNET" />
   <uses-permission android:name="android.permission.CAMERA" />
   <uses-permission android:name="android.permission.RECORD_AUDIO" />
   <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
   ```

   For a local HTTP backend, also set
   `android:usesCleartextTraffic="true"` on `<application>` — Android blocks
   plain HTTP otherwise, and the failure looks like a dead server.

   `minSdkVersion` must be **21 or higher** (flutter_webrtc and razorpay_flutter).

2. **iOS** — `ios/Runner/Info.plist` needs `NSCameraUsageDescription`,
   `NSMicrophoneUsageDescription` and `NSLocationWhenInUseUsageDescription`,
   each with a sentence explaining why.

---

## The screens

Five tabs at the bottom: **Home · Services · Top Lawyers · Wallet · Profile**,
with Top Lawyers in the raised gold middle slot because reaching a lawyer is
what the app is for. A lawyer gets their Dashboard in place of the Wallet,
because a lawyer earns rather than tops up.

Consultations are deliberately not a tab. A client has one open occasionally,
and giving a rarely-used destination a fifth of the bar cost the two things
that are used constantly. It is reached from the bell in the home header and
from Profile → My Consultations, both always one tap away. Orders sit beside
it at Profile → My Orders.

| Screen | Route | File | Reads |
|---|---|---|---|
| Splash | `/splash` | `features/splash/splash_screen.dart` | `GET /api/auth/me` |
| Onboarding (first launch only) | `/onboarding` | `features/onboarding/onboarding_screen.dart` | — |
| Home | `/` | `features/home/home_screen.dart` | `advocates/nearby`, `services`, `testimonials`, `presence` |
| Top Lawyers — results | `/lawyers` | `features/lawyers/lawyers_screen.dart` | `GET /api/advocates` |
| Find Lawyer — filters | pushed | `features/lawyers/filter_screen.dart` | `services`, `cities` |
| Advocate profile | `/lawyers/<path>` | `features/lawyers/advocate_profile_screen.dart` | `GET /api/advocates/<path>` |
| Chat | `/consultation/<id>/chat` | `features/consultation/chat_screen.dart` | `consultations/<id>`, `messages` |
| Audio call | `/consultation/<id>/audio` | `features/consultation/audio_call_screen.dart` | `consultations/<id>/call` |
| Video call | `/consultation/<id>/video` | `features/consultation/video_call_screen.dart` | `call`, `webrtc/ice` |
| My Consultations | `/consultations` | `features/consultation/consultations_screen.dart` | `consultations?scope=mine` |
| Wallet | `/wallet` | `features/account/wallet_screen.dart` | `wallet`, `wallet/order`, `wallet/verify` |
| Profile | `/profile` | `features/account/profile_screen.dart` | `auth/me`, `PATCH user/me` |
| More | `/more` | `features/account/more_screen.dart` | — (policies open on the web) |
| Legal Guides | `/blogs` | `features/content/content_screens.dart` | `GET /api/blogs` |
| Advocate Dashboard | `/dashboard` | `features/dashboard/dashboard_screen.dart` | `consultations`, `enquiries` |
| Lawyer sign-in / registration | `/advocate/login`, `/advocate/register` | `features/auth/advocate_auth_screen.dart` | `auth/advocate/otp/*`, `auth/advocate/signup` |
| Legal Services landing | `/services` | `features/services/services_screen.dart` | `GET /api/marketplace/services` |
| All services (search + shelves) | `/services/all` | `features/services/all_services_screen.dart` | `GET /api/marketplace/services` |
| Service detail | `/services/<slug>` | `features/services/service_detail_screen.dart` | `GET /api/marketplace/services/<slug>` |
| Order summary | `/services/<slug>/order` | `features/services/order_summary_screen.dart` | `marketplace/quote`, `marketplace/orders`, `orders/verify` |
| My orders | `/orders` | `features/services/my_orders_screen.dart` | `GET /api/marketplace/orders` |

Two things in the design are deliberately not built, because no server field
backs them and a number invented on the phone would be read as a fact:

- **Online time on the dashboard.** Nothing records how long an availability
  switch has been on. That slot shows waiting requests instead — which is what
  a lawyer opening the screen actually needs to know.
- **"Verified lawyers only" defaulting to on.** Verification is done by hand by
  an administrator, and nobody is marked verified yet, so defaulting it on would
  empty the directory on first open. The filter is there; it starts off.

---

## How it is put together

```
lib/
  core/
    config/      base URL, poll intervals, generated reference data
    network/     Dio client + cookie jar, endpoint map, typed errors
    theme/       the website's navy/gold palette
    utils/       formatters, validation rules copied from the web
    widgets/     loading / empty / error / success states, shared UI
  models/        the API's shapes, parsed defensively
  services/      one class per API area — no business logic, just calls
  state/         ChangeNotifiers holding what the server last said
  features/      one folder per screen area
  routing/       every route, mapped to the website's own URLs
tool/            contract checks against the web backend
```

### Authentication

The website authenticates with an httpOnly `lci_token` cookie. The app does the
same — Dio with a **persisted cookie jar**. The token is never read, stored, or
parsed by the app, because it is not the app's to see. Signing out clears the
jar as well as calling the endpoint, so a failed request cannot leave the app
sitting on a dead session.

Roles are the server's: `user` (client) or `advocate` (lawyer). `/api/auth/me`
decides, and the router guards `/account` for clients and `/dashboard` for
lawyers.

### The consultation flow

This is the part that carries money, so it is worth reading before changing:

- Booking creates a **pending** session at the lawyer's per-minute rate.
  Nothing is charged. It is refused up front only when the wallet cannot cover
  a single minute.
- The lawyer accepts (clock starts) or declines (no charge).
- Either side ends it. The server bills the minutes used and records the
  leftover, which the client can reclaim **free for 24 hours**.
- **Every transition is the server's.** The app asks and re-reads; it never
  advances a session locally and hopes the server agrees.

Three channels, each billing from its own rate and never crossing over:

| Channel | Where it happens | How it is tracked |
|---------|------------------|-------------------|
| Chat    | in the app       | polls the session |
| Video   | WebRTC, device to device | signalling relayed by the backend |
| Audio   | the phone network | polls, and the server asks the telephony provider whether it was answered |

The polling is not laziness. For an audio consultation it is the *only* thing
that starts and ends the session — nothing on the phone network reports back on
its own. For the lawyer's inbox it doubles as the presence heartbeat: a lawyer
whose app is polling is a lawyer clients can book.

### The wallet

Three steps, in this order, none skippable:

1. `POST /api/wallet/order` — the server opens a Razorpay order.
2. Razorpay's sheet takes the payment.
3. `POST /api/wallet/verify` — the server checks the signature with Razorpay
   and credits.

The app never tells the server an amount. A `pending` result means authorised
but not captured — the money is held, not taken — so the app says "your balance
will update shortly" rather than claiming success or failure. The webhook
finishes the job.

The Razorpay key id comes back in the order response, so rotating it in
`/admin/payments` reaches the app on the next top-up with no rebuild.

---

## Two things worth knowing

**This code has not been compiled.** There was no Flutter SDK on the machine it
was written on, so `flutter analyze` never ran. It is written carefully and the
API contracts were read out of the live backend rather than guessed, but expect
to fix a handful of analyzer complaints on the first `pub get`.

**The lawyer directory opens unfiltered.** A remembered location is shown in
the header but does not narrow anything on its own. That is deliberate: on the
website a picked location used to arrive with a 100 km radius already applied,
and someone opening the directory from a city with no nearby lawyers was met
with "0 lawyers found within 100 km" — a filter they never set, hiding every
lawyer on the platform.

---

## What is covered

- Client sign-in by mobile + OTP, including the first-time name step
- Lawyer sign-in, five-step registration wizard, password reset by OTP
- Lawyer directory with search, filters, sort and paging
- Full lawyer profile — rates, courts, cities, credentials, gallery, reviews, FAQ
- Booking on all three channels, with the free-resume offer for leftover time
- Live chat, video call and audio call, with running cost and countdown
- Enquiries: sending one as a client, answering one as a lawyer
- Wallet: balance, ledger, Razorpay top-up
- Client account: overview, consultation history, wallet, privacy toggle
- Lawyer dashboard: live inbox, availability switch, consultations, enquiries,
  profile editing with photo upload
- Blogs, contact form, city picker
- Loading, empty, error and success states on every screen
#   j u s t i c e _ l a n d 
 
 
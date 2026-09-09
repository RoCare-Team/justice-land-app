/// The blocks of time a client can book, and what they cost.
///
/// A mirror of the website's `src/constants/consultationSlots.js`, kept in step
/// with it deliberately: the server decides what a booking actually costs, and
/// this file exists only so the app can show the same figure *before* the
/// booking is made. If the two ever disagree the server wins, and the client
/// was quoted a price that was not charged — which is the one failure a
/// consultation product must not have.
///
/// A slot is two things: how long the client is booking, and the most it can
/// cost them. It is not what they are charged. A session still bills the
/// minutes it runs — book thirty, finish in ten, pay for ten — so the slot is a
/// ceiling, not a ticket.
library;

/// The three blocks, shortest first. `minutes` is also the key they are stored
/// under on the lawyer's record.
class ConsultationSlot {
  const ConsultationSlot({
    required this.minutes,
    required this.label,
    required this.defaultPrice,
  });

  final int minutes;
  final String label;

  /// Used only while the lawyer has not set their own figure. The moment they
  /// enter one, that is what applies.
  final int defaultPrice;
}

const List<ConsultationSlot> kConsultationSlots = [
  ConsultationSlot(minutes: 10, label: '10 min', defaultPrice: 200),
  ConsultationSlot(minutes: 30, label: '30 min', defaultPrice: 500),
  ConsultationSlot(minutes: 60, label: '1 hour', defaultPrice: 1000),
];

/// The two a lawyer card leads with. The rest are on the profile — a card has
/// room for one line, and there are nine figures behind it.
const List<int> kCardSlotMinutes = [10, 30];

/// The three ways a consultation happens, each priced separately.
///
/// A lawyer does not value them the same way: ten minutes of typing is not ten
/// minutes on camera. `card` marks the one a directory card quotes.
class ConsultationChannel {
  const ConsultationChannel({
    required this.key,
    required this.label,
    required this.blurb,
    this.card = false,
  });

  /// 'chat' | 'audio' | 'video' — the same strings the booking API takes as
  /// its `type`, so a channel chosen here can be posted unchanged.
  final String key;
  final String label;
  final String blurb;
  final bool card;
}

const List<ConsultationChannel> kConsultationChannels = [
  ConsultationChannel(
    key: 'chat',
    label: 'Chat',
    blurb: 'Typed messages',
    card: true,
  ),
  ConsultationChannel(key: 'audio', label: 'Call', blurb: 'Voice call'),
  ConsultationChannel(key: 'video', label: 'Video', blurb: 'Video call'),
];

/// How a per-channel price is stored: "chat:10", "audio:30", "video:60".
///
/// One map with compound keys rather than three maps, because the lawyers who
/// had prices before channels existed have them under the bare minutes — "10",
/// "30", "60" — and those keys keep working untouched.
String slotKey(String channel, int minutes) => '$channel:$minutes';

const int _minSlotPrice = 1;
const int _maxSlotPrice = 200000;

int _normalise(Object? raw) {
  final n = raw is num ? raw.round() : int.tryParse('$raw') ?? 0;
  if (n < _minSlotPrice || n > _maxSlotPrice) return 0;
  return n;
}

/// What this lawyer charges for a slot on a channel.
///
/// Their price for that channel, then the one they set before channels
/// existed, then ours. Each step is a real answer, so the first one found wins
/// and a lawyer is never quoted ₹0 — which is what an unset price used to mean
/// and why a new registration could sit in the directory taking nothing.
///
/// [prices] is the advocate's `slotPrices` map as the API sends it: absent for
/// almost every lawyer today, which is exactly the case the defaults cover.
int slotPriceFor(Map<String, dynamic>? prices, int minutes, {String? channel}) {
  ConsultationSlot? slot;
  for (final s in kConsultationSlots) {
    if (s.minutes == minutes) slot = s;
  }
  if (slot == null) return 0;

  int read(String key) => _normalise(prices?[key]);

  // In order: their price for this channel, their older shared price, ours.
  if (channel != null) {
    final own = read(slotKey(channel, slot.minutes));
    if (own != 0) return own;
  }
  final shared = read('${slot.minutes}');
  if (shared != 0) return shared;
  return slot.defaultPrice;
}

/// Every slot with the price this lawyer charges for it on one channel.
List<({ConsultationSlot slot, int price})> slotsFor(
  Map<String, dynamic>? prices, {
  String? channel,
}) =>
    [
      for (final s in kConsultationSlots)
        (slot: s, price: slotPriceFor(prices, s.minutes, channel: channel)),
    ];

/// The per-minute rate a booked slot bills at, floored to the paisa.
///
/// At ₹500 for thirty minutes the true rate is ₹16.666…; rounding to the
/// nearest paisa gives ₹16.67, and thirty of those is ₹500.10 — ten paise above
/// the price the client was quoted. Flooring leaves the slot a few paise short
/// instead, and a shortfall in the client's favour is the safe direction to be
/// wrong in. The server does the same, for the same reason.
double rateFor(int price, int minutes) {
  if (minutes <= 0) return 0;
  return (price / minutes * 100).floorToDouble() / 100;
}

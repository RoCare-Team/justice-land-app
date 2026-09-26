import 'advocate.dart';
import 'json.dart';

/// What the server understood from someone describing their problem out loud.
///
/// Mirrors `legal_analysis` from POST /api/voice/legal-search. Every field is
/// drawn from the directory's own vocabulary on the server — a practice area
/// it actually has, a matter a lawyer could have ticked — so nothing here is a
/// model's invention that the app then has to second-guess.
class VoiceAnalysis {
  const VoiceAnalysis({
    required this.category,
    required this.issue,
    required this.subIssue,
    required this.location,
    required this.urgency,
    required this.summary,
  });

  /// 'Labour & Employment' — empty when the problem could not be classified.
  final String category;

  /// 'Salary Dispute' — a short label for what is wrong.
  final String issue;

  /// 'Wage Disputes' — the specific matter, empty when there is none.
  final String subIssue;

  /// The city the search ran in, as the directory spells it.
  final String location;

  /// 'low' | 'medium' | 'high'.
  final String urgency;

  /// One sentence in the speaker's own language. Never advice.
  final String summary;

  bool get isUrgent => urgency == 'high';

  static const empty = VoiceAnalysis(
    category: '', issue: '', subIssue: '', location: '', urgency: 'medium', summary: '',
  );

  factory VoiceAnalysis.fromJson(Map<String, dynamic> j) => VoiceAnalysis(
        category: J.str(j['category']),
        issue: J.str(j['issue']),
        subIssue: J.str(j['sub_issue']),
        location: J.str(j['location']),
        urgency: J.str(j['urgency'], 'medium'),
        summary: J.str(j['summary']),
      );
}

/// One lawyer the search returned, with the reason it returned them.
///
/// The reason is written on the server from the facts the ranking used — the
/// area, the matter, the city, the verification — so it can never claim
/// something the ranking did not actually take into account.
class VoiceMatch {
  const VoiceMatch({required this.advocate, required this.reason});

  final Advocate advocate;
  final String reason;

  factory VoiceMatch.fromJson(Map<String, dynamic> j) => VoiceMatch(
        advocate: Advocate.fromJson(j),
        reason: J.str(J.map(j['match'])['reason']),
      );
}

/// The whole answer to one spoken problem.
class VoiceSearchResult {
  const VoiceSearchResult({
    required this.transcript,
    required this.analysis,
    required this.lawyers,
    required this.followUpQuestion,
    required this.relaxed,
    required this.toppedUp,
    required this.disclaimer,
  });

  /// What was heard, in whatever script it was spoken — shown back, because a
  /// wrong transcript is the one thing the speaker can see is wrong.
  final String transcript;

  final VoiceAnalysis analysis;
  final List<VoiceMatch> lawyers;

  /// The one short question worth asking when something essential is missing
  /// (in practice, the city). Empty when nothing needs asking.
  final String followUpQuestion;

  /// Which parts of the search had to be given up to find anyone at all —
  /// 'city', 'category'. Empty when the exact search worked.
  final List<String> relaxed;

  /// True when lawyers from outside the exact search were added to fill the
  /// list. Different from [relaxed]: the exact matches are still first.
  final bool toppedUp;

  final String disclaimer;

  bool get isEmpty => lawyers.isEmpty;
  bool get needsCity => followUpQuestion.isNotEmpty;

  factory VoiceSearchResult.fromJson(Map<String, dynamic> j) => VoiceSearchResult(
        transcript: J.str(j['transcript']),
        analysis: VoiceAnalysis.fromJson(J.map(j['legal_analysis'])),
        lawyers: J.models(j['lawyers'], VoiceMatch.fromJson),
        followUpQuestion: J.str(J.map(j['follow_up'])['question']),
        relaxed: J.strList(j['relaxed']),
        toppedUp: J.flag(j['topped_up']),
        disclaimer: J.str(j['disclaimer']),
      );
}

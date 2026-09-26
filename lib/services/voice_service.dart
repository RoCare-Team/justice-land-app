import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/json.dart';
import '../models/voice_search.dart';

/// "Tell us your legal problem" — the spoken way into the directory.
///
/// The recording goes up once and everything happens on the server: speech to
/// text, working out which area of law it is, and searching the lawyers. The
/// app never talks to a speech or AI service itself, so no key ships in the
/// binary and the same understanding runs for the website and the app.
class VoiceService {
  VoiceService(this._api);

  final ApiClient _api;

  /// Sends a recording and gets back the lawyers for it.
  ///
  /// [city] is only set when answering the follow-up question with the
  /// original recording still to hand.
  Future<VoiceSearchResult> search({
    required String filePath,
    required String mimeType,
    String city = '',
  }) async {
    final form = FormData.fromMap({
      'audio': await MultipartFile.fromFile(
        filePath,
        filename: filePath.split(RegExp(r'[\\/]')).last,
        contentType: DioMediaType.parse(mimeType),
      ),
      if (city.isNotEmpty) 'city': city,
    });

    final data = await _api.upload(Endpoints.voiceLegalSearch, form: form);
    return VoiceSearchResult.fromJson(J.map(data));
  }

  /// The same search from words already transcribed — how the follow-up answer
  /// is sent, and how a retry works. Deliberately separate from [search]: it
  /// skips speech-to-text entirely, so answering "which city?" costs nothing
  /// beyond the classification it has to redo.
  Future<VoiceSearchResult> searchText({
    required String transcript,
    String city = '',
  }) async {
    final data = await _api.post(
      Endpoints.voiceLegalSearch,
      body: {'transcript': transcript, if (city.isNotEmpty) 'city': city},
    );
    return VoiceSearchResult.fromJson(J.map(data));
  }
}

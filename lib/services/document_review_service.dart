import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/document_review.dart';
import '../models/json.dart';

/// Smart Document Check and Advocate Document Opinion — the website's
/// /api/document-review, for the app.
class DocumentReviewService {
  DocumentReviewService(this._api);

  final ApiClient _api;

  /// An AI read of a long PDF can take the better part of a minute; the
  /// server allows two.
  static const _aiTimeout = Duration(seconds: 150);

  /// Prices, accepted files and areas, plus this client's reviews (empty when
  /// signed out).
  Future<({ReviewPricing pricing, List<DocumentReview> reviews})> overview() async {
    final data = J.map(await _api.get(Endpoints.documentReviews));
    return (
      pricing: ReviewPricing.fromJson(J.map(data['pricing'])),
      reviews: J.models(data['reviews'], DocumentReview.fromJson),
    );
  }

  /// Uploads the document and prices it. Paid from the wallet when it covers
  /// the price; otherwise returns a Razorpay order.
  Future<ReviewStart> start({
    required String kind,
    required String path,
    required String fileName,
    String area = 'other',
    String question = '',
    void Function(double progress)? onProgress,
  }) async {
    final lower = fileName.toLowerCase();
    final type = lower.endsWith('.pdf')
        ? 'application/pdf'
        : lower.endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
    final form = FormData.fromMap({
      'kind': kind,
      'area': area,
      if (question.trim().isNotEmpty) 'question': question.trim(),
      'file': await MultipartFile.fromFile(path, filename: fileName, contentType: DioMediaType.parse(type)),
    });
    final data = await _api.upload(
      Endpoints.documentReviews,
      form: form,
      timeout: const Duration(seconds: 90),
      onSendProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total > 0) onProgress(sent / total);
            },
    );
    return ReviewStart.fromJson(J.map(data));
  }

  /// Proves a Razorpay payment. For an AI review the findings come back in the
  /// same answer, so this can take a minute. `pending` means the payment is
  /// still being confirmed — open the review a little later.
  Future<({DocumentReview? review, bool pending, String reviewId})> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final data = J.map(await _api.post(
      Endpoints.documentReviewVerify,
      body: {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      },
      timeout: _aiTimeout,
    ));
    return (
      review: data['review'] is Map ? DocumentReview.fromJson(J.map(data['review'])) : null,
      pending: J.flag(data['pending']),
      reviewId: J.str(data['reviewId']),
    );
  }

  /// One review. Runs a paid AI read that has not happened yet.
  Future<DocumentReview> read(String id) async {
    final data = J.map(await _api.get(Endpoints.documentReview(id), timeout: _aiTimeout));
    return DocumentReview.fromJson(J.map(data['review']));
  }

  // ── Lawyer ───────────────────────────────────────────────────────────────

  /// Advocate Document Opinion requests assigned to the signed-in lawyer.
  Future<List<DocumentReview>> assignedToMe() async {
    final data = J.map(await _api.get(Endpoints.lawyerDocumentReviews));
    return J.models(data['reviews'], DocumentReview.fromJson);
  }

  /// Sends the lawyer's written opinion; their share is credited on sending.
  Future<DocumentReview> sendReport(String id, String report) async {
    final data = J.map(await _api.post(
      Endpoints.lawyerDocumentReviews,
      body: {'id': id, 'report': report},
    ));
    return DocumentReview.fromJson(J.map(data['review']));
  }
}

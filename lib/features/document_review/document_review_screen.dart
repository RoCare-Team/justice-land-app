import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/document_review.dart';
import '../../services/document_review_service.dart';
import '../../state/auth_controller.dart';
import '../../state/wallet_controller.dart';

/// "Get your document checked" — the start of a Smart Document Check or an
/// Advocate Document Opinion: pick the product, attach the document, say what
/// it is, pay. The wallet pays when it can; otherwise Razorpay opens. Either
/// way the client lands on the review itself.
class DocumentReviewScreen extends StatefulWidget {
  const DocumentReviewScreen({super.key, this.initialKind = 'ai'});

  /// 'ai' or 'expert'.
  final String initialKind;

  @override
  State<DocumentReviewScreen> createState() => _DocumentReviewScreenState();
}

class _DocumentReviewScreenState extends State<DocumentReviewScreen> {
  late String _kind = widget.initialKind == 'expert' ? 'expert' : 'ai';
  ReviewPricing _pricing = ReviewPricing.fallback;
  String _area = 'property';
  final _question = TextEditingController();

  String? _path;
  String _fileName = '';
  int _fileSize = 0;

  bool _busy = false;
  double _progress = 0;
  String _stage = '';
  String _error = '';

  Razorpay? _razorpay;
  String _reviewId = '';

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  @override
  void dispose() {
    _razorpay?.clear();
    _question.dispose();
    super.dispose();
  }

  Future<void> _loadPricing() async {
    try {
      final o = await context.read<DocumentReviewService>().overview();
      if (!mounted) return;
      setState(() {
        _pricing = o.pricing;
        if (!_pricing.aiAvailable && _kind == 'ai') _kind = 'expert';
      });
    } catch (_) {
      // The fallback figures are the website's own; carry on with them.
    }
  }

  bool get _isPdf => _fileName.toLowerCase().endsWith('.pdf');

  String get _priceLabel {
    if (_kind == 'ai') return Fmt.money(_pricing.aiFee);
    if (_path != null && !_isPdf) return Fmt.money(_pricing.expertPrice(1));
    return '${Fmt.money(_pricing.ratePerPage)}/page';
  }

  /* ── Picking the document ───────────────────────────────────────────── */

  Future<void> _pickFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      );
      final f = picked?.files.single;
      if (f == null || f.path == null) return;
      _setFile(f.path!, f.name, f.size);
    } catch (_) {
      if (mounted) Toast.error(context, 'Could not open your files. Check the app permissions.');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2200, imageQuality: 82);
      if (x == null) return;
      _setFile(x.path, x.name.toLowerCase().endsWith('.png') ? x.name : '${x.name.split('.').first}.jpg', await x.length());
    } catch (_) {
      if (mounted) Toast.error(context, 'Could not open the camera. Check the app permissions.');
    }
  }

  void _setFile(String path, String name, int size) {
    if (size > _pricing.maxBytes) {
      Toast.error(context, 'That file is over ${(_pricing.maxBytes / 1024 / 1024).round()} MB. Choose a smaller one.');
      return;
    }
    setState(() {
      _path = path;
      _fileName = name;
      _fileSize = size;
      _error = '';
    });
  }

  /* ── Paying ─────────────────────────────────────────────────────────── */

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    if (!auth.isUser) {
      context.push('/login?redirect=${Uri.encodeComponent('/document-review?kind=$_kind')}');
      return;
    }
    if (_path == null || _busy) return;
    final service = context.read<DocumentReviewService>();
    final wallet = context.read<WalletController>();

    setState(() {
      _busy = true;
      _error = '';
      _progress = 0;
      _stage = 'Uploading your document…';
    });

    ReviewStart start;
    try {
      start = await service.start(
        kind: _kind,
        path: _path!,
        fileName: _fileName,
        area: _area,
        question: _question.text,
        onProgress: (p) => mounted ? setState(() => _progress = p) : null,
      );
    } on ApiException catch (e) {
      _fail(e.message);
      return;
    }
    _reviewId = start.reviewId;

    if (start.paid) {
      // The wallet covered it and the review is already paid. The balance
      // moved, so the wallet tab is refreshed too.
      unawaited(wallet.load(silent: true));
      _open(start.reviewId);
      return;
    }

    setState(() => _stage = 'Opening payment…');
    _razorpay?.clear();
    final rzp = Razorpay();
    _razorpay = rzp;
    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaid);
    rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      _fail(r.code == Razorpay.PAYMENT_CANCELLED
          ? 'Payment cancelled. Your document was not sent.'
          : (r.message?.isNotEmpty ?? false) ? r.message! : 'Payment failed. Please try again.');
    });
    rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
    try {
      rzp.open({
        'key': start.keyId,
        'order_id': start.orderId,
        'amount': start.amountPaise,
        'currency': start.currency,
        'name': 'Justiceland',
        'description': _kind == 'ai' ? 'Smart Document Check' : 'Advocate Document Opinion · ${start.pages} page(s)',
        'prefill': {'name': start.prefillName, 'email': start.prefillEmail, 'contact': start.prefillContact},
        'theme': {'color': '#1E3A5F'},
      });
    } catch (_) {
      _fail('Could not open the payment screen. Please try again.');
    }
  }

  Future<void> _onPaid(PaymentSuccessResponse r) async {
    if (!mounted) return;
    setState(() => _stage = _kind == 'ai' ? 'Payment done. AI is reading your document…' : 'Payment done. Confirming…');
    try {
      final result = await context.read<DocumentReviewService>().verify(
            orderId: r.orderId ?? '',
            paymentId: r.paymentId ?? '',
            signature: r.signature ?? '',
          );
      _open(result.review?.id ?? (result.reviewId.isNotEmpty ? result.reviewId : _reviewId));
    } on ApiException catch (_) {
      // Paid but not confirmed — the webhook settles it; the review page
      // re-reads and finishes the AI read when opened.
      _open(_reviewId);
    }
  }

  void _open(String id) {
    if (!mounted) return;
    setState(() => _busy = false);
    context.pushReplacement('/document-reviews/$id');
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  /* ── UI ─────────────────────────────────────────────────────────────── */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(
        title: const Text('Get a document checked'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/document-reviews'),
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('My reviews'),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomGutter(context)),
          children: [
            _sectionTitle('1. Choose how'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ProductCard(
                    selected: _kind == 'ai',
                    enabled: _pricing.aiAvailable,
                    badge: 'READY IN 2 MIN',
                    badgeColor: const Color(0xFF059669),
                    icon: Icons.document_scanner_rounded,
                    iconColor: const Color(0xFF10B981),
                    title: 'Smart Document Check',
                    body: 'AI flags hidden risks, one-sided terms and anything missing.',
                    price: '${Fmt.money(_pricing.aiFee)} flat',
                    onTap: () => setState(() => _kind = 'ai'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ProductCard(
                    selected: _kind == 'expert',
                    badge: 'EXPERT OPINION',
                    badgeColor: const Color(0xFFEA580C),
                    icon: Icons.assignment_turned_in_rounded,
                    iconColor: const Color(0xFFF97316),
                    title: 'Advocate Document Opinion',
                    body: 'A verified advocate sends a written opinion within ${_pricing.deliveryHours} hours.',
                    price: 'From ${Fmt.money(_pricing.ratePerPage)}/page',
                    onTap: () => setState(() => _kind = 'expert'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _sectionTitle('2. Attach the document'),
            _filePanel(),
            const SizedBox(height: 22),
            _sectionTitle('3. What kind of document is it?'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in _pricing.areas)
                  ChoiceChip(
                    label: Text(a.label.split(' (').first),
                    selected: _area == a.value,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _area = a.value),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _area == a.value ? Colors.white : AppColors.ink.withValues(alpha: 0.75),
                    ),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surface,
                    side: BorderSide(color: _area == a.value ? AppColors.primary : AppColors.border),
                    shape: const StadiumBorder(),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _question,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Anything specific to look at? (optional)',
                hintText: 'e.g. Is the lock-in clause fair to me?',
                alignLabelWithHint: true,
                filled: true,
                fillColor: AppColors.surface,
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 6),
              NoticeBanner(message: _error, tone: ChipTone.danger, icon: Icons.error_outline_rounded),
            ],
            const SizedBox(height: 16),
            _payBar(),
            const SizedBox(height: 10),
            Text(
              'Your document is private — only you${_kind == 'expert' ? ', the assigned advocate' : ''} and our team can open it. '
              '${_kind == 'ai' ? 'The AI check is information, not legal advice.' : ''}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, height: 1.45, color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
      );

  Widget _filePanel() {
    if (_path != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: _isPdf ? AppColors.dangerSoft : AppColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                  color: _isPdf ? AppColors.danger : AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_fileName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${(_fileSize / 1024).round()} KB', style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
                ],
              ),
            ),
            TextButton(onPressed: _pickFile, child: const Text('Change')),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(
        children: [
          Icon(Icons.upload_file_rounded, size: 34, color: AppColors.primary.withValues(alpha: 0.8)),
          const SizedBox(height: 8),
          const Text('PDF, JPG or PNG', style: TextStyle(fontWeight: FontWeight.w700)),
          Text(
            'Up to ${(_pricing.maxBytes / 1024 / 1024).round()} MB${_kind == 'ai' ? ' · ${_pricing.aiMaxPages} pages max' : ''}',
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Choose file'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _takePhoto,
                  icon: const Icon(Icons.photo_camera_rounded, size: 18),
                  label: const Text('Take photo'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payBar() {
    final expertPdf = _kind == 'expert' && (_path == null || _isPdf);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_kind == 'ai' ? 'Smart Document Check' : 'Advocate Document Opinion',
                        style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                    Text(_priceLabel, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              if (expertPdf)
                Flexible(
                  child: Text(
                    'Priced by page count — ${Fmt.money(_pricing.ratePerPageLong)}/page '
                    'from ${_pricing.longFromPages} pages.',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, height: 1.35, color: AppColors.inkFaint),
                  ),
                ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: _progress > 0 && _progress < 1 ? _progress : null, minHeight: 5),
            ),
            const SizedBox(height: 6),
            Text(_stage, style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            label: _path == null
                ? 'Attach a document first'
                : _kind == 'ai'
                    ? 'Pay ${Fmt.money(_pricing.aiFee)} & check now'
                    : 'Continue to payment',
            busy: _busy,
            onPressed: _path == null ? null : _submit,
          ),
          const SizedBox(height: 6),
          Text(
            'Paid from your wallet when it has enough, otherwise by UPI / card.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.selected,
    required this.badge,
    required this.badgeColor,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.price,
    required this.onTap,
    this.enabled = true,
  });

  final bool selected;
  final bool enabled;
  final String badge;
  final Color badgeColor;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: selected ? 2 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(20)),
                      child: Text(badge,
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                    const Spacer(),
                    Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                        size: 20, color: selected ? AppColors.accent : AppColors.inkFaint),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(color: iconColor, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(height: 10),
                Text(title, style: const TextStyle(fontSize: 14.5, height: 1.2, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(body, style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.inkMuted)),
                const SizedBox(height: 8),
                Text(price, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The two document products as a pair of cards — for Home, the same pair
/// the website shows under "How would you like legal help today?".
class DocumentReviewPromo extends StatelessWidget {
  const DocumentReviewPromo({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Get your papers checked', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('Agreements, notices, deeds — before you sign or reply.',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ProductCard(
                selected: false,
                badge: 'READY IN 2 MIN',
                badgeColor: const Color(0xFF059669),
                icon: Icons.document_scanner_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'Smart Document Check',
                body: 'AI flags hidden risks, one-sided terms and anything missing.',
                price: '₹199 flat',
                onTap: () => context.push('/document-review?kind=ai'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProductCard(
                selected: false,
                badge: 'EXPERT OPINION',
                badgeColor: const Color(0xFFEA580C),
                icon: Icons.assignment_turned_in_rounded,
                iconColor: const Color(0xFFF97316),
                title: 'Advocate Document Opinion',
                body: 'A verified advocate sends a written opinion within 24 hours.',
                price: 'From ₹149/page',
                onTap: () => context.push('/document-review?kind=expert'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

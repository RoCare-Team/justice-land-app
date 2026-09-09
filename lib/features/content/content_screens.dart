import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/account.dart';
import '../../services/content_service.dart';
import '../../state/auth_controller.dart';

/// Legal blogs — the list.
class BlogsScreen extends StatefulWidget {
  const BlogsScreen({super.key});

  @override
  State<BlogsScreen> createState() => _BlogsScreenState();
}

class _BlogsScreenState extends State<BlogsScreen> {
  List<BlogPost> _posts = [];

  /// The categories the published articles actually carry, learned from the
  /// unfiltered load rather than hardcoded. A fixed row of chips is a promise
  /// about what has been written, and it stops being true the moment an admin
  /// publishes under a new heading or retires an old one.
  List<String> _categories = [];
  String _category = '';

  bool _loading = true;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await context.read<ContentService>().blogs(category: _category);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        // Only the unfiltered list knows the full set. Rebuilding the chips
        // from a filtered one would narrow them to the choice already made and
        // strand the reader inside it.
        if (_category.isEmpty) {
          _categories = posts
              .map((p) => p.category)
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
        }
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _pick(String category) {
    if (category == _category) return;
    setState(() => _category = category);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Legal Guides')),
      body: Column(
        children: [
          if (_categories.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                children: [
                  SelectableChip(
                    label: 'All',
                    selected: _category.isEmpty,
                    onTap: () => _pick(''),
                  ),
                  for (final category in _categories) ...[
                    const SizedBox(width: 8),
                    SelectableChip(
                      label: category,
                      selected: _category == category,
                      onTap: () => _pick(category),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const SkeletonList(count: 4, height: 120);

    final error = _error;
    if (error != null) {
      return ErrorView(
        message: error.message,
        isNetwork: error.isNetwork,
        onRetry: _load,
      );
    }

    if (_posts.isEmpty) {
      return EmptyView(
        icon: Icons.article_outlined,
        title: _category.isEmpty ? 'No articles yet' : 'Nothing under $_category',
        message: _category.isEmpty
            ? 'Legal guides and explainers will appear here.'
            : 'No article has been published under this heading yet.',
        action: _category.isEmpty
            ? null
            : OutlinedButton(
                onPressed: () => _pick(''),
                child: const Text('Show all articles'),
              ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        itemCount: _posts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _card(_posts[i]),
      ),
    );
  }

  Widget _card(BlogPost post) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/blogs/${post.slug}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (post.image.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: Avatar.resolveUrl(post.image),
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(height: 150, color: AppColors.muted),
                  errorWidget: (_, __, ___) =>
                      Container(height: 150, color: AppColors.muted),
                ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post.category.isNotEmpty) ...[
                      Tag(label: post.category, tone: AppColors.accent),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      post.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    if (post.excerpt.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        post.excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          Fmt.date(post.publishedAt),
                          style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                        ),
                        if (post.readTime.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '· ${post.readTime}',
                            style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One blog post.
class BlogDetailScreen extends StatefulWidget {
  const BlogDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  State<BlogDetailScreen> createState() => _BlogDetailScreenState();
}

class _BlogDetailScreenState extends State<BlogDetailScreen> {
  BlogPost? _post;
  bool _loading = true;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final post = await context.read<ContentService>().blog(widget.slug);
      if (!mounted) return;
      setState(() {
        _post = post;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// The body comes from the admin's rich-text editor as HTML. Rendering a
  /// full HTML engine for a few paragraphs is not worth the dependency, so the
  /// tags are stripped and the paragraph breaks kept.
  String _plainText(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '•  ')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Article')),
        body: const LoadingView(),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Article')),
        body: ErrorView(
          message: _error!.message,
          isNetwork: _error!.isNetwork,
          onRetry: _load,
        ),
      );
    }

    final post = _post!;
    return Scaffold(
      appBar: AppBar(title: const Text('Article')),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (post.image.isNotEmpty)
            CachedNetworkImage(
              imageUrl: Avatar.resolveUrl(post.image),
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  Container(height: 200, color: AppColors.muted),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.category.isNotEmpty) ...[
                  Tag(label: post.category, tone: AppColors.accent),
                  const SizedBox(height: 12),
                ],
                Text(post.title,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (post.author.isNotEmpty) ...[
                      Avatar(name: post.author, size: 26),
                      const SizedBox(width: 8),
                      Text(
                        post.author,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      Fmt.date(post.publishedAt),
                      style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                    ),
                  ],
                ),
                const Divider(height: 28),
                Text(
                  _plainText(post.content),
                  style: const TextStyle(fontSize: 15, height: 1.7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The contact form.
class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  final _subject = TextEditingController();
  final _message = TextEditingController();

  bool _busy = false;
  bool _sent = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    _name = TextEditingController(text: auth.user?.name ?? auth.advocate?.name ?? '');
    _email = TextEditingController(
        text: auth.user?.email ?? auth.advocate?.contact.email ?? '');
    _phone = TextEditingController(
        text: auth.user?.phone ?? auth.advocate?.contact.phone ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await context.read<ContentService>().submitContact(
            name: _name.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim(),
            subject: _subject.text.trim(),
            message: _message.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contact')),
        body: SuccessView(
          title: 'Message sent',
          message: 'Our team will get back to you shortly.',
          primaryAction: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Back to home'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Contact us')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Get in touch',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Questions, feedback or something wrong with your account — '
                'write to us and we will answer.',
                style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 22),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                validator: (v) => Validators.required$(v, 'Your name'),
                decoration: const InputDecoration(labelText: 'Your name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                validator: Validators.email,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                validator: Validators.phoneLoose,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _subject,
                validator: (v) => Validators.required$(v, 'Subject'),
                decoration: const InputDecoration(labelText: 'Subject'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _message,
                maxLines: 5,
                validator: (v) => (v ?? '').trim().length < 10
                    ? 'Please write a little more.'
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                ),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 14),
                NoticeBanner(
                  message: _error,
                  tone: ChipTone.danger,
                  icon: Icons.error_outline_rounded,
                ),
              ],
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Send message',
                busy: _busy,
                icon: Icons.send_rounded,
                onPressed: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

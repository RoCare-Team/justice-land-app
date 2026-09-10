import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../state/auth_controller.dart';
import '../../state/wallet_controller.dart';

/// The client's own account, as a list of places to go.
///
/// The heading names the person the way the lawyers see them, which is the
/// whole point of the switch below it: with anonymity on it reads "Anonymous
/// User", because that is what a lawyer is shown, and a profile that greets you
/// by a name lawyers never see would quietly contradict the setting.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    // A signed-in lawyer used to land on the signed-out screen and be asked to
    // sign in — which they had just done. Their account is an Advocate, not a
    // User, and `isUser` is false for them; the fix is their own view, not a
    // looser check.
    if (auth.isAdvocate) return const _AdvocateProfile();
    if (!auth.isUser) return const _SignedOutProfile();

    final user = auth.user!;
    final wallet = context.watch<WalletController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: () => context.push('/more'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Row(
            children: [
              Avatar(
                name: user.anonymous ? 'Anonymous User' : user.displayName,
                photo: user.anonymous ? null : user.photo,
                size: 60,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.anonymous ? 'Anonymous User' : user.displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // The mobile number is the account's identity — there is
                      // no username to show, and printing the number is what
                      // lets someone confirm which account they are in.
                      Fmt.phone(user.phone),
                      style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () => _editName(context, auth),
                      child: const Text('Edit Profile'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          _Rows(
            children: [
              _Row(
                icon: Icons.badge_outlined,
                label: 'Personal Details',
                value: user.needsName ? 'Add your name' : user.name,
                onTap: () => _editName(context, auth),
              ),
              _AnonymousRow(auth: auth),
              _Row(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Wallet',
                value: wallet.loading ? null : Fmt.money(wallet.balance),
                onTap: () => context.go('/wallet'),
              ),
              _Row(
                icon: Icons.forum_outlined,
                label: 'My Consultations',
                onTap: () => context.go('/consultations'),
              ),
              // Consultations and orders both live here rather than in the
              // bottom bar: each matters enormously on the day you have one
              // and not at all on the days you do not, which is the wrong
              // shape for a permanent tab.
              _Row(
                icon: Icons.receipt_long_outlined,
                label: 'My Orders',
                onTap: () => context.push('/orders'),
              ),
              _Row(
                icon: Icons.article_outlined,
                label: 'Legal Guides',
                onTap: () => context.push('/blogs'),
              ),
            ],
          ),

          const SizedBox(height: 14),
          _Rows(
            children: [
              _Row(
                icon: Icons.more_horiz_rounded,
                label: 'More',
                onTap: () => context.push('/more'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Name is the only editable field: everything else about a client account is
  /// either the mobile number that identifies it or a preference with its own
  /// control. A full edit form would be four read-only rows and one input.
  Future<void> _editName(BuildContext context, AuthController auth) async {
    final controller = TextEditingController(text: auth.user?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Rahul Sharma'),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return;
    final ok = await auth.setName(trimmed);
    if (!context.mounted) return;
    if (ok) {
      Toast.success(context, 'Name saved.');
    } else {
      Toast.error(context, auth.error ?? 'Could not save your name.');
    }
  }
}

/// Anonymity is a switch, not a page, so it sits in the list as one.
class _AnonymousRow extends StatelessWidget {
  const _AnonymousRow({required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final on = auth.user?.anonymous ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.visibility_off_outlined, size: 20, color: AppColors.inkMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Anonymous Mode',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  on
                      ? 'Lawyers see “Anonymous” instead of your name'
                      : 'Lawyers see your name when you book',
                  style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: on,
            onChanged: auth.busy
                ? null
                : (value) async {
                    final ok = await auth.setAnonymous(value);
                    if (!context.mounted) return;
                    if (ok) {
                      Toast.success(
                        context,
                        value
                            ? 'Lawyers will see “Anonymous”.'
                            : 'Lawyers will see your name.',
                      );
                    } else {
                      Toast.error(context, auth.error ?? 'Could not update.');
                    }
                  },
          ),
        ],
      ),
    );
  }
}

/// A card holding rows, hairline-separated.
class _Rows extends StatelessWidget {
  const _Rows({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 48, color: AppColors.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.tone,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colour = tone ?? AppColors.ink;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tone ?? AppColors.inkMuted),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: colour,
                ),
              ),
            ),
            if (value != null && value!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  value!,
                  style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                ),
              ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// The Profile tab for a signed-in lawyer.
///
/// Their account is not a client account: there is no wallet to top up and no
/// anonymity switch, because neither exists on an Advocate. What a lawyer
/// wants from this tab is their own listing, the profile editor, and the way
/// out — so that is what it holds.
class _AdvocateProfile extends StatelessWidget {
  const _AdvocateProfile();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final advocate = auth.advocate;

    if (advocate == null) {
      // Signed in as a lawyer but the record has not arrived yet.
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const LoadingView(label: 'Loading your account…'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: () => context.push('/more'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Row(
            children: [
              Avatar(name: advocate.name, photo: advocate.photo, size: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      advocate.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Tag(label: advocate.legalCareId),
                        const SizedBox(width: 8),
                        Tag(
                          label: advocate.available ? 'Online' : 'Offline',
                          tone: advocate.available
                              ? AppColors.success
                              : AppColors.inkMuted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () => context.push('/dashboard/profile'),
                      child: const Text('Edit Profile'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _Rows(
            children: [
              _Row(
                icon: Icons.dashboard_outlined,
                label: 'Dashboard',
                onTap: () => context.go('/dashboard'),
              ),
              _Row(
                icon: Icons.forum_outlined,
                label: 'My Consultations',
                onTap: () => context.go('/consultations'),
              ),
              _Row(
                icon: Icons.badge_outlined,
                label: 'Edit my listing',
                onTap: () => context.push('/dashboard/profile'),
              ),
              // Their own public page, seen the way a client sees it — the one
              // check a lawyer actually wants before sharing the link.
              _Row(
                icon: Icons.visibility_outlined,
                label: 'View my public profile',
                onTap: () => context.push('/lawyers/${advocate.profilePath}'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Rows(
            children: [
              _Row(
                icon: Icons.article_outlined,
                label: 'Legal Guides',
                onTap: () => context.push('/blogs'),
              ),
              _Row(
                icon: Icons.more_horiz_rounded,
                label: 'More',
                onTap: () => context.push('/more'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () async {
              await context.read<AuthController>().signOut();
              if (context.mounted) context.go('/');
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger.withOpacity(0.35)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Signed out. Both doors are here rather than only the client one — a lawyer
/// opening the app looks for their own dashboard, not a client sign-in.
class _SignedOutProfile extends StatelessWidget {
  const _SignedOutProfile();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        children: [
          Container(
            height: 76,
            width: 76,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_outline_rounded, size: 34, color: AppColors.primary),
          ),
          const SizedBox(height: 18),
          Text('You are not signed in', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Sign in with your mobile number to book consultations, keep your '
            'chat history and top up your wallet.',
            style: TextStyle(fontSize: 14, height: 1.55, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: () => context.push('/login?redirect=/profile'),
            child: const Text('Sign in'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => context.push('/advocate/login'),
            child: const Text('I am a lawyer'),
          ),
          const SizedBox(height: 24),
          _Rows(
            children: [
              _Row(
                icon: Icons.article_outlined,
                label: 'Legal Guides',
                onTap: () => context.push('/blogs'),
              ),
              _Row(
                icon: Icons.more_horiz_rounded,
                label: 'More',
                onTap: () => context.push('/more'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

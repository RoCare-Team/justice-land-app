import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// The system back button on a bottom-bar tab.
///
/// Tabs are switched with `go`, so there is nothing under them to pop and back
/// used to close the app from wherever the user was. Now back from any other
/// tab lands on [homePath] first, and back from there asks before leaving.
class TabBackGuard extends StatelessWidget {
  const TabBackGuard({super.key, required this.homePath, required this.child});

  final String homePath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (location != homePath) {
          context.go(homePath);
          return;
        }
        if (await confirmExit(context)) SystemNavigator.pop();
      },
      child: child,
    );
  }
}

/// "Exit the app?" — true when the user chose to leave.
Future<bool> confirmExit(BuildContext context) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Exit app?'),
      content: const Text('Are you sure you want to exit JusticeLand?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Exit'),
        ),
      ],
    ),
  );
  return leave ?? false;
}

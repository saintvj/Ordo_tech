import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/gathering_controller.dart';
import '../core/theme/theme.dart';
import 'router.dart';

/// The app's router. Kept alive for the app's lifetime so its
/// [_GatheringRouterRefresh] listener stays attached to [gatheringProvider].
final routerProvider = Provider<GoRouter>((ref) => buildRouter(ref));

class OrdoApp extends ConsumerStatefulWidget {
  const OrdoApp({super.key});

  @override
  ConsumerState<OrdoApp> createState() => _OrdoAppState();
}

class _OrdoAppState extends ConsumerState<OrdoApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // A problem found at start-up was reported before this widget could
    // listen for it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final issue = ref.read(storageIssueProvider);
      if (issue != null) _showIssue(issue);
    });
  }

  void _showIssue(StorageIssue issue) {
    final onAction = issue.onAction;
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(issue.message),
          behavior: SnackBarBehavior.floating,
          // The retry is on the message itself: a floating snackbar can
          // cover the button the user would otherwise tap again.
          action: onAction == null
              ? null
              : SnackBarAction(
                  label: issue.actionLabel ?? 'Try Again',
                  onPressed: onAction,
                ),
        ),
      );
    ref.read(storageIssueProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(storageIssueProvider, (previous, next) {
      if (next != null) _showIssue(next);
    });
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Ordo',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      routerConfig: router,
    );
  }
}

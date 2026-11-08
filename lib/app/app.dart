import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/theme.dart';
import 'router.dart';

/// The app's router. Kept alive for the app's lifetime so its
/// [_GatheringRouterRefresh] listener stays attached to [gatheringProvider].
final routerProvider = Provider<GoRouter>((ref) => buildRouter(ref));

class OrdoApp extends ConsumerWidget {
  const OrdoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Ordo',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}

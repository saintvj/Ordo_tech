import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import '../../application/gathering_controller.dart';
import '../../application/startup.dart';
import '../../data/gathering_repository.dart';
import 'gathering_tile.dart';
import 'history_screen.dart';

final _unfinishedProvider = FutureProvider.autoDispose<GatheringList>(
  (ref) => ref.watch(gatheringRepositoryProvider).listUnfinished(),
);

/// Shown on start-up when more than one gathering is unfinished, so the user
/// picks which one to continue instead of the app choosing.
class ResumeScreen extends ConsumerWidget {
  const ResumeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unfinished = ref.watch(_unfinishedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unfinished Gatherings'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: unfinished.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => Center(
                  child: Text(
                    "Unfinished gatherings couldn't be loaded.",
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                data: (listing) => ListView(
                  padding: const EdgeInsets.all(24.0),
                  children: [
                    Text(
                      'Pick up where you left off.',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'More than one gathering was still in progress. '
                      'Choose the one to continue.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    if (listing.hasUnreadable) ...[
                      const SizedBox(height: 12),
                      Text(
                        unreadableMessage(listing),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    for (final summary in listing.gatherings)
                      GatheringTile(
                        summary: summary,
                        onTap: () => openSavedGathering(context, ref, summary),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: TextButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Not Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

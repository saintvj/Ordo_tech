import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import '../../application/gathering_controller.dart';
import '../../application/startup.dart';
import '../../data/gathering_repository.dart';
import '../../domain/models.dart';
import 'gathering_tile.dart';
import '../../shared/widgets/message_view.dart';

/// Every saved gathering, newest first.
final gatheringHistoryProvider = FutureProvider.autoDispose<GatheringList>(
  (ref) => ref.watch(gatheringRepositoryProvider).listAll(),
);

/// Opens a gathering from a history or resume list: completed ones open
/// read-only; unfinished ones become the active gathering again, and the
/// router then shows their current stage.
Future<void> openSavedGathering(
  BuildContext context,
  WidgetRef ref,
  GatheringSummary summary,
) async {
  if (summary.status.isFinished) {
    context.push(Routes.historyDetailFor(summary.id));
    return;
  }
  try {
    await ref.read(gatheringProvider.notifier).resume(summary.id);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("This gathering couldn't be opened. Try again."),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final history = ref.watch(gatheringHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Past Gatherings')),
      body: SafeArea(
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => MessageView(
            message: "Past gatherings couldn't be loaded.",
            actionLabel: 'Try Again',
            onAction: () => ref.invalidate(gatheringHistoryProvider),
          ),
          data: (listing) =>
              listing.gatherings.isEmpty && !listing.hasUnreadable
              ? const MessageView(
                  message: 'Gatherings you start will appear here.',
                )
              : ListView(
                  padding: const EdgeInsets.all(24.0),
                  children: [
                    Text(
                      'Tap a completed gathering to see its bill, or an '
                      'unfinished one to carry on.',
                      style: theme.textTheme.bodyMedium?.copyWith(
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
                    const SizedBox(height: 24),
                    for (final summary in listing.gatherings)
                      GatheringTile(
                        summary: summary,
                        onTap: () => openSavedGathering(context, ref, summary),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/gathering_controller.dart';

/// The "More options" menu on the active gathering's screens. It holds
/// actions that should be easy to find but not compete with the main flow,
/// currently just Discard Gathering.
class GatheringMenuButton extends ConsumerWidget {
  const GatheringMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_GatheringAction>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'More options',
      onSelected: (action) => switch (action) {
        _GatheringAction.discard => confirmAndDiscard(context, ref),
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _GatheringAction.discard,
          child: Text('Discard Gathering'),
        ),
      ],
    );
  }
}

enum _GatheringAction { discard }

/// Asks before permanently deleting the active gathering, then deletes it.
/// Navigation to Home happens only once the delete has succeeded (the
/// router reacts to the gathering being cleared).
Future<void> confirmAndDiscard(BuildContext context, WidgetRef ref) async {
  final gathering = ref.read(gatheringProvider);
  if (gathering == null) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => const _DiscardDialog(),
  );
  if (confirmed != true) return;
  await ref.read(gatheringProvider.notifier).discardGathering();
}

class _DiscardDialog extends ConsumerWidget {
  const _DiscardDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = ref.read(gatheringProvider)?.name ?? 'this gathering';
    return AlertDialog(
      title: const Text('Discard this gathering?'),
      content: Text(
        '"$name" and its menu, orders and serving progress will be '
        'permanently deleted from this phone. Completed gatherings in your '
        'history are not affected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Discard'),
        ),
      ],
    );
  }
}

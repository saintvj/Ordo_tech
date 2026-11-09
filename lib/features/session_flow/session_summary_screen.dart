import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import '../../application/gathering_controller.dart';

class SessionSummaryScreen extends ConsumerWidget {
  const SessionSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gathering = ref.watch(gatheringProvider);
    if (gathering == null) return const Scaffold();
    return Scaffold(
      appBar: AppBar(
        title: const Text('End of Session'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(24.0),
                itemCount: gathering.participants.length,
                itemBuilder: (context, index) {
                  final participant = gathering.participants[index];
                  // One row per portion, so served state is shown per portion
                  final items = [
                    for (final line in gathering.linesFor(participant.id))
                      for (var i = 0; i < line.quantity; i++)
                        (
                          name: line.itemName,
                          isServed: i < line.servedQuantity,
                        ),
                  ];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          participant.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  item.isServed
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  size: 16,
                                  color: item.isServed
                                      ? theme.colorScheme.tertiary
                                      : theme.colorScheme.error,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    context.push(Routes.billSummary);
                  },
                  child: const Text('View Bill'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

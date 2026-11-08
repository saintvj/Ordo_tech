import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/gathering_controller.dart';
import '../../domain/money.dart';
import 'participant_order_screen.dart';

class ReviewOrdersScreen extends ConsumerWidget {
  const ReviewOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gathering = ref.watch(gatheringProvider);
    if (gathering == null) return const Scaffold();

    return Scaffold(
      appBar: AppBar(title: const Text('Review Orders')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(24.0),
                itemCount: gathering.participants.length,
                itemBuilder: (context, index) {
                  final participant = gathering.participants[index];
                  final lines = gathering.linesFor(participant.id);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              participant.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Text(
                              formatRupees(
                                gathering.subtotalFor(participant.id),
                              ),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...lines.map((line) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${line.itemName} × ${line.quantity}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                Text(
                                  formatRupees(line.totalPaise),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          );
                        }),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.pushNamed(
                                context,
                                '/participant_order',
                                arguments: ParticipantOrderArgs.edit(
                                  participant.id,
                                ),
                              );
                            },
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Edit'),
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
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: gathering.orderLines.isEmpty
                      ? null
                      : () {
                          ref.read(gatheringProvider.notifier).startServing();
                          // Ordering is over: clear the ordering screens from
                          // the back stack.
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/waiter_mode',
                            (route) => route.isFirst,
                          );
                        },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start Waiter Mode'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

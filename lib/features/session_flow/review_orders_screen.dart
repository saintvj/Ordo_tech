import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import '../../application/gathering_controller.dart';
import '../../domain/money.dart';
import 'participant_order_screen.dart';
import 'gathering_menu_button.dart';
import '../../shared/widgets/message_view.dart';

class ReviewOrdersScreen extends ConsumerWidget {
  const ReviewOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gathering = ref.watch(gatheringProvider);
    if (gathering == null) return const Scaffold();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Orders'),
        actions: const [GatheringMenuButton()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: gathering.participants.isEmpty
                  // Every order was removed while editing.
                  ? MessageView(
                      title: 'No orders yet',
                      message: 'Add someone to start taking orders.',
                      actionLabel: 'Add Someone',
                      onAction: () => context.go(Routes.participantName),
                    )
                  : ListView.builder(
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      participant.name,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    formatRupees(
                                      gathering.subtotalFor(participant.id),
                                    ),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ...lines.map((line) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${line.itemName} × ${line.quantity}',
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
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
                                    // push (not go): this edit should return here
                                    // afterwards, unlike the pass-and-play cycle.
                                    context.push(
                                      ParticipantOrderArgs.edit(
                                        participant.id,
                                      ).location,
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
                    color: Colors.black.withValues(alpha: 0.05),
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
                          // startServing() moves the gathering to serving;
                          // the router's redirect will refuse every
                          // ordering-stage route from now on. go clears
                          // the ordering screens (including any pushed
                          // edits) from the back stack in one step.
                          ref.read(gatheringProvider.notifier).startServing();
                          context.go(Routes.waiterMode);
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

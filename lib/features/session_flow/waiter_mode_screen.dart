import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import '../../application/gathering_controller.dart';
import '../../domain/models.dart';

/// One portion to hand over: unit [index] of an order line.
class _ServingUnit {
  const _ServingUnit(this.line, this.index);

  final OrderLine line;
  final int index;

  bool get isServed => index < line.servedQuantity;
}

class WaiterModeScreen extends ConsumerWidget {
  const WaiterModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gathering = ref.watch(gatheringProvider);
    if (gathering == null) return const Scaffold();

    // Group portions by menu item
    final Map<String, List<_ServingUnit>> unitsByItem = {};
    for (final line in gathering.orderLines) {
      final units = unitsByItem.putIfAbsent(line.menuItemId, () => []);
      for (var i = 0; i < line.quantity; i++) {
        units.add(_ServingUnit(line, i));
      }
    }

    // Serving has started; there is no going back to ordering.
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Service'),
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: () {
                context.push(Routes.sessionSummary);
              },
              child: const Text('Finish Service'),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: unitsByItem.values.map((orders) {
              final itemName = orders.first.line.itemName;
              final servedCount = orders.where((o) => o.isServed).length;
              final totalCount = orders.length;
              final isComplete = servedCount == totalCount;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(bottom: 24.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isComplete
                        ? theme.colorScheme.tertiary.withOpacity(0.5)
                        : theme.colorScheme.onSurface.withOpacity(0.05),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: isComplete ? 0.6 : 1.0,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                itemName,
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                            Text(
                              '$servedCount / $totalCount Served',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: isComplete
                                    ? theme.colorScheme.tertiary
                                    : theme.colorScheme.onSurface.withOpacity(
                                        0.7,
                                      ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: totalCount == 0
                                ? 0
                                : servedCount / totalCount,
                            minHeight: 8,
                            backgroundColor: theme.colorScheme.onSurface
                                .withOpacity(0.05),
                            color: isComplete
                                ? theme.colorScheme.tertiary
                                : theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ...orders.map((order) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                final line = order.line;
                                ref
                                    .read(gatheringProvider.notifier)
                                    .setServedQuantity(
                                      line.id,
                                      order.isServed
                                          ? line.servedQuantity - 1
                                          : line.servedQuantity + 1,
                                    );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: order.isServed
                                      ? theme.colorScheme.tertiary.withOpacity(
                                          0.1,
                                        )
                                      : theme.colorScheme.background,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      gathering
                                              .findParticipant(
                                                order.line.participantId,
                                              )
                                              ?.name ??
                                          '',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            decoration: order.isServed
                                                ? TextDecoration.lineThrough
                                                : null,
                                            color: order.isServed
                                                ? theme.colorScheme.tertiary
                                                : theme.colorScheme.onSurface,
                                          ),
                                    ),
                                    Icon(
                                      order.isServed
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      color: order.isServed
                                          ? theme.colorScheme.tertiary
                                          : theme.colorScheme.onSurface
                                                .withOpacity(0.2),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/gathering_controller.dart';
import '../../domain/money.dart';

class BillSummaryScreen extends ConsumerWidget {
  const BillSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gathering = ref.watch(gatheringProvider);
    if (gathering == null) return const Scaffold();

    // One row per portion
    final rows = [
      for (final line in gathering.orderLines)
        for (var i = 0; i < line.quantity; i++)
          (
            name: line.itemName,
            participant:
                gathering.findParticipant(line.participantId)?.name ?? '',
            pricePaise: line.unitPricePaise,
          ),
    ];

    final subtotal = gathering.subtotalPaise;
    // Placeholder tax rates (2.5% each) until the billing engine in v0.5
    final cgst = percentOf(subtotal, 250);
    final sgst = percentOf(subtotal, 250);
    final grandTotal = subtotal + cgst + sgst;

    return Scaffold(
      appBar: AppBar(
        title: const Text('L\'Addition'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          gathering.restaurantName,
                          style: theme.textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          gathering.name,
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        const Divider(),
                        const SizedBox(height: 16),

                        Expanded(
                          child: ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            row.name,
                                            style: theme.textTheme.titleSmall,
                                          ),
                                          Text(
                                            row.participant,
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      formatRupees(row.pricePaise),
                                      style: theme.textTheme.titleSmall,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),

                        _buildTotalRow(context, 'Subtotal', subtotal),
                        const SizedBox(height: 8),
                        _buildTotalRow(context, 'CGST (2.5%)', cgst),
                        const SizedBox(height: 8),
                        _buildTotalRow(context, 'SGST (2.5%)', sgst),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Grand Total',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              formatRupees(grandTotal),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/',
                      (route) => false,
                    );
                    ref.read(gatheringProvider.notifier).closeGathering();
                  },
                  child: const Text('Close Session'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTotalRow(BuildContext context, String label, int amountPaise) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        Text(formatRupees(amountPaise), style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

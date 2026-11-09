import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/gathering_controller.dart';
import '../../domain/bill.dart';
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

    final totals = BillTotals.of(gathering);
    final subtotal = totals.subtotalPaise;
    final cgst = totals.cgstPaise;
    final sgst = totals.sgstPaise;
    final grandTotal = totals.grandTotalPaise;

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
                  // One scrolling list, so on a short screen or with large
                  // text the totals scroll into view instead of being cut
                  // off.
                  child: ListView(
                    padding: const EdgeInsets.all(24.0),
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
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              const SizedBox(width: 12),
                              Text(
                                formatRupees(row.pricePaise),
                                style: theme.textTheme.titleSmall,
                              ),
                            ],
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              'Grand Total',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
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
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    // completeGathering() saves the gathering as
                    // completed (read-only, kept in history). Only once
                    // that save succeeds is the active gathering cleared,
                    // and the router's redirect sends navigation home. If
                    // it fails, the bill stays and the message offers
                    // "Try Again".
                    ref.read(gatheringProvider.notifier).completeGathering();
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
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        const SizedBox(width: 12),
        Text(formatRupees(amountPaise), style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

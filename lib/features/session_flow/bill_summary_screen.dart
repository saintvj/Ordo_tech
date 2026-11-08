import 'package:flutter/material.dart';
import '../../shared/models/models.dart';

class BillSummaryScreen extends StatelessWidget {
  final Session session;

  const BillSummaryScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Calculate totals
    double subtotal = 0;
    for (var order in session.orders) {
      subtotal += order.menuItem.price;
    }
    
    // Mock Taxes (2.5% each)
    double cgst = subtotal * 0.025;
    double sgst = subtotal * 0.025;
    double grandTotal = subtotal + cgst + sgst;

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
                          session.restaurantName,
                          style: theme.textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          session.gatheringName,
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        const Divider(),
                        const SizedBox(height: 16),
                        
                        Expanded(
                          child: ListView.builder(
                            itemCount: session.orders.length,
                            itemBuilder: (context, index) {
                              final order = session.orders[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            order.menuItem.name,
                                            style: theme.textTheme.titleSmall,
                                          ),
                                          Text(
                                            order.participant.name,
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '₹${order.menuItem.price.toStringAsFixed(2)}',
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
                              '₹${grandTotal.toStringAsFixed(2)}',
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
                    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
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

  Widget _buildTotalRow(BuildContext context, String label, double amount) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium,
        ),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

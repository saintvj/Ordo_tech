import 'package:flutter/material.dart';
import '../../shared/models/models.dart';

class SessionSummaryScreen extends StatelessWidget {
  final Session session;
  const SessionSummaryScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                itemCount: session.participants.length,
                itemBuilder: (context, index) {
                  final participant = session.participants[index];
                  final items = session.orders.where((oi) => oi.participant.id == participant.id).toList();
                  
                  if (items.isEmpty) return const SizedBox.shrink();

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
                        ...items.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item.menuItem.name,
                                style: theme.textTheme.bodyMedium,
                              ),
                              Icon(
                                item.isServed ? Icons.check_circle : Icons.cancel,
                                size: 16,
                                color: item.isServed ? theme.colorScheme.tertiary : theme.colorScheme.error,
                              ),
                            ],
                          ),
                        )),
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
                  )
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/bill_summary',
                      arguments: session,
                    );
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

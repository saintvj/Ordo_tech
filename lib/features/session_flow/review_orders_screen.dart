import 'package:flutter/material.dart';
import '../../shared/models/models.dart';

class ReviewOrdersScreen extends StatefulWidget {
  final Session session;
  const ReviewOrdersScreen({super.key, required this.session});

  @override
  State<ReviewOrdersScreen> createState() => _ReviewOrdersScreenState();
}

class _ReviewOrdersScreenState extends State<ReviewOrdersScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Group orders by participant
    Map<String, List<OrderItem>> itemsByParticipant = {};
    for (var order in widget.session.orders) {
      if (!itemsByParticipant.containsKey(order.participant.id)) {
        itemsByParticipant[order.participant.id] = [];
      }
      itemsByParticipant[order.participant.id]!.add(order);
    }
    
    return Scaffold(
      appBar: AppBar(title: const Text('Review Orders')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(24.0),
                itemCount: widget.session.participants.length,
                itemBuilder: (context, index) {
                  final participant = widget.session.participants[index];
                  final items = itemsByParticipant[participant.id] ?? [];
                  
                  if (items.isEmpty) return const SizedBox.shrink();

                  Map<String, int> itemCount = {};
                  Map<String, MenuItem> itemData = {};
                  double participantTotal = 0;
                  
                  for (var i in items) {
                    participantTotal += i.menuItem.price;
                    itemCount[i.menuItem.id] = (itemCount[i.menuItem.id] ?? 0) + 1;
                    itemData[i.menuItem.id] = i.menuItem;
                  }

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
                              '₹${participantTotal.toStringAsFixed(2)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...itemCount.keys.map((itemId) {
                          final item = itemData[itemId]!;
                          final count = itemCount[itemId]!;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${item.name} × $count',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                Text(
                                  '₹${(item.price * count).toStringAsFixed(2)}',
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
                                arguments: {
                                  'session': widget.session,
                                  'participant': participant,
                                  'isEditing': true,
                                },
                              ).then((_) {
                                setState(() {});
                              });
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
                  )
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pushReplacementNamed(
                      context,
                      '/waiter_mode',
                      arguments: widget.session,
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

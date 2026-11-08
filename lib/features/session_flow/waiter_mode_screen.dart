import 'package:flutter/material.dart';
import '../../shared/models/models.dart';

class WaiterModeScreen extends StatefulWidget {
  final Session session;
  const WaiterModeScreen({super.key, required this.session});

  @override
  State<WaiterModeScreen> createState() => _WaiterModeScreenState();
}

class _WaiterModeScreenState extends State<WaiterModeScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Group orders by MenuItem
    final Map<String, List<OrderItem>> itemsByMenu = {};
    for (var order in widget.session.orders) {
      if (!itemsByMenu.containsKey(order.menuItem.id)) {
        itemsByMenu[order.menuItem.id] = [];
      }
      itemsByMenu[order.menuItem.id]!.add(order);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Service'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pushNamed(
                context,
                '/session_summary',
                arguments: widget.session,
              );
            },
            child: const Text('Finish Service'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: itemsByMenu.values.map((orders) {
            final menuItem = orders.first.menuItem;
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
                  color: isComplete ? theme.colorScheme.tertiary.withOpacity(0.5) : theme.colorScheme.onSurface.withOpacity(0.05),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
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
                              menuItem.name,
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          Text(
                            '$servedCount / $totalCount Served',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: isComplete ? theme.colorScheme.tertiary : theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: totalCount == 0 ? 0 : servedCount / totalCount,
                          minHeight: 8,
                          backgroundColor: theme.colorScheme.onSurface.withOpacity(0.05),
                          color: isComplete ? theme.colorScheme.tertiary : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ...orders.map((order) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              setState(() {
                                order.isServed = !order.isServed;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: order.isServed ? theme.colorScheme.tertiary.withOpacity(0.1) : theme.colorScheme.background,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    order.participant.name,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      decoration: order.isServed ? TextDecoration.lineThrough : null,
                                      color: order.isServed ? theme.colorScheme.tertiary : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  Icon(
                                    order.isServed ? Icons.check_circle : Icons.radio_button_unchecked,
                                    color: order.isServed ? theme.colorScheme.tertiary : theme.colorScheme.onSurface.withOpacity(0.2),
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
    );
  }
}

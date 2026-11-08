import 'package:flutter/material.dart';
import '../../shared/models/models.dart';

class ParticipantOrderScreen extends StatefulWidget {
  final Session session;
  final Participant participant;
  final bool isEditing;
  
  const ParticipantOrderScreen({
    super.key,
    required this.session,
    required this.participant,
    this.isEditing = false,
  });

  @override
  State<ParticipantOrderScreen> createState() => _ParticipantOrderScreenState();
}

class _ParticipantOrderScreenState extends State<ParticipantOrderScreen> {
  late List<OrderItem> _localOrders;

  @override
  void initState() {
    super.initState();
    _localOrders = widget.session.orders
        .where((o) => o.participant.id == widget.participant.id)
        .toList();
  }

  void _addItem(MenuItem item) {
    setState(() {
      _localOrders.add(
        OrderItem(
          id: DateTime.now().toString(),
          participant: widget.participant,
          menuItem: item,
        ),
      );
    });
  }

  void _removeItem(MenuItem item) {
    setState(() {
      final index = _localOrders.lastIndexWhere(
        (o) => o.menuItem.id == item.id
      );
      if (index != -1) {
        _localOrders.removeAt(index);
      }
    });
  }

  void _saveAndContinue() {
    widget.session.orders.removeWhere((o) => o.participant.id == widget.participant.id);
    widget.session.orders.addAll(_localOrders);

    if (widget.isEditing) {
      Navigator.pop(context);
    } else {
      Navigator.pushNamed(
        context,
        '/pass_phone',
        arguments: widget.session,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    

    // Calculate participant total
    double currentTotal = 0;
    for (var order in _localOrders) {
      currentTotal += order.menuItem.price;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.participant.name}\'s Order'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                children: widget.session.menu.categories.map((category) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                        child: Text(
                          category.name.toUpperCase(),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      ...category.items.map((item) {
                        final count = _localOrders
                            .where((oi) => oi.menuItem.id == item.id)
                            .length;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.05)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '₹${item.price.toStringAsFixed(2)}',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: theme.colorScheme.secondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: count > 0 ? theme.colorScheme.primary.withOpacity(0.1) : theme.colorScheme.surface,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (count > 0) ...[
                                          IconButton(
                                            icon: Icon(Icons.remove, color: theme.colorScheme.primary),
                                            onPressed: () => _removeItem(item),
                                            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                                            padding: EdgeInsets.zero,
                                          ),
                                          SizedBox(
                                            width: 24,
                                            child: Text(
                                              '$count', 
                                              textAlign: TextAlign.center,
                                              style: theme.textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: theme.colorScheme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                        IconButton(
                                          icon: Icon(Icons.add, color: theme.colorScheme.primary),
                                          onPressed: () => _addItem(item),
                                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                                          padding: EdgeInsets.zero,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                    ],
                  );
                }).toList(),
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
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Your Total',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            '₹${currentTotal.toStringAsFixed(2)}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: currentTotal > 0 ? _saveAndContinue : null,
                      child: Text(widget.isEditing ? 'Save Changes' : 'Confirm Order'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

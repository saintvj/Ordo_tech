import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import '../../application/gathering_controller.dart';
import '../../domain/money.dart';
import '../../domain/models.dart';

/// Either a new participant (only a name, nothing stored yet) or an existing
/// participant whose order is being edited.
class ParticipantOrderArgs {
  const ParticipantOrderArgs.newParticipant(String this.name)
    : participantId = null;
  const ParticipantOrderArgs.edit(String this.participantId) : name = null;

  final String? name;
  final String? participantId;

  bool get isEditing => participantId != null;
}

class ParticipantOrderScreen extends ConsumerStatefulWidget {
  final ParticipantOrderArgs args;

  const ParticipantOrderScreen({super.key, required this.args});

  @override
  ConsumerState<ParticipantOrderScreen> createState() =>
      _ParticipantOrderScreenState();
}

class _ParticipantOrderScreenState
    extends ConsumerState<ParticipantOrderScreen> {
  /// Menu item id → quantity. Only committed on Confirm / Save.
  final Map<String, int> _quantities = {};

  @override
  void initState() {
    super.initState();
    final participantId = widget.args.participantId;
    final gathering = ref.read(gatheringProvider);
    if (participantId != null && gathering != null) {
      for (final line in gathering.linesFor(participantId)) {
        _quantities[line.menuItemId] =
            (_quantities[line.menuItemId] ?? 0) + line.quantity;
      }
    }
  }

  void _addItem(MenuItem item) {
    setState(() {
      _quantities[item.id] = (_quantities[item.id] ?? 0) + 1;
    });
  }

  void _removeItem(MenuItem item) {
    setState(() {
      final count = _quantities[item.id] ?? 0;
      if (count <= 1) {
        _quantities.remove(item.id);
      } else {
        _quantities[item.id] = count - 1;
      }
    });
  }

  void _saveAndContinue() {
    final notifier = ref.read(gatheringProvider.notifier);
    final participantId = widget.args.participantId;
    if (participantId != null) {
      // Reached by a push from Review Orders: pop back to it.
      notifier.replaceOrder(participantId, _quantities);
      context.pop();
    } else {
      // Reached by a go from Participant Name: continue the flow with go,
      // so this screen is replaced rather than left underneath Pass
      // Phone. See participant_name_screen.dart for the other half.
      notifier.addParticipantWithOrder(widget.args.name!, _quantities);
      context.go(Routes.passPhone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gathering = ref.watch(gatheringProvider);
    if (gathering == null) return const Scaffold();
    final isEditing = widget.args.isEditing;
    final participantName = isEditing
        ? gathering.findParticipant(widget.args.participantId!)?.name ?? ''
        : widget.args.name!;

    int currentTotal = 0;
    for (final MapEntry(key: itemId, value: count) in _quantities.entries) {
      currentTotal +=
          (gathering.menu.findItem(itemId)?.pricePaise ?? 0) * count;
    }

    // When ordering for a new participant, this screen is reached via go
    // (see participant_name_screen.dart), so there is nothing beneath it
    // to pop back to. When editing from Review Orders it is reached via
    // push, so popping (discarding the in-progress edit) is allowed.
    return PopScope(
      canPop: isEditing,
      child: Scaffold(
        appBar: AppBar(
          title: Text("$participantName's Order"),
          automaticallyImplyLeading: isEditing,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  children: gathering.menu.categories.map((category) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: 16.0,
                          ),
                          child: Text(
                            category.name.toUpperCase(),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        ...category.items.map((item) {
                          final count = _quantities[item.id] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 4.0,
                            ),
                            child: Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.05),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.name,
                                            style: theme.textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            formatRupees(item.pricePaise),
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .secondary,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: count > 0
                                            ? theme.colorScheme.primary
                                                  .withOpacity(0.1)
                                            : theme.colorScheme.surface,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: theme.colorScheme.onSurface
                                              .withOpacity(0.1),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (count > 0) ...[
                                            IconButton(
                                              icon: Icon(
                                                Icons.remove,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                              onPressed: () =>
                                                  _removeItem(item),
                                              constraints: const BoxConstraints(
                                                minWidth: 40,
                                                minHeight: 40,
                                              ),
                                              padding: EdgeInsets.zero,
                                            ),
                                            SizedBox(
                                              width: 24,
                                              child: Text(
                                                '$count',
                                                textAlign: TextAlign.center,
                                                style: theme
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: theme
                                                          .colorScheme
                                                          .primary,
                                                    ),
                                              ),
                                            ),
                                          ],
                                          IconButton(
                                            icon: Icon(
                                              Icons.add,
                                              color: theme.colorScheme.primary,
                                            ),
                                            onPressed: () => _addItem(item),
                                            constraints: const BoxConstraints(
                                              minWidth: 40,
                                              minHeight: 40,
                                            ),
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
                    ),
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
                              formatRupees(currentTotal),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: currentTotal > 0 || isEditing
                            ? _saveAndContinue
                            : null,
                        child: Text(
                          isEditing ? 'Save Changes' : 'Confirm Order',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

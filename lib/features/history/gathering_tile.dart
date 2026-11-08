import 'package:flutter/material.dart';
import '../../domain/models.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// e.g. `8 Nov 2026, 7:05 PM`.
String formatGatheringDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${local.day} ${_months[local.month - 1]} ${local.year}, '
      '$hour12:$minute $period';
}

/// What a gathering's status means to the user.
String statusLabel(GatheringStatus status) => switch (status) {
  GatheringStatus.menuDraft => 'Setting up menu',
  GatheringStatus.ordering => 'Ordering',
  GatheringStatus.serving => 'Serving',
  GatheringStatus.completed => 'Completed',
};

/// A gathering in a history or resume list.
class GatheringTile extends StatelessWidget {
  const GatheringTile({super.key, required this.summary, required this.onTap});

  final GatheringSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finished = summary.status.isFinished;
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summary.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      summary.restaurantName,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatGatheringDate(summary.createdAt),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Chip(
                label: Text(statusLabel(summary.status)),
                labelStyle: theme.textTheme.labelMedium?.copyWith(
                  color: finished
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.primary,
                ),
                side: BorderSide(
                  color: finished
                      ? theme.colorScheme.outlineVariant
                      : theme.colorScheme.primary,
                ),
                backgroundColor: theme.colorScheme.surface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

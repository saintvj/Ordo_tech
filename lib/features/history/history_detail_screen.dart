import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/gathering_controller.dart';
import '../../domain/bill.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import 'gathering_tile.dart';
import '../../shared/widgets/message_view.dart';

final _savedGatheringProvider = FutureProvider.autoDispose
    .family<Gathering?, String>(
      (ref, id) => ref.watch(gatheringRepositoryProvider).load(id),
    );

/// A completed gathering, read-only. It is loaded straight from storage and
/// never becomes the active gathering, so nothing here can change it.
class HistoryDetailScreen extends ConsumerWidget {
  const HistoryDetailScreen({super.key, required this.gatheringId});

  final String gatheringId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(_savedGatheringProvider(gatheringId));

    return Scaffold(
      appBar: AppBar(title: const Text('Past Gathering')),
      body: SafeArea(
        child: saved.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => MessageView(
            message: "This gathering couldn't be loaded.",
            actionLabel: 'Try Again',
            onAction: () =>
                ref.invalidate(_savedGatheringProvider(gatheringId)),
          ),
          data: (gathering) => gathering == null
              ? const MessageView(
                  message: 'This gathering is no longer saved on this phone.',
                )
              : _Bill(
                  gathering: gathering,
                  onTogglePaid: (participantId, paid) async {
                    await ref
                        .read(gatheringRepositoryProvider)
                        .updateSettlement(gathering.id, participantId, paid);
                    ref.invalidate(_savedGatheringProvider(gatheringId));
                  },
                ),
        ),
      ),
    );
  }
}

class _Bill extends StatelessWidget {
  const _Bill({required this.gathering, required this.onTogglePaid});

  final Gathering gathering;
  final Future<void> Function(String participantId, bool paid) onTogglePaid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = gathering.billConfig;
    final totals = GatheringBill.of(gathering, config);

    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        Card(
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
                const SizedBox(height: 4),
                Text(
                  '${formatGatheringDate(gathering.createdAt)} · '
                  'Hosted by ${gathering.hostName}',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const Divider(),
                for (final participant in gathering.participants) ...[
                  const SizedBox(height: 16),
                  _Row(
                    label: participant.name,
                    paise: gathering.subtotalFor(participant.id),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final line in gathering.linesFor(participant.id))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: _Row(
                        label: '${line.itemName} × ${line.quantity}',
                        paise: line.totalPaise,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                _Row(
                  label: 'Subtotal',
                  paise: totals.subtotalPaise,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                _Row(
                  label: 'CGST (${_pct(config.cgstBasisPoints)})',
                  paise: totals.cgstPaise,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                _Row(
                  label: 'SGST (${_pct(config.sgstBasisPoints)})',
                  paise: totals.sgstPaise,
                  style: theme.textTheme.bodyMedium,
                ),
                if (totals.serviceChargePaise > 0) ...[
                  const SizedBox(height: 8),
                  _Row(
                    label: 'Service (${_pct(config.serviceChargeBasisPoints)})',
                    paise: totals.serviceChargePaise,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                _Row(
                  label: 'Grand Total',
                  paise: totals.grandTotalPaise,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                _Settlement(
                  participants: gathering.participants,
                  paidIds: gathering.paidParticipantIds,
                  onToggle: onTogglePaid,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _pct(int basisPoints) {
    final value = basisPoints / 100;
    return value == value.roundToDouble() ? '${value.round()}%' : '$value%';
  }
}

/// Paid / pending tracker for a completed gathering. Toggling a participant
/// updates only the settlement record, through the narrow repository method.
class _Settlement extends StatelessWidget {
  const _Settlement({
    required this.participants,
    required this.paidIds,
    required this.onToggle,
  });

  final List<Participant> participants;
  final Set<String> paidIds;
  final Future<void> Function(String participantId, bool paid) onToggle;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Settlement',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        for (final p in participants)
          CheckboxListTile(
            key: Key('paid-${p.id}'),
            contentPadding: EdgeInsets.zero,
            value: paidIds.contains(p.id),
            title: Text(p.name),
            subtitle: Text(paidIds.contains(p.id) ? 'Paid' : 'Pending'),
            onChanged: (v) => onToggle(p.id, v ?? false),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.paise, this.style});

  final String label;
  final int paise;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Text(formatRupees(paise), style: style),
      ],
    );
  }
}

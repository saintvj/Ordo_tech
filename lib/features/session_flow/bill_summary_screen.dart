import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/gathering_controller.dart';
import '../../domain/bill.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import 'bill_export.dart';

class BillSummaryScreen extends ConsumerWidget {
  const BillSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gathering = ref.watch(gatheringProvider);
    if (gathering == null) return const Scaffold();

    final config = gathering.billConfig;
    final bill = GatheringBill.of(gathering, config);

    return Scaffold(
      appBar: AppBar(
        title: const Text('L\'Addition'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () => _editCharges(context, ref, gathering),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Charges'),
          ),
          PopupMenuButton<void>(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share bill',
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: () => shareBillText(gathering),
                child: const Text('Share as text'),
              ),
              PopupMenuItem(
                onTap: () => shareBillPdf(gathering),
                child: const Text('Share as PDF'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              _SplitToggle(
                method: config.splitMethod,
                onChanged: (m) => ref
                    .read(gatheringProvider.notifier)
                    .setBillConfig(config.copyWith(splitMethod: m)),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Card(
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
                      const SizedBox(height: 24),
                      for (final share in bill.shares) ...[
                        _ParticipantBlock(share: share, config: config),
                        const Divider(height: 32),
                      ],
                      _ChargeLine(label: 'Subtotal', paise: bill.subtotalPaise),
                      if (bill.discountPaise > 0)
                        _ChargeLine(
                          label: 'Discount',
                          paise: -bill.discountPaise,
                        ),
                      if (bill.cgstPaise > 0)
                        _ChargeLine(
                          label: config.taxInclusive
                              ? 'CGST (incl.)'
                              : 'CGST (${_pct(config.cgstBasisPoints)})',
                          paise: bill.cgstPaise,
                        ),
                      if (bill.sgstPaise > 0)
                        _ChargeLine(
                          label: config.taxInclusive
                              ? 'SGST (incl.)'
                              : 'SGST (${_pct(config.sgstBasisPoints)})',
                          paise: bill.sgstPaise,
                        ),
                      if (bill.serviceChargePaise > 0)
                        _ChargeLine(
                          label:
                              'Service (${_pct(config.serviceChargeBasisPoints)})',
                          paise: bill.serviceChargePaise,
                        ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Grand Total',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            formatRupees(bill.grandTotalPaise),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
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

  void _editCharges(BuildContext context, WidgetRef ref, Gathering gathering) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChargesSheet(
        initial: gathering.billConfig,
        onSave: (c) => ref.read(gatheringProvider.notifier).setBillConfig(c),
      ),
    );
  }

  static String _pct(int basisPoints) {
    final whole = basisPoints ~/ 100;
    final frac = basisPoints % 100;
    return frac == 0
        ? '$whole%'
        : '$whole.${frac.toString().padLeft(2, '0').replaceAll(RegExp(r'0$'), '')}%';
  }
}

class _SplitToggle extends StatelessWidget {
  const _SplitToggle({required this.method, required this.onChanged});

  final SplitMethod method;
  final ValueChanged<SplitMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<SplitMethod>(
      segments: const [
        ButtonSegment(
          value: SplitMethod.payAsYouEat,
          label: Text('Pay as you eat'),
          icon: Icon(Icons.person_outline),
        ),
        ButtonSegment(
          value: SplitMethod.splitEqually,
          label: Text('Split equally'),
          icon: Icon(Icons.groups_outlined),
        ),
      ],
      selected: {method},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _ParticipantBlock extends StatelessWidget {
  const _ParticipantBlock({required this.share, required this.config});

  final ParticipantShare share;
  final BillConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEqual = config.splitMethod == SplitMethod.splitEqually;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                share.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              formatRupees(share.totalPaise),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          isEqual
              ? 'Equal share of the bill'
              : 'Items ${formatRupees(share.subtotalPaise)}'
                    '${share.discountPaise > 0 ? ' − ${formatRupees(share.discountPaise)} off' : ''}'
                    '${_taxLabel()}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  String _taxLabel() {
    final tax = share.cgstPaise + share.sgstPaise + share.serviceChargePaise;
    if (config.taxInclusive || tax == 0) return '';
    return ' + ${formatRupees(tax)} charges';
  }
}

class _ChargeLine extends StatelessWidget {
  const _ChargeLine({required this.label, required this.paise});

  final String label;
  final int paise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            formatRupees(paise),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet to edit CGST/SGST/service rates, tax mode and flat discount.
class _ChargesSheet extends StatefulWidget {
  const _ChargesSheet({required this.initial, required this.onSave});

  final BillConfig initial;
  final ValueChanged<BillConfig> onSave;

  @override
  State<_ChargesSheet> createState() => _ChargesSheetState();
}

class _ChargesSheetState extends State<_ChargesSheet> {
  late final TextEditingController _cgst;
  late final TextEditingController _sgst;
  late final TextEditingController _service;
  late final TextEditingController _discount;
  late bool _taxInclusive;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cgst = TextEditingController(
      text: _bpText(widget.initial.cgstBasisPoints),
    );
    _sgst = TextEditingController(
      text: _bpText(widget.initial.sgstBasisPoints),
    );
    _service = TextEditingController(
      text: _bpText(widget.initial.serviceChargeBasisPoints),
    );
    _discount = TextEditingController(
      text: widget.initial.discountPaise == 0
          ? ''
          : rupeesInputText(widget.initial.discountPaise),
    );
    _taxInclusive = widget.initial.taxInclusive;
  }

  @override
  void dispose() {
    _cgst.dispose();
    _sgst.dispose();
    _service.dispose();
    _discount.dispose();
    super.dispose();
  }

  static String _bpText(int basisPoints) {
    if (basisPoints == 0) return '';
    final rupeesLike = basisPoints / 100; // percent value
    return rupeesLike == rupeesLike.roundToDouble()
        ? rupeesLike.round().toString()
        : rupeesLike.toString();
  }

  /// Parses a percent field such as `2.5` into basis points (250).
  int? _percentToBp(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 0;
    final value = double.tryParse(trimmed);
    if (value == null || value < 0) return null;
    return (value * 100).round();
  }

  void _save() {
    final cgst = _percentToBp(_cgst.text);
    final sgst = _percentToBp(_sgst.text);
    final service = _percentToBp(_service.text);
    if (cgst == null || sgst == null || service == null) {
      setState(() => _error = 'Rates must be zero or a positive percentage.');
      return;
    }
    final discountText = _discount.text.trim();
    final discount = discountText.isEmpty ? 0 : parseRupees(discountText);
    if (discount == null) {
      setState(() => _error = 'Discount must be a valid amount, or blank.');
      return;
    }
    widget.onSave(
      widget.initial.copyWith(
        cgstBasisPoints: cgst,
        sgstBasisPoints: sgst,
        serviceChargeBasisPoints: service,
        taxInclusive: _taxInclusive,
        discountPaise: discount,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Charges & Discount',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _percentField(_cgst, 'CGST %')),
              const SizedBox(width: 12),
              Expanded(child: _percentField(_sgst, 'SGST %')),
            ],
          ),
          const SizedBox(height: 12),
          _percentField(_service, 'Service charge %'),
          const SizedBox(height: 12),
          TextField(
            controller: _discount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Flat discount (₹)',
              hintText: 'Optional',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _taxInclusive,
            title: const Text('Prices already include tax'),
            onChanged: (v) => setState(() => _taxInclusive = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Apply')),
        ],
      ),
    );
  }

  Widget _percentField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(labelText: label, hintText: '0'),
    );
  }
}

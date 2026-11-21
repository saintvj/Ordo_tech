import 'bill.dart';
import 'models.dart';
import 'money.dart';

String _pct(int basisPoints) {
  final value = basisPoints / 100;
  return value == value.roundToDouble() ? '${value.round()}%' : '$value%';
}

String _date(DateTime utc) {
  final d = utc.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// Builds a plain-text bill suitable for sharing as a message. Pure and
/// deterministic, so it is fully unit-testable.
String formatBillText(Gathering gathering) {
  final config = gathering.billConfig;
  final bill = GatheringBill.of(gathering, config);
  final paid = gathering.paidParticipantIds;
  final buffer = StringBuffer()
    ..writeln(gathering.restaurantName)
    ..writeln(gathering.name)
    ..writeln('${_date(gathering.createdAt)} · Hosted by ${gathering.hostName}')
    ..writeln(
      config.splitMethod == SplitMethod.splitEqually
          ? 'Split equally'
          : 'Pay as you eat',
    )
    ..writeln('—————————————');

  for (final share in bill.shares) {
    final status = paid.contains(share.participantId) ? ' (paid)' : '';
    buffer.writeln('${share.name}$status');
    if (config.splitMethod == SplitMethod.payAsYouEat) {
      for (final line in gathering.linesFor(share.participantId)) {
        buffer.writeln(
          '  ${line.itemName} × ${line.quantity}'
          '  ${formatRupees(line.totalPaise)}',
        );
      }
    }
    buffer.writeln('  Total: ${formatRupees(share.totalPaise)}');
  }

  buffer
    ..writeln('—————————————')
    ..writeln('Subtotal: ${formatRupees(bill.subtotalPaise)}');
  if (bill.discountPaise > 0) {
    buffer.writeln('Discount: -${formatRupees(bill.discountPaise)}');
  }
  if (bill.cgstPaise > 0) {
    buffer.writeln(
      'CGST (${_pct(config.cgstBasisPoints)}): ${formatRupees(bill.cgstPaise)}',
    );
  }
  if (bill.sgstPaise > 0) {
    buffer.writeln(
      'SGST (${_pct(config.sgstBasisPoints)}): ${formatRupees(bill.sgstPaise)}',
    );
  }
  if (bill.serviceChargePaise > 0) {
    buffer.writeln(
      'Service (${_pct(config.serviceChargeBasisPoints)}): '
      '${formatRupees(bill.serviceChargePaise)}',
    );
  }
  buffer.write('Grand Total: ${formatRupees(bill.grandTotalPaise)}');
  return buffer.toString();
}

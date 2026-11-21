import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ordo/domain/models.dart';
import 'package:ordo/features/session_flow/bill_export.dart';

Gathering _gathering() => Gathering(
  id: 'g1',
  createdAt: DateTime.utc(2026, 11, 8),
  name: 'Brunch',
  restaurantName: 'MTR',
  hostName: 'Asha',
  status: GatheringStatus.completed,
  menu: const Menu(),
  participants: const [Participant(id: 'p1', name: 'Ravi')],
  orderLines: const [
    OrderLine(
      id: 'l1',
      participantId: 'p1',
      menuItemId: 'm1',
      itemName: 'Idli',
      unitPricePaise: 5000,
      quantity: 2,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildBillPdf produces a valid PDF document', () async {
    final bytes = await buildBillPdf(_gathering());
    expect(bytes.length, greaterThan(100));
    // A PDF file always starts with the "%PDF" magic bytes.
    expect(ascii.decode(bytes.sublist(0, 4)), '%PDF');
  });
}

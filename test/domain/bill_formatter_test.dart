import 'package:flutter_test/flutter_test.dart';
import 'package:ordo/domain/bill.dart';
import 'package:ordo/domain/bill_formatter.dart';
import 'package:ordo/domain/models.dart';

Gathering _gathering({
  BillConfig config = BillConfig.defaults,
  Set<String> paid = const {},
}) => Gathering(
  id: 'g1',
  createdAt: DateTime.utc(2026, 11, 8, 13, 5),
  name: 'Brunch',
  restaurantName: 'MTR',
  hostName: 'Asha',
  status: GatheringStatus.completed,
  menu: const Menu(),
  participants: const [
    Participant(id: 'p1', name: 'Ravi'),
    Participant(id: 'p2', name: 'Meera'),
  ],
  orderLines: const [
    OrderLine(
      id: 'l1',
      participantId: 'p1',
      menuItemId: 'm1',
      itemName: 'Idli',
      unitPricePaise: 5000,
      quantity: 2,
    ),
    OrderLine(
      id: 'l2',
      participantId: 'p2',
      menuItemId: 'm2',
      itemName: 'Dosa',
      unitPricePaise: 8000,
      quantity: 1,
    ),
  ],
  billConfig: config,
  paidParticipantIds: paid,
);

void main() {
  group('formatBillText', () {
    test('includes restaurant, gathering, host, participants and total', () {
      final text = formatBillText(_gathering());
      expect(text, contains('MTR'));
      expect(text, contains('Brunch'));
      expect(text, contains('Hosted by Asha'));
      expect(text, contains('8 Nov 2026'));
      expect(text, contains('Ravi'));
      expect(text, contains('Meera'));
      expect(text, contains('Idli × 2'));
      expect(text, contains('Grand Total:'));
      expect(text, contains('Pay as you eat'));
    });

    test('shows paid status and tax lines', () {
      final text = formatBillText(_gathering(paid: {'p1'}));
      expect(text, contains('Ravi (paid)'));
      expect(text, contains('Meera'));
      expect(text, contains('CGST (2.5%):'));
      expect(text, contains('SGST (2.5%):'));
    });

    test('equal split omits per-item lines and labels the method', () {
      final text = formatBillText(
        _gathering(
          config: const BillConfig(splitMethod: SplitMethod.splitEqually),
        ),
      );
      expect(text, contains('Split equally'));
      expect(text, isNot(contains('Idli × 2')));
    });
  });
}

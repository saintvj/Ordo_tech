import 'package:flutter_test/flutter_test.dart';
import 'package:ordo/domain/bill.dart';
import 'package:ordo/domain/models.dart';

/// Builds a gathering with the given participants, each mapped to a list of
/// (unitPricePaise, quantity) order lines.
Gathering _gathering(Map<String, List<(int, int)>> orders) {
  final participants = <Participant>[];
  final lines = <OrderLine>[];
  var lineCounter = 0;
  orders.forEach((pid, items) {
    participants.add(Participant(id: pid, name: pid.toUpperCase()));
    for (final (price, qty) in items) {
      lines.add(
        OrderLine(
          id: 'l${lineCounter++}',
          participantId: pid,
          menuItemId: 'm',
          itemName: 'Item',
          unitPricePaise: price,
          quantity: qty,
        ),
      );
    }
  });
  return Gathering(
    id: 'g1',
    createdAt: DateTime.utc(2026, 1, 1),
    name: 'Test',
    restaurantName: 'R',
    hostName: 'H',
    status: GatheringStatus.serving,
    menu: const Menu(),
    participants: participants,
    orderLines: lines,
  );
}

int _sumShares(GatheringBill bill) =>
    bill.shares.fold(0, (a, s) => a + s.totalPaise);

void main() {
  group('allocateProportionally', () {
    test('distributes exactly, largest remainder first', () {
      // 10 paise across weights 1,1,1 -> 4,3,3 (first gets the extra).
      expect(allocateProportionally(10, [1, 1, 1]), [4, 3, 3]);
    });

    test('sum always equals total for odd divisions', () {
      final out = allocateProportionally(100, [3, 5, 7]);
      expect(out.fold(0, (a, b) => a + b), 100);
    });

    test('spreads evenly when all weights are zero', () {
      expect(allocateProportionally(10, [0, 0, 0]), [4, 3, 3]);
    });

    test('empty weights give empty result', () {
      expect(allocateProportionally(10, []), isEmpty);
    });
  });

  group('pay-as-you-eat', () {
    test('each participant pays their own subtotal with no charges', () {
      final g = _gathering({
        'a': [(10000, 1)],
        'b': [(20000, 1)],
      });
      final bill = GatheringBill.of(
        g,
        const BillConfig(cgstBasisPoints: 0, sgstBasisPoints: 0),
      );
      expect(bill.subtotalPaise, 30000);
      expect(bill.grandTotalPaise, 30000);
      expect(bill.shares[0].totalPaise, 10000);
      expect(bill.shares[1].totalPaise, 20000);
      expect(_sumShares(bill), bill.grandTotalPaise);
    });

    test('proportional tax, shares sum exactly to grand total', () {
      final g = _gathering({
        'a': [(10000, 1)],
        'b': [(20000, 1)],
        'c': [(5000, 1)],
      });
      final bill = GatheringBill.of(g, BillConfig.defaults);
      expect(_sumShares(bill), bill.grandTotalPaise);
    });

    test('three uneven subtotals with odd grand total stay exact', () {
      final g = _gathering({
        'a': [(333, 1)],
        'b': [(777, 1)],
        'c': [(1111, 1)],
      });
      final bill = GatheringBill.of(
        g,
        const BillConfig(serviceChargeBasisPoints: 1000),
      );
      expect(_sumShares(bill), bill.grandTotalPaise);
    });

    test('service charge is applied', () {
      final g = _gathering({
        'a': [(10000, 1)],
      });
      final bill = GatheringBill.of(
        g,
        const BillConfig(
          cgstBasisPoints: 0,
          sgstBasisPoints: 0,
          serviceChargeBasisPoints: 1000, // 10%
        ),
      );
      expect(bill.serviceChargePaise, 1000);
      expect(bill.grandTotalPaise, 11000);
      expect(bill.shares.single.totalPaise, 11000);
    });
  });

  group('split equally', () {
    test('divides grand total equally, indivisible paise deterministic', () {
      final g = _gathering({
        'a': [(10000, 1)],
        'b': [(0 + 1, 1)], // tiny order
        'c': [(1, 1)],
      });
      // grand total is odd-ish; just assert exact division.
      final bill = GatheringBill.of(
        g,
        const BillConfig(splitMethod: SplitMethod.splitEqually),
      );
      expect(_sumShares(bill), bill.grandTotalPaise);
      // Difference between any two shares is at most 1 paisa.
      final totals = bill.shares.map((s) => s.totalPaise).toList();
      expect(
        totals.reduce((a, b) => a > b ? a : b) -
            totals.reduce((a, b) => a < b ? a : b),
        lessThanOrEqualTo(1),
      );
    });

    test('includes a participant who ordered nothing', () {
      final g = _gathering({
        'a': [(30000, 1)],
        'b': <(int, int)>[], // ordered nothing
      });
      final bill = GatheringBill.of(
        g,
        const BillConfig(
          cgstBasisPoints: 0,
          sgstBasisPoints: 0,
          splitMethod: SplitMethod.splitEqually,
        ),
      );
      expect(bill.shares.length, 2);
      expect(bill.shares[0].totalPaise, 15000);
      expect(bill.shares[1].totalPaise, 15000);
      expect(_sumShares(bill), bill.grandTotalPaise);
    });

    test('excludes a participant when the host says so', () {
      final g = _gathering({
        'a': [(30000, 1)],
        'b': <(int, int)>[],
      });
      final bill = GatheringBill.of(
        g,
        const BillConfig(
          cgstBasisPoints: 0,
          sgstBasisPoints: 0,
          splitMethod: SplitMethod.splitEqually,
          excludedParticipantIds: {'b'},
        ),
      );
      expect(bill.shares.length, 1);
      expect(bill.shares.single.participantId, 'a');
      expect(bill.shares.single.totalPaise, 30000);
    });
  });

  group('discounts', () {
    test('zero discount leaves subtotal untouched', () {
      final g = _gathering({
        'a': [(10000, 1)],
      });
      final bill = GatheringBill.of(
        g,
        const BillConfig(cgstBasisPoints: 0, sgstBasisPoints: 0),
      );
      expect(bill.discountPaise, 0);
      expect(bill.grandTotalPaise, 10000);
    });

    test('discount larger than subtotal floors the bill at zero', () {
      final g = _gathering({
        'a': [(10000, 1)],
      });
      final bill = GatheringBill.of(
        g,
        const BillConfig(
          cgstBasisPoints: 0,
          sgstBasisPoints: 0,
          discountPaise: 50000,
        ),
      );
      expect(bill.discountPaise, 10000);
      expect(bill.grandTotalPaise, 0);
      expect(_sumShares(bill), 0);
    });
  });

  group('tax inclusive vs exclusive', () {
    test('exclusive adds tax on top', () {
      final g = _gathering({
        'a': [(10000, 1)],
      });
      final bill = GatheringBill.of(g, BillConfig.defaults);
      expect(bill.cgstPaise, 250);
      expect(bill.sgstPaise, 250);
      expect(bill.grandTotalPaise, 10500);
    });

    test('inclusive carves tax out, grand total equals subtotal', () {
      final g = _gathering({
        'a': [(10500, 1)],
      });
      final bill = GatheringBill.of(g, const BillConfig(taxInclusive: true));
      // 10500 inclusive of 5% => net 10000, tax 500.
      expect(bill.grandTotalPaise, 10500);
      expect(bill.cgstPaise + bill.sgstPaise, 500);
      expect(_sumShares(bill), bill.grandTotalPaise);
    });
  });

  group('confirmed product requirements', () {
    test('discount allocation sums exactly to the configured discount', () {
      final g = _gathering({
        'a': [(333, 1)],
        'b': [(777, 1)],
        'c': [(1111, 1)],
      });
      final bill = GatheringBill.of(g, const BillConfig(discountPaise: 500));
      final allocated = bill.shares.fold(0, (a, s) => a + s.discountPaise);
      expect(allocated, bill.discountPaise);
      expect(bill.discountPaise, 500);
    });

    test('tax-inclusive reconciles with service charge enabled', () {
      final g = _gathering({
        'a': [(10500, 1)],
      });
      final bill = GatheringBill.of(
        g,
        const BillConfig(taxInclusive: true, serviceChargeBasisPoints: 1000),
      );
      // Net 10000 + tax 500 already in the 10500 subtotal; +10% service.
      expect(bill.serviceChargePaise, 1050);
      expect(bill.grandTotalPaise, 11550);
      expect(_sumShares(bill), bill.grandTotalPaise);
    });

    test('excluded participants leave the equal-split denominator', () {
      final g = _gathering({
        'a': [(30000, 1)],
        'b': <(int, int)>[],
        'c': <(int, int)>[],
      });
      final bill = GatheringBill.of(
        g,
        const BillConfig(
          cgstBasisPoints: 0,
          sgstBasisPoints: 0,
          splitMethod: SplitMethod.splitEqually,
          excludedParticipantIds: {'c'},
        ),
      );
      // Denominator is 2 (a and b), not 3.
      expect(bill.shares.length, 2);
      expect(bill.shares[0].totalPaise, 15000);
      expect(bill.shares[1].totalPaise, 15000);
    });

    test('zero-order participant: zero in PAYE, equal share in split', () {
      final g = _gathering({
        'a': [(30000, 1)],
        'b': <(int, int)>[],
      });
      final paye = GatheringBill.of(
        g,
        const BillConfig(cgstBasisPoints: 0, sgstBasisPoints: 0),
      );
      final bShareInPaye = paye.shares.firstWhere(
        (s) => s.participantId == 'b',
      );
      expect(bShareInPaye.totalPaise, 0);

      final equal = GatheringBill.of(
        g,
        const BillConfig(
          cgstBasisPoints: 0,
          sgstBasisPoints: 0,
          splitMethod: SplitMethod.splitEqually,
        ),
      );
      final bShareInEqual = equal.shares.firstWhere(
        (s) => s.participantId == 'b',
      );
      expect(bShareInEqual.totalPaise, 15000);
    });
  });

  group('validation', () {
    test('rejects negative rates', () {
      final g = _gathering({
        'a': [(100, 1)],
      });
      expect(
        () => GatheringBill.of(g, const BillConfig(cgstBasisPoints: -1)),
        throwsArgumentError,
      );
      expect(
        () => GatheringBill.of(g, const BillConfig(discountPaise: -1)),
        throwsArgumentError,
      );
    });
  });
}

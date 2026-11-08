import 'models.dart';
import 'money.dart';

/// Bill totals for a gathering, in paise.
///
/// Tax uses placeholder rates (2.5% CGST + 2.5% SGST) until the billing
/// engine in v0.5.
class BillTotals {
  const BillTotals._({
    required this.subtotalPaise,
    required this.cgstPaise,
    required this.sgstPaise,
  });

  factory BillTotals.of(Gathering gathering) {
    final subtotal = gathering.subtotalPaise;
    return BillTotals._(
      subtotalPaise: subtotal,
      cgstPaise: percentOf(subtotal, 250),
      sgstPaise: percentOf(subtotal, 250),
    );
  }

  final int subtotalPaise;
  final int cgstPaise;
  final int sgstPaise;

  int get grandTotalPaise => subtotalPaise + cgstPaise + sgstPaise;
}

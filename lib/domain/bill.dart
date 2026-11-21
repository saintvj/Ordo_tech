import 'models.dart';
import 'money.dart';

/// How a gathering's bill is divided among participants.
enum SplitMethod {
  /// Each participant pays for the items they ordered; shared charges and
  /// discount are allocated in proportion to their item subtotal.
  payAsYouEat,

  /// The final bill is divided equally among eligible participants,
  /// regardless of what each ordered.
  splitEqually,
}

/// Tax and charge configuration for a gathering's bill. All rates are in
/// basis points (1% = 100 bp); discount is a flat amount in paise.
///
/// The placeholder 2.5% + 2.5% GST from earlier stages is only the default;
/// the host can change every value.
class BillConfig {
  const BillConfig({
    this.cgstBasisPoints = 250,
    this.sgstBasisPoints = 250,
    this.serviceChargeBasisPoints = 0,
    this.taxInclusive = false,
    this.discountPaise = 0,
    this.splitMethod = SplitMethod.payAsYouEat,
    this.excludedParticipantIds = const {},
  });

  /// CGST rate in basis points (250 = 2.5%).
  final int cgstBasisPoints;

  /// SGST rate in basis points.
  final int sgstBasisPoints;

  /// Service charge rate in basis points (0 = none).
  final int serviceChargeBasisPoints;

  /// When true, menu prices already include CGST + SGST, so tax is
  /// back-calculated out of the subtotal rather than added on top. Service
  /// charge is still added on top either way.
  final bool taxInclusive;

  /// Flat discount off the subtotal, before tax, in paise.
  final int discountPaise;

  final SplitMethod splitMethod;

  /// Participants the host has excluded from an equal split. Ignored for
  /// pay-as-you-eat (there, a participant pays only for what they ordered).
  final Set<String> excludedParticipantIds;

  static const defaults = BillConfig();

  /// Throws [ArgumentError] if any value is out of range. Rates and discount
  /// must be non-negative; a discount larger than the subtotal is allowed
  /// and simply floors the bill at zero.
  void validate() {
    void nonNegative(int value, String name) {
      if (value < 0) throw ArgumentError.value(value, name, 'Must be >= 0');
    }

    nonNegative(cgstBasisPoints, 'cgstBasisPoints');
    nonNegative(sgstBasisPoints, 'sgstBasisPoints');
    nonNegative(serviceChargeBasisPoints, 'serviceChargeBasisPoints');
    nonNegative(discountPaise, 'discountPaise');
  }

  Map<String, dynamic> toJson() => {
    'cgstBp': cgstBasisPoints,
    'sgstBp': sgstBasisPoints,
    'serviceBp': serviceChargeBasisPoints,
    'taxInclusive': taxInclusive,
    'discountPaise': discountPaise,
    'split': splitMethod.name,
    'excluded': excludedParticipantIds.toList(),
  };

  /// Parses a stored config. Falls back to [defaults] for any missing or
  /// unrecognised field, so a config written by a newer app still loads.
  factory BillConfig.fromJson(Map<String, dynamic> json) {
    SplitMethod split = SplitMethod.payAsYouEat;
    final splitName = json['split'];
    if (splitName is String) {
      split = SplitMethod.values.firstWhere(
        (s) => s.name == splitName,
        orElse: () => SplitMethod.payAsYouEat,
      );
    }
    return BillConfig(
      cgstBasisPoints: (json['cgstBp'] as num?)?.toInt() ?? 250,
      sgstBasisPoints: (json['sgstBp'] as num?)?.toInt() ?? 250,
      serviceChargeBasisPoints: (json['serviceBp'] as num?)?.toInt() ?? 0,
      taxInclusive: json['taxInclusive'] as bool? ?? false,
      discountPaise: (json['discountPaise'] as num?)?.toInt() ?? 0,
      splitMethod: split,
      excludedParticipantIds: {
        for (final id in (json['excluded'] as List? ?? const []))
          if (id is String) id,
      },
    );
  }

  BillConfig copyWith({
    int? cgstBasisPoints,
    int? sgstBasisPoints,
    int? serviceChargeBasisPoints,
    bool? taxInclusive,
    int? discountPaise,
    SplitMethod? splitMethod,
    Set<String>? excludedParticipantIds,
  }) => BillConfig(
    cgstBasisPoints: cgstBasisPoints ?? this.cgstBasisPoints,
    sgstBasisPoints: sgstBasisPoints ?? this.sgstBasisPoints,
    serviceChargeBasisPoints:
        serviceChargeBasisPoints ?? this.serviceChargeBasisPoints,
    taxInclusive: taxInclusive ?? this.taxInclusive,
    discountPaise: discountPaise ?? this.discountPaise,
    splitMethod: splitMethod ?? this.splitMethod,
    excludedParticipantIds:
        excludedParticipantIds ?? this.excludedParticipantIds,
  );
}

/// What one participant owes, and the breakdown behind it.
class ParticipantShare {
  const ParticipantShare({
    required this.participantId,
    required this.name,
    required this.subtotalPaise,
    required this.discountPaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.serviceChargePaise,
    required this.totalPaise,
  });

  final String participantId;
  final String name;
  final int subtotalPaise;
  final int discountPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int serviceChargePaise;
  final int totalPaise;
}

/// A fully computed bill for a gathering under a [BillConfig].
///
/// Every amount is in integer paise. The per-participant [shares] always sum
/// exactly to [grandTotalPaise]; rounding leftovers are distributed with the
/// largest-remainder method so no paisa is lost or invented.
class GatheringBill {
  const GatheringBill._({
    required this.subtotalPaise,
    required this.discountPaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.serviceChargePaise,
    required this.grandTotalPaise,
    required this.shares,
  });

  final int subtotalPaise;

  /// Discount actually applied (never more than the subtotal).
  final int discountPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int serviceChargePaise;
  final int grandTotalPaise;
  final List<ParticipantShare> shares;

  factory GatheringBill.of(Gathering gathering, BillConfig config) {
    config.validate();

    final subtotal = gathering.subtotalPaise;
    final discount = config.discountPaise > subtotal
        ? subtotal
        : config.discountPaise;
    final discountedSubtotal = subtotal - discount;

    // Tax base and the net (ex-tax) subtotal differ only when prices are
    // tax-inclusive, where tax is carved out of the subtotal instead of
    // added on top.
    final int cgst;
    final int sgst;
    if (config.taxInclusive) {
      final totalTaxBp = config.cgstBasisPoints + config.sgstBasisPoints;
      // Tax already contained in the discounted subtotal:
      //   tax = subtotal - subtotal * 10000 / (10000 + rate)
      final net = (discountedSubtotal * 10000) ~/ (10000 + totalTaxBp);
      final impliedTax = discountedSubtotal - net;
      // Split the carved-out tax between CGST and SGST by their rates.
      cgst = totalTaxBp == 0
          ? 0
          : (impliedTax * config.cgstBasisPoints) ~/ totalTaxBp;
      sgst = impliedTax - cgst;
    } else {
      cgst = percentOf(discountedSubtotal, config.cgstBasisPoints);
      sgst = percentOf(discountedSubtotal, config.sgstBasisPoints);
    }

    final serviceCharge = percentOf(
      discountedSubtotal,
      config.serviceChargeBasisPoints,
    );

    // Service charge is always on top; tax is on top only when exclusive.
    final grandTotal = config.taxInclusive
        ? discountedSubtotal + serviceCharge
        : discountedSubtotal + cgst + sgst + serviceCharge;

    final shares = switch (config.splitMethod) {
      SplitMethod.payAsYouEat => _payAsYouEat(
        gathering,
        discount: discount,
        cgst: cgst,
        sgst: sgst,
        serviceCharge: serviceCharge,
        taxInclusive: config.taxInclusive,
      ),
      SplitMethod.splitEqually => _splitEqually(
        gathering,
        config,
        grandTotal: grandTotal,
      ),
    };

    return GatheringBill._(
      subtotalPaise: subtotal,
      discountPaise: discount,
      cgstPaise: cgst,
      sgstPaise: sgst,
      serviceChargePaise: serviceCharge,
      grandTotalPaise: grandTotal,
      shares: shares,
    );
  }
}

/// Allocates [total] across [weights] in proportion, with the leftover paise
/// from rounding handed to the largest fractional remainders first. The
/// returned amounts always sum exactly to [total]. If every weight is zero,
/// the total is spread as evenly as possible instead.
List<int> allocateProportionally(int total, List<int> weights) {
  final n = weights.length;
  if (n == 0) return const [];
  final weightSum = weights.fold(0, (a, b) => a + b);
  if (weightSum == 0) return _spreadEvenly(total, n);

  final base = List<int>.filled(n, 0);
  final remainders = <(int index, int remainder)>[];
  var allocated = 0;
  for (var i = 0; i < n; i++) {
    final numerator = total * weights[i];
    base[i] = numerator ~/ weightSum;
    remainders.add((i, numerator % weightSum));
    allocated += base[i];
  }

  var leftover = total - allocated;
  // Largest remainder first; ties broken by lower index for determinism.
  remainders.sort((a, b) {
    final byRemainder = b.$2.compareTo(a.$2);
    return byRemainder != 0 ? byRemainder : a.$1.compareTo(b.$1);
  });
  for (var k = 0; k < leftover; k++) {
    base[remainders[k % n].$1] += 1;
  }
  return base;
}

/// Spreads [total] across [n] slots as evenly as possible; the first
/// `total % n` slots get one extra paisa. Sum equals [total] exactly.
List<int> _spreadEvenly(int total, int n) {
  final base = total ~/ n;
  final extra = total % n;
  return [for (var i = 0; i < n; i++) base + (i < extra ? 1 : 0)];
}

List<ParticipantShare> _payAsYouEat(
  Gathering gathering, {
  required int discount,
  required int cgst,
  required int sgst,
  required int serviceCharge,
  required bool taxInclusive,
}) {
  final participants = gathering.participants;
  final weights = [for (final p in participants) gathering.subtotalFor(p.id)];

  final discountShares = allocateProportionally(discount, weights);
  final cgstShares = allocateProportionally(cgst, weights);
  final sgstShares = allocateProportionally(sgst, weights);
  final serviceShares = allocateProportionally(serviceCharge, weights);

  return [
    for (final (i, p) in participants.indexed)
      ParticipantShare(
        participantId: p.id,
        name: p.name,
        subtotalPaise: weights[i],
        discountPaise: discountShares[i],
        cgstPaise: cgstShares[i],
        sgstPaise: sgstShares[i],
        serviceChargePaise: serviceShares[i],
        // When prices are tax-inclusive the tax is already inside the
        // subtotal, so it is shown but not added on top again.
        totalPaise:
            weights[i] -
            discountShares[i] +
            (taxInclusive ? 0 : cgstShares[i] + sgstShares[i]) +
            serviceShares[i],
      ),
  ];
}

List<ParticipantShare> _splitEqually(
  Gathering gathering,
  BillConfig config, {
  required int grandTotal,
}) {
  final eligible = [
    for (final p in gathering.participants)
      if (!config.excludedParticipantIds.contains(p.id)) p,
  ];
  if (eligible.isEmpty) return const [];

  final totals = _spreadEvenly(grandTotal, eligible.length);
  return [
    for (final (i, p) in eligible.indexed)
      ParticipantShare(
        participantId: p.id,
        name: p.name,
        subtotalPaise: gathering.subtotalFor(p.id),
        // Charges aren't meaningfully per-participant in an equal split; the
        // breakdown is the gathering-level one. Only the total is divided.
        discountPaise: 0,
        cgstPaise: 0,
        sgstPaise: 0,
        serviceChargePaise: 0,
        totalPaise: totals[i],
      ),
  ];
}

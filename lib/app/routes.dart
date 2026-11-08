/// Route paths, named as constants so a typo is a compile error rather than
/// a silent "route not found" at runtime.
///
/// Each screen that needs typed arguments gets its own `*Args` class, passed
/// through go_router's `extra`, so no screen ever receives a raw `Map` or a
/// mutable domain object through navigation.
abstract final class Routes {
  static const home = '/';
  static const createGathering = '/create-gathering';
  static const menuSelection = '/menu-selection';
  static const editMenu = '/edit-menu';
  static const participantName = '/participant-name';
  static const participantOrder = '/participant-order';
  static const passPhone = '/pass-phone';
  static const reviewOrders = '/review-orders';
  static const waiterMode = '/waiter-mode';
  static const sessionSummary = '/session-summary';
  static const billSummary = '/bill-summary';
}

/// The three gathering details collected on [Routes.createGathering] and
/// used to start the gathering on [Routes.menuSelection].
class GatheringDetailsArgs {
  const GatheringDetailsArgs({
    required this.gatheringName,
    required this.restaurantName,
    required this.hostName,
  });

  final String gatheringName;
  final String restaurantName;
  final String hostName;
}

/// Route paths, named as constants so a typo is a compile error rather than
/// a silent "route not found" at runtime.
///
/// Each screen that needs arguments gets its own typed `*Args` class, carried
/// in the route's query string (see each class's `location` and `fromQuery`).
/// Unlike go_router's `extra`, the query survives rebuilds, and a route
/// opened without valid arguments is redirected rather than shown broken.
/// No screen receives a raw `Map` or a mutable domain object.
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
  static const history = '/history';
  static const historyDetail = '/history/:id';
  static const resume = '/resume';

  /// The read-only history page for one gathering.
  static String historyDetailFor(String gatheringId) =>
      '$history/${Uri.encodeComponent(gatheringId)}';
}

/// The three gathering details collected on [Routes.createGathering] and
/// used to start the gathering on [Routes.menuSelection].
class GatheringDetailsArgs {
  const GatheringDetailsArgs({
    required this.gatheringName,
    required this.restaurantName,
    required this.hostName,
  });

  /// The details from [query], or null if any is missing or blank.
  static GatheringDetailsArgs? fromQuery(Map<String, String> query) {
    final gathering = query['gathering']?.trim() ?? '';
    final restaurant = query['restaurant']?.trim() ?? '';
    final host = query['host']?.trim() ?? '';
    if (gathering.isEmpty || restaurant.isEmpty || host.isEmpty) return null;
    return GatheringDetailsArgs(
      gatheringName: gathering,
      restaurantName: restaurant,
      hostName: host,
    );
  }

  final String gatheringName;
  final String restaurantName;
  final String hostName;

  /// Where to navigate to show Menu Selection with these details.
  String get location => Uri(
    path: Routes.menuSelection,
    queryParameters: {
      'gathering': gatheringName,
      'restaurant': restaurantName,
      'host': hostName,
    },
  ).toString();
}

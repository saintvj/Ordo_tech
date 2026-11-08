import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/gathering_controller.dart';
import '../domain/models.dart';
import '../features/session_flow/bill_summary_screen.dart';
import '../features/session_flow/create_gathering_screen.dart';
import '../features/session_flow/edit_menu_screen.dart';
import '../features/session_flow/home_screen.dart';
import '../features/session_flow/menu_selection_screen.dart';
import '../features/session_flow/participant_name_screen.dart';
import '../features/session_flow/participant_order_screen.dart';
import '../features/session_flow/pass_phone_screen.dart';
import '../features/session_flow/review_orders_screen.dart';
import '../features/session_flow/session_summary_screen.dart';
import '../features/session_flow/waiter_mode_screen.dart';
import 'routes.dart';

/// Which screens a [GatheringStatus] allows, used by [_redirectForLifecycle].
///
/// `null` status (no active gathering) is handled separately: only
/// [Routes.home], [Routes.createGathering] and [Routes.menuSelection] are
/// reachable before a gathering exists.
const _menuDraftRoutes = {Routes.editMenu};
const _orderingRoutes = {
  Routes.participantName,
  Routes.participantOrder,
  Routes.passPhone,
  Routes.reviewOrders,
};
const _servingRoutes = {
  Routes.waiterMode,
  Routes.sessionSummary,
  Routes.billSummary,
};

/// The screen each stage should land on when a route doesn't belong to it.
const _entryPointForStatus = {
  GatheringStatus.menuDraft: Routes.editMenu,
  GatheringStatus.ordering: Routes.reviewOrders,
  GatheringStatus.serving: Routes.waiterMode,
};

/// Notifies go_router when the gathering's lifecycle status changes (or the
/// gathering starts or closes), so a change made by the controller - such as
/// `confirmMenu()` - re-evaluates [_redirectForLifecycle] immediately.
///
/// It deliberately ignores other changes (orders, served counts): the
/// redirect only depends on status, and refreshing the router on every edit
/// re-applies the current stack and can undo a pop that is in progress.
class _GatheringRouterRefresh extends ChangeNotifier {
  _GatheringRouterRefresh(Ref ref) {
    ref.listen(
      gatheringProvider.select((g) => g?.status),
      (previous, next) => notifyListeners(),
    );
  }
}

/// Builds the app's [GoRouter]. [ref] must be a ref that lives as long as
/// the app (see [routerProvider]), since [_redirectForLifecycle] reads
/// [gatheringProvider] on every navigation.
GoRouter buildRouter(Ref ref) {
  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: _GatheringRouterRefresh(ref),
    redirect: (context, state) =>
        _redirectForLifecycle(ref, state.matchedLocation),
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: Routes.createGathering,
        builder: (context, state) => const CreateGatheringScreen(),
      ),
      GoRoute(
        path: Routes.menuSelection,
        builder: (context, state) {
          // See the matching comment on Routes.participantOrder: extra
          // can be null on a rebuild of a route that is being navigated
          // away from.
          final details = state.extra;
          return details is GatheringDetailsArgs
              ? MenuSelectionScreen(details: details)
              : const Scaffold();
        },
      ),
      GoRoute(
        path: Routes.editMenu,
        builder: (context, state) => const EditMenuScreen(),
      ),
      GoRoute(
        path: Routes.participantName,
        builder: (context, state) => const ParticipantNameScreen(),
      ),
      GoRoute(
        path: Routes.participantOrder,
        builder: (context, state) {
          // `extra` is only guaranteed on the push/go that first opened
          // this route; a rebuild while it's being popped (e.g. triggered
          // by the refresh listener) can hand back a null extra. Fall
          // back to an empty screen rather than crash on the cast - this
          // page is on its way out regardless.
          final args = state.extra;
          return args is ParticipantOrderArgs
              ? ParticipantOrderScreen(args: args)
              : const Scaffold();
        },
      ),
      GoRoute(
        path: Routes.passPhone,
        builder: (context, state) => const PassPhoneScreen(),
      ),
      GoRoute(
        path: Routes.reviewOrders,
        builder: (context, state) => const ReviewOrdersScreen(),
      ),
      GoRoute(
        path: Routes.waiterMode,
        builder: (context, state) => const WaiterModeScreen(),
      ),
      GoRoute(
        path: Routes.sessionSummary,
        builder: (context, state) => const SessionSummaryScreen(),
      ),
      GoRoute(
        path: Routes.billSummary,
        builder: (context, state) => const BillSummaryScreen(),
      ),
    ],
  );
}

/// Enforces the gathering lifecycle: menuDraft → ordering → serving.
///
/// Returns the path to redirect to, or `null` to allow the navigation.
/// A route that doesn't belong to the gathering's current stage is bounced
/// to that stage's entry point rather than left reachable, so the host or a
/// participant can never, for example, reopen the menu editor once ordering
/// has started, or return to ordering once serving has started.
String? _redirectForLifecycle(Ref ref, String location) {
  final gathering = ref.read(gatheringProvider);

  if (gathering == null) {
    // No active gathering: only the pre-gathering screens are reachable.
    const allowed = {Routes.home, Routes.createGathering, Routes.menuSelection};
    return allowed.contains(location) ? null : Routes.home;
  }

  final status = gathering.status;

  // Once a gathering exists, the pre-gathering screens are no longer the
  // right place to be; send the user to where that stage actually starts.
  if (location == Routes.home ||
      location == Routes.createGathering ||
      location == Routes.menuSelection) {
    return _entryPointForStatus[status];
  }

  final belongsToStage = switch (status) {
    GatheringStatus.menuDraft => _menuDraftRoutes.contains(location),
    GatheringStatus.ordering => _orderingRoutes.contains(location),
    GatheringStatus.serving => _servingRoutes.contains(location),
  };

  return belongsToStage ? null : _entryPointForStatus[status];
}

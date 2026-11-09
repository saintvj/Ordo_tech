import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/gathering_controller.dart';
import '../domain/models.dart';
import '../features/history/history_detail_screen.dart';
import '../features/history/history_screen.dart';
import '../features/history/resume_screen.dart';
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

/// The screen a gathering should land on when the requested route doesn't
/// belong to its stage, e.g. when it is reopened after a restart.
///
/// While ordering, that is Participant Name until someone has ordered, then
/// Pass Phone, which offers both "Next Person" and "Finish Ordering". (Review
/// Orders would be a dead end there: nothing beneath it to add people from.)
String _entryPointFor(Gathering gathering) => switch (gathering.status) {
  GatheringStatus.menuDraft => Routes.editMenu,
  GatheringStatus.ordering =>
    gathering.participants.isEmpty ? Routes.participantName : Routes.passPhone,
  GatheringStatus.serving => Routes.waiterMode,
  // Never active (completeGathering clears it); treated like no gathering.
  GatheringStatus.completed => Routes.home,
};

/// Where navigation starts. `main.dart` overrides it from the saved state
/// (see loadStartupState).
final initialLocationProvider = Provider<String>((ref) => Routes.home);

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
    initialLocation: ref.read(initialLocationProvider),
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
        // Without the gathering details there is nothing to start; ask for
        // them again.
        redirect: (context, state) =>
            GatheringDetailsArgs.fromQuery(state.uri.queryParameters) == null
            ? Routes.createGathering
            : null,
        builder: (context, state) => MenuSelectionScreen(
          details: GatheringDetailsArgs.fromQuery(state.uri.queryParameters)!,
        ),
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
        redirect: (context, state) =>
            _participantOrderRedirect(ref, state.uri.queryParameters),
        builder: (context, state) => ParticipantOrderScreen(
          args: ParticipantOrderArgs.fromQuery(state.uri.queryParameters)!,
        ),
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
      GoRoute(
        path: Routes.history,
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: Routes.historyDetail,
        builder: (context, state) =>
            HistoryDetailScreen(gatheringId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.resume,
        builder: (context, state) => const ResumeScreen(),
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

  if (gathering == null || gathering.status.isFinished) {
    // No active gathering: only the pre-gathering screens, session history
    // and the resume picker are reachable.
    const allowed = {
      Routes.home,
      Routes.createGathering,
      Routes.menuSelection,
      Routes.history,
      Routes.resume,
    };
    final isHistoryDetail = location.startsWith('${Routes.history}/');
    return allowed.contains(location) || isHistoryDetail ? null : Routes.home;
  }

  final belongsToStage = switch (gathering.status) {
    GatheringStatus.menuDraft => _menuDraftRoutes.contains(location),
    GatheringStatus.ordering => _orderingRoutes.contains(location),
    GatheringStatus.serving => _servingRoutes.contains(location),
    GatheringStatus.completed => false,
  };

  // Everything else - including Home, history and the pre-gathering
  // screens - goes to where the active gathering's stage starts.
  return belongsToStage ? null : _entryPointFor(gathering);
}

/// The order screen needs either a new participant's name or an existing
/// participant of the active gathering. Otherwise, send the user to where
/// they can carry on: entering a name, or the orders they were reviewing.
String? _participantOrderRedirect(Ref ref, Map<String, String> query) {
  final args = ParticipantOrderArgs.fromQuery(query);
  if (args == null) return Routes.participantName;
  final participantId = args.participantId;
  if (participantId != null &&
      ref.read(gatheringProvider)?.findParticipant(participantId) == null) {
    return Routes.reviewOrders;
  }
  return null;
}

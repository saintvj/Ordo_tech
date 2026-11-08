import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ordo/app/app.dart';
import 'package:ordo/app/routes.dart';
import 'package:ordo/application/gathering_controller.dart';
import 'package:ordo/domain/temporary_menu.dart';

/// These tests drive the router through [ProviderScope]/[OrdoApp] rather
/// than calling [buildRouter] directly, so they exercise exactly what a
/// user's navigation (or the controller's lifecycle changes) actually
/// produce, including the `redirect` callback and the back stack.
///
/// The router is read from [routerProvider] on the test's own
/// [ProviderContainer] rather than via `GoRouter.of(context)`, which is
/// more robust across rebuilds triggered by `redirect` and by the
/// gathering's lifecycle changes.
void main() {
  late ProviderContainer container;

  Future<void> pumpApp(WidgetTester tester) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const OrdoApp()),
    );
    await tester.pumpAndSettle();
  }

  /// The currently displayed route, i.e. the top of the stack. `.uri`
  /// alone reflects the *first* match, which is wrong whenever something
  /// has been pushed on top (e.g. editing from Review Orders), so this
  /// reads the last match's location instead.
  String currentLocation(WidgetTester tester) {
    final router = container.read(routerProvider);
    final matches = router.routerDelegate.currentConfiguration.matches;
    return matches.last.matchedLocation;
  }

  /// Drives the full host journey up to Review Orders with one confirmed
  /// participant ("Ravi", 1 Idli), using go_router directly so these tests
  /// don't depend on tapping through every screen.
  Future<void> advanceToReviewOrders(WidgetTester tester) async {
    final router = container.read(routerProvider);
    final notifier = container.read(gatheringProvider.notifier);

    notifier.startGathering(
      name: 'Brunch',
      restaurantName: 'MTR',
      hostName: 'Asha',
      menu: temporaryMenu,
    );
    router.go(Routes.editMenu);
    await tester.pumpAndSettle();

    notifier.confirmMenu();
    router.go(Routes.participantName);
    await tester.pumpAndSettle();

    notifier.addParticipantWithOrder('Ravi', {'m1': 1});
    router.go(Routes.passPhone);
    await tester.pumpAndSettle();

    router.go(Routes.reviewOrders);
    await tester.pumpAndSettle();
  }

  group('menu editing to ordering transition', () {
    testWidgets('editMenu is reachable in menuDraft', (tester) async {
      await pumpApp(tester);
      container
          .read(gatheringProvider.notifier)
          .startGathering(
            name: 'Brunch',
            restaurantName: 'MTR',
            hostName: 'Asha',
            menu: temporaryMenu,
          );
      container.read(routerProvider).go(Routes.editMenu);
      await tester.pumpAndSettle();

      expect(currentLocation(tester), Routes.editMenu);
    });

    testWidgets(
      'confirming the menu redirects away from editMenu into ordering',
      (tester) async {
        await pumpApp(tester);
        final notifier = container.read(gatheringProvider.notifier);
        notifier.startGathering(
          name: 'Brunch',
          restaurantName: 'MTR',
          hostName: 'Asha',
          menu: temporaryMenu,
        );
        final router = container.read(routerProvider);
        router.go(Routes.editMenu);
        await tester.pumpAndSettle();

        // confirmMenu() alone (no navigation call) must be enough: the
        // refresh listener re-runs the redirect and bounces editMenu.
        notifier.confirmMenu();
        await tester.pumpAndSettle();

        expect(currentLocation(tester), isNot(Routes.editMenu));
        expect(currentLocation(tester), Routes.reviewOrders);
      },
    );

    testWidgets('B1/B2: editMenu is refused once ordering has started', (
      tester,
    ) async {
      await pumpApp(tester);
      final notifier = container.read(gatheringProvider.notifier);
      notifier.startGathering(
        name: 'Brunch',
        restaurantName: 'MTR',
        hostName: 'Asha',
        menu: temporaryMenu,
      );
      notifier.confirmMenu();
      final router = container.read(routerProvider);

      // A direct attempt to navigate to editMenu must be redirected away,
      // not merely discouraged by the UI.
      router.go(Routes.editMenu);
      await tester.pumpAndSettle();

      expect(currentLocation(tester), isNot(Routes.editMenu));
    });
  });

  group('ordering to serving transition', () {
    testWidgets('reviewOrders is reachable while ordering', (tester) async {
      await pumpApp(tester);
      await advanceToReviewOrders(tester);

      expect(currentLocation(tester), Routes.reviewOrders);
    });

    testWidgets('starting service redirects away from ordering into serving', (
      tester,
    ) async {
      await pumpApp(tester);
      await advanceToReviewOrders(tester);

      // startServing() alone must trigger the redirect, exactly like
      // confirmMenu() above.
      container.read(gatheringProvider.notifier).startServing();
      await tester.pumpAndSettle();

      expect(currentLocation(tester), Routes.waiterMode);
    });

    testWidgets('B4: ordering routes are refused once serving has started', (
      tester,
    ) async {
      await pumpApp(tester);
      await advanceToReviewOrders(tester);
      container.read(gatheringProvider.notifier).startServing();
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);

      for (final blocked in [
        Routes.editMenu,
        Routes.participantName,
        Routes.participantOrder,
        Routes.passPhone,
        Routes.reviewOrders,
      ]) {
        router.go(blocked);
        await tester.pumpAndSettle();
        expect(
          currentLocation(tester),
          Routes.waiterMode,
          reason: '$blocked must redirect to waiterMode once serving',
        );
      }
    });

    testWidgets('serving cannot return to ordering: repeated back presses from '
        'Waiter Mode stay on Waiter Mode', (tester) async {
      await pumpApp(tester);
      await advanceToReviewOrders(tester);
      container.read(gatheringProvider.notifier).startServing();
      await tester.pumpAndSettle();

      expect(currentLocation(tester), Routes.waiterMode);

      for (var i = 0; i < 5; i++) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(currentLocation(tester), Routes.waiterMode);
      }
    });
  });

  group('back navigation during participant ordering', () {
    testWidgets(
      'back stack does not grow across many participants (go, not push)',
      (tester) async {
        await pumpApp(tester);
        final notifier = container.read(gatheringProvider.notifier);
        notifier.startGathering(
          name: 'Brunch',
          restaurantName: 'MTR',
          hostName: 'Asha',
          menu: temporaryMenu,
        );
        notifier.confirmMenu();
        final router = container.read(routerProvider);

        router.go(Routes.participantName);
        await tester.pumpAndSettle();

        // Simulate 10 participants taking their turn.
        for (var i = 0; i < 10; i++) {
          notifier.addParticipantWithOrder('Guest $i', {'m1': 1});
          router.go(Routes.passPhone);
          await tester.pumpAndSettle();
          router.go(Routes.participantName);
          await tester.pumpAndSettle();
        }

        // The stack must stay at one entry regardless of how many
        // participants have gone through the cycle.
        final delegate = router.routerDelegate;
        expect(delegate.currentConfiguration.matches, hasLength(1));
        expect(container.read(gatheringProvider)!.participants, hasLength(10));
      },
    );

    testWidgets(
      'back navigation does not create duplicate participants or orders',
      (tester) async {
        await pumpApp(tester);
        final notifier = container.read(gatheringProvider.notifier);
        notifier.startGathering(
          name: 'Brunch',
          restaurantName: 'MTR',
          hostName: 'Asha',
          menu: temporaryMenu,
        );
        notifier.confirmMenu();
        final router = container.read(routerProvider);
        router.go(Routes.participantName);
        await tester.pumpAndSettle();

        // Repeated system-back presses on Participant Name (reached via
        // go, so there is nothing beneath it) must not pop the app out of
        // the ordering stage or duplicate anything, since no participant
        // has been confirmed yet.
        for (var i = 0; i < 3; i++) {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        }
        expect(currentLocation(tester), Routes.participantName);
        expect(container.read(gatheringProvider)!.participants, isEmpty);

        notifier.addParticipantWithOrder('Ravi', {'m1': 1});
        router.go(Routes.passPhone);
        await tester.pumpAndSettle();

        // Repeated back presses from Pass Phone (also reached via go)
        // must not re-add Ravi or go anywhere but stay put.
        for (var i = 0; i < 3; i++) {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        }
        expect(currentLocation(tester), Routes.passPhone);
        expect(container.read(gatheringProvider)!.participants, hasLength(1));
      },
    );
  });

  group('back navigation from Waiter Mode', () {
    testWidgets('system back does not leave Waiter Mode', (tester) async {
      await pumpApp(tester);
      await advanceToReviewOrders(tester);
      container.read(gatheringProvider.notifier).startServing();
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(currentLocation(tester), Routes.waiterMode);
    });
  });

  group('host can review and edit before starting service', () {
    testWidgets('editing from Review Orders returns to Review Orders', (
      tester,
    ) async {
      await pumpApp(tester);
      await advanceToReviewOrders(tester);

      await tester.ensureVisible(find.text('Edit'));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(currentLocation(tester), Routes.participantOrder);
      expect(find.byType(BackButton), findsOneWidget);

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(currentLocation(tester), Routes.reviewOrders);
    });

    testWidgets('back from Review Orders allows adding a late participant', (
      tester,
    ) async {
      await pumpApp(tester);
      final notifier = container.read(gatheringProvider.notifier);
      notifier.startGathering(
        name: 'Brunch',
        restaurantName: 'MTR',
        hostName: 'Asha',
        menu: temporaryMenu,
      );
      notifier.confirmMenu();
      notifier.addParticipantWithOrder('Ravi', {'m1': 1});
      container.read(routerProvider).go(Routes.passPhone);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Finish Ordering'));
      await tester.pumpAndSettle();
      expect(currentLocation(tester), Routes.reviewOrders);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(currentLocation(tester), Routes.passPhone);

      await tester.tap(find.text('Next Person'));
      await tester.pumpAndSettle();
      expect(currentLocation(tester), Routes.participantName);
      expect(
        container
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .matches,
        hasLength(1),
      );
    });
  });

  group('full pass-and-play journey', () {
    testWidgets('home through to bill summary via taps', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await pumpApp(tester);

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap(find.text('Start a Session'));
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Brunch');
      await tester.enterText(fields.at(1), 'MTR');
      await tester.enterText(fields.at(2), 'Asha');
      await tap(find.text('Continue'));
      await tap(find.text('Use Temporary Menu'));
      expect(currentLocation(tester), Routes.editMenu);

      await tap(find.text('Confirm Menu'));
      expect(currentLocation(tester), Routes.participantName);
      expect(find.byType(BackButton), findsNothing);

      await tester.enterText(find.byType(TextField), 'Ravi');
      await tap(find.text('Continue to Menu'));
      await tap(find.byIcon(Icons.add).first);
      await tap(find.text('Confirm Order'));
      expect(currentLocation(tester), Routes.passPhone);

      await tap(find.text('Finish Ordering'));
      expect(currentLocation(tester), Routes.reviewOrders);

      await tap(find.text('Start Waiter Mode'));
      expect(currentLocation(tester), Routes.waiterMode);

      await tap(find.text('Ravi').first);
      await tap(find.text('Finish Service'));
      expect(currentLocation(tester), Routes.sessionSummary);

      await tap(find.text('View Bill'));
      expect(currentLocation(tester), Routes.billSummary);

      await tap(find.text('Close Session'));
      expect(currentLocation(tester), Routes.home);
      expect(find.text('Start a Session'), findsOneWidget);
    });
  });
}

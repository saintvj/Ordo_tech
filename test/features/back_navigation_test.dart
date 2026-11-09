import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ordo/app/app.dart';
import 'package:ordo/app/router.dart';
import 'package:ordo/app/routes.dart';
import 'package:ordo/application/gathering_controller.dart';
import 'package:ordo/application/startup.dart';
import 'package:ordo/data/gathering_repository.dart';
import 'package:ordo/domain/models.dart';
import 'package:ordo/domain/temporary_menu.dart';

/// Android system back across the gathering lifecycle. Back may only move
/// within the current stage, and never drops unsaved work without asking.
void main() {
  late InMemoryGatheringRepository repository;
  late ProviderContainer container;

  setUp(() => repository = InMemoryGatheringRepository());

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final startup = await loadStartupState(repository);
    container = ProviderContainer(
      overrides: [
        gatheringRepositoryProvider.overrideWithValue(repository),
        initialLocationProvider.overrideWithValue(startup.initialLocation),
      ],
    );
    addTearDown(container.dispose);
    if (startup.resumeGathering case final g?) {
      container.read(gatheringProvider.notifier).restore(g);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const OrdoApp()),
    );
    await tester.pumpAndSettle();
  }

  String location() => container
      .read(routerProvider)
      .routerDelegate
      .currentConfiguration
      .matches
      .last
      .matchedLocation;

  Gathering? gathering() => container.read(gatheringProvider);

  Future<void> back(WidgetTester tester, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Saves a gathering in [status] with Ravi ordering 2 Idli.
  Future<Gathering> seed(GatheringStatus status) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final g = c.read(gatheringProvider.notifier)
      ..startGathering(
        name: 'Brunch',
        restaurantName: 'MTR',
        hostName: 'Asha',
        menu: temporaryMenu,
      );
    if (status.index >= GatheringStatus.ordering.index) {
      g
        ..confirmMenu()
        ..addParticipantWithOrder('Ravi', {'m1': 2});
    }
    if (status.index >= GatheringStatus.serving.index) g.startServing();
    final saved = c.read(gatheringProvider)!;
    await repository.save(saved);
    return saved;
  }

  group('editing an order from Review Orders', () {
    Future<void> openEdit(WidgetTester tester) async {
      await seed(GatheringStatus.ordering);
      await launch(tester); // reopens on Pass Phone
      await tap(tester, find.text('Finish Ordering'));
      await tap(tester, find.text('Edit'));
      expect(location(), Routes.participantOrder);
    }

    testWidgets('back with no changes returns straight to Review', (
      tester,
    ) async {
      await openEdit(tester);
      await back(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(location(), Routes.reviewOrders);
    });

    testWidgets('back with changes asks; Keep Editing keeps them', (
      tester,
    ) async {
      await openEdit(tester);
      await tap(tester, find.byIcon(Icons.add).first); // 3 Idli
      await back(tester);

      expect(find.text('Discard your changes?'), findsOneWidget);
      await tap(tester, find.text('Keep Editing'));
      expect(location(), Routes.participantOrder);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('Discard returns to Review with the order unchanged', (
      tester,
    ) async {
      await openEdit(tester);
      await tap(tester, find.byIcon(Icons.add).first);
      await back(tester);
      await tap(tester, find.text('Discard'));

      expect(location(), Routes.reviewOrders);
      expect(find.text('Idli × 2'), findsOneWidget);
      expect(gathering()!.orderLines.single.quantity, 2);
    });

    testWidgets('the app bar back arrow asks the same way', (tester) async {
      await openEdit(tester);
      await tap(tester, find.byIcon(Icons.add).first);
      await tap(tester, find.byType(BackButton));
      expect(find.text('Discard your changes?'), findsOneWidget);
    });
  });

  group('a new participant ordering', () {
    Future<void> startOrdering(WidgetTester tester) async {
      await seed(GatheringStatus.ordering);
      await launch(tester);
      await tap(tester, find.text('Next Person'));
      await tester.enterText(find.byType(TextField), 'Meera');
      await tap(tester, find.text('Continue to Menu'));
      expect(location(), Routes.participantOrder);
    }

    testWidgets('back with nothing picked returns to Participant Name', (
      tester,
    ) async {
      await startOrdering(tester);
      await back(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(location(), Routes.participantName);
      expect(gathering()!.participants.map((p) => p.name), ['Ravi']);
    });

    testWidgets('back with dishes picked asks; Discard adds no one', (
      tester,
    ) async {
      await startOrdering(tester);
      await tap(tester, find.byIcon(Icons.add).first);
      await back(tester);

      expect(find.text('Discard this order?'), findsOneWidget);
      await tap(tester, find.text('Discard'));
      expect(location(), Routes.participantName);
      expect(gathering()!.participants.map((p) => p.name), ['Ravi']);
      expect(gathering()!.orderLines, hasLength(1));
    });

    testWidgets('repeated back never duplicates a participant', (tester) async {
      await startOrdering(tester);
      await back(tester, times: 4); // order -> name, then blocked
      expect(location(), Routes.participantName);
      expect(gathering()!.participants, hasLength(1));
    });
  });

  group('creating a gathering', () {
    testWidgets('back from an empty form returns Home', (tester) async {
      await launch(tester);
      await tap(tester, find.text('Start a Session'));
      await back(tester);
      expect(location(), Routes.home);
    });

    testWidgets('back after typing asks before dropping the details', (
      tester,
    ) async {
      await launch(tester);
      await tap(tester, find.text('Start a Session'));
      await tester.enterText(find.byType(TextFormField).first, 'Brunch');
      await back(tester);

      expect(find.text('Discard these details?'), findsOneWidget);
      await tap(tester, find.text('Keep Editing'));
      expect(location(), Routes.createGathering);
      expect(find.text('Brunch'), findsOneWidget);

      await back(tester);
      await tap(tester, find.text('Discard'));
      expect(location(), Routes.home);
      expect(gathering(), isNull);
    });
  });

  group('serving', () {
    testWidgets('back from the bill steps back to Waiter Mode and stops', (
      tester,
    ) async {
      await seed(GatheringStatus.serving);
      await launch(tester);
      await tap(tester, find.text('Finish Service'));
      await tap(tester, find.text('View Bill'));
      expect(location(), Routes.billSummary);

      await back(tester);
      expect(location(), Routes.sessionSummary);
      await back(tester);
      expect(location(), Routes.waiterMode);
      await back(tester, times: 5);
      expect(location(), Routes.waiterMode);
      expect(gathering()!.status, GatheringStatus.serving);
    });
  });

  group('after start-up recovery', () {
    for (final (status, screen) in [
      (GatheringStatus.menuDraft, Routes.editMenu),
      (GatheringStatus.ordering, Routes.passPhone),
      (GatheringStatus.serving, Routes.waiterMode),
    ]) {
      testWidgets('back on a reopened ${status.name} gathering stays in its '
          'stage', (tester) async {
        final saved = await seed(status);
        await launch(tester);
        expect(location(), screen);
        await back(tester, times: 3);
        // Either still there, or (Edit Menu, the stage's only screen)
        // the app was asked to close - never a screen of another stage.
        expect(location(), screen);
        expect(gathering()!.id, saved.id);
        expect(gathering()!.status, status);
      });
    }

    testWidgets('back on the resume picker opens nothing', (tester) async {
      await seed(GatheringStatus.ordering);
      await seed(GatheringStatus.serving);
      await launch(tester);
      expect(location(), Routes.resume);
      await back(tester, times: 2);
      expect(location(), Routes.resume);
      expect(gathering(), isNull);
    });

    testWidgets('history steps back to Home', (tester) async {
      await launch(tester);
      await tap(tester, find.text('Past Gatherings'));
      await back(tester);
      expect(location(), Routes.home);
    });
  });
}

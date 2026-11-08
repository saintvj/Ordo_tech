import 'dart:async';

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

/// UI-level recovery and history tests. Storage itself is covered against a
/// real database in test/data and test/application; these use the
/// in-memory repository so they can focus on what the user sees.
void main() {
  late InMemoryGatheringRepository repository;
  late List<String> unreadableIds;
  late ProviderContainer container;

  setUp(() {
    unreadableIds = [];
    repository = _TestRepository(() => unreadableIds);
  });

  /// Starts the app the way main.dart does: run the start-up check, then
  /// restore the gathering it found (if any).
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
    final resumed = startup.resumeGathering;
    if (resumed != null) {
      container.read(gatheringProvider.notifier).restore(resumed);
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

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Saves a gathering built through the real controller, in [status].
  Future<Gathering> seed(
    GatheringStatus status, {
    String name = 'Brunch',
    DateTime? createdAt,
  }) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final g = c.read(gatheringProvider.notifier);
    g.startGathering(
      name: name,
      restaurantName: 'MTR',
      hostName: 'Asha',
      menu: temporaryMenu,
    );
    if (status.index >= GatheringStatus.ordering.index) {
      g.confirmMenu();
      g.addParticipantWithOrder('Ravi', {'m1': 2});
    }
    if (status.index >= GatheringStatus.serving.index) {
      g.startServing();
      final line = c.read(gatheringProvider)!.orderLines.single;
      g.setServedQuantity(line.id, 1);
    }
    var gathering = c.read(gatheringProvider)!;
    if (status == GatheringStatus.completed) {
      gathering = gathering.copyWith(status: GatheringStatus.completed);
    }
    if (createdAt != null) {
      gathering = Gathering(
        id: gathering.id,
        createdAt: createdAt,
        name: gathering.name,
        restaurantName: gathering.restaurantName,
        hostName: gathering.hostName,
        status: gathering.status,
        menu: gathering.menu,
        participants: gathering.participants,
        orderLines: gathering.orderLines,
      );
    }
    await repository.save(gathering);
    return gathering;
  }

  group('resuming after a restart', () {
    testWidgets('menu editing resumes on Edit Menu', (tester) async {
      await seed(GatheringStatus.menuDraft);
      await launch(tester);
      expect(location(), Routes.editMenu);
    });

    testWidgets('ordering resumes on Pass Phone with both choices', (
      tester,
    ) async {
      await seed(GatheringStatus.ordering);
      await launch(tester);
      expect(location(), Routes.passPhone);

      await tap(tester, find.text('Finish Ordering'));
      expect(find.text('Idli × 2'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(tester, find.text('Next Person'));
      expect(location(), Routes.participantName);
    });

    testWidgets('serving resumes on Waiter Mode with progress', (tester) async {
      await seed(GatheringStatus.serving);
      await launch(tester);
      expect(location(), Routes.waiterMode);
      expect(find.text('1 / 2 Served'), findsOneWidget);
    });

    testWidgets('several unfinished: the user picks one', (tester) async {
      await seed(
        GatheringStatus.ordering,
        name: 'Lunch',
        createdAt: DateTime(2026, 11, 1, 13),
      );
      await seed(
        GatheringStatus.serving,
        name: 'Dinner',
        createdAt: DateTime(2026, 11, 1, 20),
      );
      await launch(tester);

      expect(location(), Routes.resume);
      expect(container.read(gatheringProvider), isNull);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Dinner'), findsOneWidget);

      await tap(tester, find.text('Dinner'));
      expect(location(), Routes.waiterMode);
      expect(container.read(gatheringProvider)!.name, 'Dinner');
    });

    testWidgets('"Not Now" goes Home without opening anything', (tester) async {
      await seed(GatheringStatus.ordering, name: 'Lunch');
      await seed(GatheringStatus.ordering, name: 'Dinner');
      await launch(tester);

      await tap(tester, find.text('Not Now'));
      expect(location(), Routes.home);
      expect(container.read(gatheringProvider), isNull);
    });
  });

  group('session history', () {
    testWidgets('lists gatherings with restaurant, date and status', (
      tester,
    ) async {
      await seed(
        GatheringStatus.completed,
        name: 'Lunch',
        createdAt: DateTime(2026, 11, 1, 13, 5),
      );
      await launch(tester);

      await tap(tester, find.text('Past Gatherings'));
      expect(location(), Routes.history);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('MTR'), findsOneWidget);
      expect(find.text('1 Nov 2026, 1:05 PM'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('a completed gathering opens read-only', (tester) async {
      final done = await seed(GatheringStatus.completed);
      await launch(tester);
      await tap(tester, find.text('Past Gatherings'));

      await tap(tester, find.text('Brunch'));
      expect(location(), Routes.historyDetailFor(done.id));
      expect(find.text('Idli × 2'), findsOneWidget);
      expect(find.text('₹105.00'), findsOneWidget); // 100 + 2.5% + 2.5%
      // Nothing on the page can change it.
      for (final label in ['Edit', 'Save Changes', 'Confirm Order']) {
        expect(find.text(label), findsNothing);
      }
      expect(find.byType(FilledButton), findsNothing);
      expect(container.read(gatheringProvider), isNull);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(location(), Routes.history);
    });

    testWidgets('an unfinished gathering resumes from history', (tester) async {
      await seed(GatheringStatus.completed, name: 'Lunch');
      await launch(tester); // only a completed one: starts at Home
      await seed(GatheringStatus.serving, name: 'Dinner');

      await tap(tester, find.text('Past Gatherings'));
      await tap(tester, find.text('Dinner'));
      expect(location(), Routes.waiterMode);
      expect(container.read(gatheringProvider)!.name, 'Dinner');
    });

    testWidgets('history is not reachable while a gathering is active', (
      tester,
    ) async {
      await seed(GatheringStatus.ordering);
      await launch(tester);
      container.read(routerProvider).go(Routes.history);
      await tester.pumpAndSettle();
      expect(location(), Routes.passPhone);
    });

    testWidgets('fix 2: skipped gatherings are mentioned in history', (
      tester,
    ) async {
      await seed(GatheringStatus.completed, name: 'Lunch');
      unreadableIds = ['damaged'];
      await launch(tester);

      await tap(tester, find.text('Past Gatherings'));
      expect(find.text('Lunch'), findsOneWidget);
      expect(
        find.text("1 saved gathering couldn't be read and isn't shown."),
        findsOneWidget,
      );
    });

    testWidgets('fix 6: a double tap resumes once, with no false error', (
      tester,
    ) async {
      final slow = _SlowTestRepository();
      repository = slow;
      await launch(tester);
      await seed(GatheringStatus.serving, name: 'Dinner');
      await tap(tester, find.text('Past Gatherings'));

      await tester.tap(find.text('Dinner'));
      await tester.tap(find.text('Dinner'));
      await tester.pump();
      slow.gate.complete();
      await tester.pumpAndSettle();

      expect(location(), Routes.waiterMode);
      expect(find.textContaining("couldn't be opened"), findsNothing);
      expect(slow.loads, 1);
    });

    testWidgets('fix 3: a failed Close Session stays on the bill', (
      tester,
    ) async {
      final failing = _FailOnCompleteTestRepository();
      repository = failing;
      await seed(GatheringStatus.serving);
      await launch(tester);
      await tap(tester, find.text('Finish Service'));
      await tap(tester, find.text('View Bill'));

      await tap(tester, find.text('Close Session'));
      expect(location(), Routes.billSummary);
      expect(container.read(gatheringProvider), isNotNull);
      expect(
        find.textContaining("couldn't finish this gathering"),
        findsOneWidget,
      );

      failing.failCompletion = false;
      await tap(tester, find.text('Try Again'));
      expect(location(), Routes.home);
      expect(container.read(gatheringProvider), isNull);
    });

    testWidgets('closing the bill puts the gathering in history', (
      tester,
    ) async {
      await seed(GatheringStatus.serving);
      await launch(tester);

      await tap(tester, find.text('Finish Service'));
      await tap(tester, find.text('View Bill'));
      await tap(tester, find.text('Close Session'));
      await container.read(gatheringProvider.notifier).flushSaves();
      expect(location(), Routes.home);

      await tap(tester, find.text('Past Gatherings'));
      expect(find.text('Completed'), findsOneWidget);
    });
  });
}

/// In-memory storage whose listings also report [unreadableIds], to show
/// how the screens present skipped gatherings.
class _TestRepository extends InMemoryGatheringRepository {
  _TestRepository(this.unreadableIds);

  final List<String> Function() unreadableIds;

  @override
  Future<GatheringList> listAll() async => GatheringList(
    (await super.listAll()).gatherings,
    unreadableIds: unreadableIds(),
  );
}

class _SlowTestRepository extends InMemoryGatheringRepository {
  final gate = Completer<void>();
  int loads = 0;

  @override
  Future<Gathering?> load(String id) async {
    loads++;
    await gate.future;
    return super.load(id);
  }
}

class _FailOnCompleteTestRepository extends InMemoryGatheringRepository {
  bool failCompletion = true;

  @override
  Future<void> save(Gathering gathering) async {
    if (failCompletion && gathering.status.isFinished) {
      throw const GatheringStorageException('disk full');
    }
    return super.save(gathering);
  }
}

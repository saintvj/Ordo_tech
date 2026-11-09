import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ordo/app/app.dart';
import 'package:ordo/app/router.dart';
import 'package:ordo/app/routes.dart';
import 'package:ordo/application/gathering_controller.dart';
import 'package:ordo/application/startup.dart';
import 'package:ordo/data/gathering_repository.dart';
import 'package:ordo/data/local/app_database.dart';
import 'package:ordo/data/local/local_gathering_repository.dart';
import 'package:ordo/domain/models.dart';
import 'package:ordo/domain/temporary_menu.dart';

/// Builds a gathering through the real controller and returns it in
/// [status] (completed is the serving gathering marked completed).
Gathering buildGathering(GatheringStatus status, {String name = 'Brunch'}) {
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
  if (status.index >= GatheringStatus.serving.index) g.startServing();
  final gathering = c.read(gatheringProvider)!;
  return status == GatheringStatus.completed
      ? gathering.copyWith(status: GatheringStatus.completed)
      : gathering;
}

void main() {
  group('repository delete (real database, reopened)', () {
    late Directory dir;
    late File file;
    final dbs = <AppDatabase>[];

    LocalGatheringRepository connect() {
      final db = AppDatabase(NativeDatabase(file));
      dbs.add(db);
      return LocalGatheringRepository(db);
    }

    Future<LocalGatheringRepository> reconnect() async {
      for (final db in dbs) {
        await db.close();
      }
      dbs.clear();
      return connect();
    }

    Future<int> count(String table) async {
      final row = await dbs.last
          .customSelect('SELECT COUNT(*) AS n FROM $table')
          .getSingle();
      return row.read<int>('n');
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ordo_discard_test');
      file = File('${dir.path}/ordo.sqlite');
    });

    tearDown(() async {
      for (final db in dbs) {
        await db.close();
      }
      dbs.clear();
      await dir.delete(recursive: true);
    });

    test('removes only that gathering and all of its rows', () async {
      var repo = connect();
      final doomed = buildGathering(GatheringStatus.serving, name: 'Doomed');
      final kept = buildGathering(GatheringStatus.ordering, name: 'Kept');
      final history = buildGathering(GatheringStatus.completed, name: 'Old');
      for (final g in [doomed, kept, history]) {
        await repo.save(g);
      }

      await repo.delete(doomed.id);
      repo = await reconnect();

      expect(await repo.load(doomed.id), isNull);
      expect((await repo.load(kept.id))!.orderLines, hasLength(1));
      expect((await repo.load(history.id))!.status, GatheringStatus.completed);
      // Each remaining gathering has its own 2 categories, 7 items,
      // 1 participant and 1 line; nothing of the deleted one is left.
      expect(await count('gatherings'), 2);
      expect(await count('menu_categories'), 4);
      expect(await count('menu_items'), 14);
      expect(await count('participants'), 2);
      expect(await count('order_lines'), 2);
    });

    test('refuses to delete a completed gathering', () async {
      var repo = connect();
      final history = buildGathering(GatheringStatus.completed);
      await repo.save(history);

      await expectLater(
        repo.delete(history.id),
        throwsA(isA<ReadOnlyGatheringException>()),
      );
      repo = await reconnect();
      expect((await repo.load(history.id))!.orderLines, hasLength(1));
    });

    test('deleting something already gone is not an error', () async {
      await connect().delete('never-saved');
    });

    test('queued saves cannot bring a discarded gathering back', () async {
      final repo = connect();
      final c = ProviderContainer(
        overrides: [gatheringRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      final g = c.read(gatheringProvider.notifier);
      // Several changes, none flushed before the discard.
      g.startGathering(
        name: 'Brunch',
        restaurantName: 'MTR',
        hostName: 'Asha',
        menu: temporaryMenu,
      );
      final id = c.read(gatheringProvider)!.id;
      g.confirmMenu();
      g.addParticipantWithOrder('Ravi', {'m1': 1});

      expect(await g.discardGathering(), isTrue);
      await g.flushSaves();
      final reopened = await reconnect();
      expect(await reopened.load(id), isNull);
      expect((await reopened.listAll()).gatherings, isEmpty);
    });

    test('start-up does not reopen a discarded gathering', () async {
      final repo = connect();
      final discarded = buildGathering(GatheringStatus.serving, name: 'Gone');
      await repo.save(discarded);
      await repo.save(buildGathering(GatheringStatus.completed, name: 'Old'));
      await repo.delete(discarded.id);

      final startup = await loadStartupState(await reconnect());
      expect(startup.resumeGathering, isNull);
      expect(startup.initialLocation, Routes.home);
    });
  });

  group('controller discard', () {
    ProviderContainer containerWith(GatheringRepository repo) {
      final c = ProviderContainer(
        overrides: [gatheringRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a failed delete keeps the gathering and offers Try Again', () async {
      final repo = _FailingDeleteRepository();
      final gathering = buildGathering(GatheringStatus.ordering);
      await repo.save(gathering);
      final c = containerWith(repo);
      c.read(gatheringProvider.notifier).restore(gathering);

      expect(
        await c.read(gatheringProvider.notifier).discardGathering(),
        isFalse,
      );
      expect(c.read(gatheringProvider)!.id, gathering.id);
      expect(await repo.load(gathering.id), isNotNull);
      final issue = c.read(storageIssueProvider)!;
      expect(issue.message, contains("couldn't discard"));
      expect(issue.actionLabel, 'Try Again');

      repo.fail = false;
      issue.onAction!();
      await c.read(gatheringProvider.notifier).flushSaves();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(gatheringProvider), isNull);
      expect(await repo.load(gathering.id), isNull);
    });

    test('a second request while discarding joins the first', () async {
      final repo = _SlowDeleteRepository();
      final gathering = buildGathering(GatheringStatus.ordering);
      await repo.save(gathering);
      final c = containerWith(repo);
      final g = c.read(gatheringProvider.notifier)..restore(gathering);

      final first = g.discardGathering();
      final second = g.discardGathering();
      repo.gate.complete();
      expect(await Future.wait([first, second]), [true, true]);
      expect(repo.deletes, 1);
      expect(c.read(storageIssueProvider), isNull);
    });
  });

  group('Discard Gathering on screen', () {
    late InMemoryGatheringRepository repository;
    late ProviderContainer container;

    Future<void> launch(WidgetTester tester) async {
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

    Future<void> openDiscardDialog(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard Gathering'));
      await tester.pumpAndSettle();
    }

    setUp(() => repository = InMemoryGatheringRepository());

    for (final (status, screen) in [
      (GatheringStatus.menuDraft, Routes.editMenu),
      (GatheringStatus.ordering, Routes.passPhone),
      (GatheringStatus.serving, Routes.waiterMode),
    ]) {
      testWidgets('is offered on ${screen.substring(1)}', (tester) async {
        await repository.save(buildGathering(status));
        await launch(tester);
        expect(location(), screen);
        await openDiscardDialog(tester);
        expect(find.text('Discard this gathering?'), findsOneWidget);
      });
    }

    testWidgets('Cancel leaves everything unchanged', (tester) async {
      final gathering = buildGathering(GatheringStatus.serving);
      await repository.save(gathering);
      await launch(tester);

      await openDiscardDialog(tester);
      expect(find.textContaining('permanently deleted'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(location(), Routes.waiterMode);
      expect(container.read(gatheringProvider)!.id, gathering.id);
      expect(await repository.load(gathering.id), isNotNull);
    });

    testWidgets('Discard deletes it, keeps history, and goes Home', (
      tester,
    ) async {
      final gathering = buildGathering(GatheringStatus.ordering);
      final history = buildGathering(GatheringStatus.completed, name: 'Old');
      await repository.save(gathering);
      await repository.save(history);
      await launch(tester);

      await openDiscardDialog(tester);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(location(), Routes.home);
      expect(container.read(gatheringProvider), isNull);
      expect(await repository.load(gathering.id), isNull);
      expect((await repository.load(history.id))!.status, isNotNull);

      await tester.tap(find.text('Past Gatherings'));
      await tester.pumpAndSettle();
      expect(find.text('Old'), findsOneWidget);
      expect(find.text('Brunch'), findsNothing);
    });

    testWidgets('a failed discard stays put and explains', (tester) async {
      final failing = _FailingDeleteRepository();
      repository = failing;
      final gathering = buildGathering(GatheringStatus.serving);
      await repository.save(gathering);
      await launch(tester);

      await openDiscardDialog(tester);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(location(), Routes.waiterMode);
      expect(container.read(gatheringProvider), isNotNull);
      expect(find.textContaining("couldn't discard"), findsOneWidget);

      failing.fail = false;
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(location(), Routes.home);
    });
  });
}

class _FailingDeleteRepository extends InMemoryGatheringRepository {
  bool fail = true;

  @override
  Future<void> delete(String id) async {
    if (fail) throw const GatheringStorageException('disk full');
    return super.delete(id);
  }
}

class _SlowDeleteRepository extends InMemoryGatheringRepository {
  final gate = Completer<void>();
  int deletes = 0;

  @override
  Future<void> delete(String id) async {
    deletes++;
    await gate.future;
    return super.delete(id);
  }
}

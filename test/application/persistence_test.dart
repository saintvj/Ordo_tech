import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ordo/app/routes.dart';
import 'package:ordo/application/gathering_controller.dart';
import 'package:ordo/application/startup.dart';
import 'package:ordo/data/gathering_repository.dart';
import 'package:ordo/data/local/app_database.dart';
import 'package:ordo/data/local/local_gathering_repository.dart';
import 'package:ordo/domain/models.dart';
import 'package:ordo/domain/temporary_menu.dart';

void main() {
  late Directory dir;
  late File dbFile;
  final openDbs = <AppDatabase>[];

  LocalGatheringRepository connect() {
    final db = AppDatabase(NativeDatabase(dbFile));
    openDbs.add(db);
    return LocalGatheringRepository(db);
  }

  /// Reads through a separate connection to the same file, then closes it,
  /// so the result can only come from what was written to disk.
  Future<Gathering?> readFromDisk(String id) async {
    final db = AppDatabase(NativeDatabase(dbFile));
    try {
      return await LocalGatheringRepository(db).load(id);
    } finally {
      await db.close();
    }
  }

  ProviderContainer containerWith(GatheringRepository repository) {
    final c = ProviderContainer(
      overrides: [gatheringRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ordo_persist_test');
    dbFile = File('${dir.path}/ordo.sqlite');
  });

  tearDown(() async {
    for (final db in openDbs) {
      await db.close();
    }
    openDbs.clear();
    await dir.delete(recursive: true);
  });

  group('automatic saving', () {
    test('every lifecycle step is on disk as soon as it is flushed', () async {
      final c = containerWith(connect());
      final controller = c.read(gatheringProvider.notifier);
      Future<Gathering> saved() async {
        await controller.flushSaves();
        return (await readFromDisk(c.read(gatheringProvider)!.id))!;
      }

      controller.startGathering(
        name: 'Brunch',
        restaurantName: 'MTR',
        hostName: 'Asha',
        menu: temporaryMenu,
      );
      expect((await saved()).status, GatheringStatus.menuDraft);

      controller.updateItem('c1', 'm1', name: 'Ghee Idli', pricePaise: 7000);
      expect((await saved()).menu.findItem('m1')!.name, 'Ghee Idli');

      controller.confirmMenu();
      expect((await saved()).status, GatheringStatus.ordering);

      final ravi = controller.addParticipantWithOrder('Ravi', {'m1': 1});
      expect((await saved()).participants.single.name, 'Ravi');

      controller.replaceOrder(ravi, {'m1': 3});
      expect((await saved()).orderLines.single.quantity, 3);

      controller.startServing();
      expect((await saved()).status, GatheringStatus.serving);

      final line = c.read(gatheringProvider)!.orderLines.single;
      controller.setServedQuantity(line.id, 2);
      expect((await saved()).orderLines.single.servedQuantity, 2);
      expect((await saved()).orderLines.single.unitPricePaise, 7000);
    });

    test('completing saves the gathering as completed and clears it', () async {
      final c = containerWith(connect());
      final controller = c.read(gatheringProvider.notifier);
      controller.startGathering(
        name: 'Brunch',
        restaurantName: 'MTR',
        hostName: 'Asha',
        menu: temporaryMenu,
      );
      final id = c.read(gatheringProvider)!.id;
      controller.confirmMenu();
      controller.addParticipantWithOrder('Ravi', {'m1': 1});
      controller.startServing();

      expect(await controller.completeGathering(), isTrue);

      expect(c.read(gatheringProvider), isNull);
      final stored = (await readFromDisk(id))!;
      expect(stored.status, GatheringStatus.completed);
      expect(stored.orderLines, hasLength(1));
    });

    test('a failed save is reported to the user, not swallowed', () async {
      final c = containerWith(_FailingRepository());
      c
          .read(gatheringProvider.notifier)
          .startGathering(
            name: 'Brunch',
            restaurantName: 'MTR',
            hostName: 'Asha',
          );
      await c.read(gatheringProvider.notifier).flushSaves();

      expect(c.read(storageIssueProvider)!.message, contains("couldn't save"));
      // The in-memory state is kept, so the user can carry on.
      expect(c.read(gatheringProvider), isNotNull);
    });
  });

  group('fix 3: completing when the save fails', () {
    test('keeps the gathering active, explains, and can be retried', () async {
      final repo = _FailOnCompleteRepository();
      final c = containerWith(repo);
      final controller = c.read(gatheringProvider.notifier);
      controller.startGathering(
        name: 'Brunch',
        restaurantName: 'MTR',
        hostName: 'Asha',
        menu: temporaryMenu,
      );
      controller.confirmMenu();
      controller.addParticipantWithOrder('Ravi', {'m1': 1});
      controller.startServing();
      final serving = c.read(gatheringProvider)!;

      expect(await controller.completeGathering(), isFalse);
      expect(c.read(gatheringProvider), same(serving));
      final issue = c.read(storageIssueProvider)!;
      expect(issue.message, contains("couldn't finish"));
      expect(issue.actionLabel, 'Try Again');
      expect((await repo.load(serving.id))!.status, GatheringStatus.serving);

      // Retry through the message's action, as the user would.
      repo.failCompletion = false;
      issue.onAction!();
      await controller.flushSaves();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(gatheringProvider), isNull);
      expect((await repo.load(serving.id))!.status, GatheringStatus.completed);
    });

    test('a repeated tap while completing is harmless', () async {
      final repo = InMemoryGatheringRepository();
      final c = containerWith(repo);
      final controller = c.read(gatheringProvider.notifier);
      controller.startGathering(
        name: 'Brunch',
        restaurantName: 'MTR',
        hostName: 'Asha',
        menu: temporaryMenu,
      );
      controller.confirmMenu();
      controller.addParticipantWithOrder('Ravi', {'m1': 1});
      controller.startServing();

      final results = await Future.wait([
        controller.completeGathering(),
        controller.completeGathering(),
      ]);
      expect(results, [true, true]);
      expect(c.read(gatheringProvider), isNull);
      expect(c.read(storageIssueProvider), isNull);
    });
  });

  group('fix 6: overlapping resume requests', () {
    test('a second request while loading joins the first', () async {
      final repo = _SlowRepository();
      final saved = _gatheringIn(GatheringStatus.serving);
      await repo.save(saved);
      final c = containerWith(repo);
      final controller = c.read(gatheringProvider.notifier);

      final first = controller.resume(saved.id);
      final second = controller.resume(saved.id);
      repo.gate.complete();
      await Future.wait([first, second]); // neither throws

      expect(repo.loads, 1);
      expect(c.read(gatheringProvider)!.id, saved.id);
    });

    test(
      'resuming the gathering that is already active does nothing',
      () async {
        final repo = InMemoryGatheringRepository();
        final saved = _gatheringIn(GatheringStatus.ordering);
        await repo.save(saved);
        final c = containerWith(repo);
        final controller = c.read(gatheringProvider.notifier);

        await controller.resume(saved.id);
        await controller.resume(saved.id);
        expect(c.read(gatheringProvider)!.id, saved.id);
      },
    );
  });

  group('7. start-up recovery', () {
    test('restores an unfinished gathering after a full restart', () async {
      // First run: get to serving with one portion served.
      final firstRepo = connect();
      final first = containerWith(firstRepo);
      final controller = first.read(gatheringProvider.notifier);
      controller.startGathering(
        name: 'Brunch',
        restaurantName: 'MTR',
        hostName: 'Asha',
        menu: temporaryMenu,
      );
      controller.confirmMenu();
      controller.addParticipantWithOrder('Ravi', {'m1': 2});
      controller.addParticipantWithOrder('Meera', {'m6': 1});
      controller.startServing();
      final line = first.read(gatheringProvider)!.orderLines.first;
      controller.setServedQuantity(line.id, 1);
      await controller.flushSaves();
      final before = first.read(gatheringProvider)!;

      // "Process death": drop the container and the connection.
      first.dispose();
      for (final db in openDbs) {
        await db.close();
      }
      openDbs.clear();

      // Second run: a new connection, startup check and container.
      final repo = connect();
      final startup = await loadStartupState(repo);
      expect(startup.initialLocation, Routes.home);
      final restored = startup.resumeGathering!;
      final second = containerWith(repo);
      second.read(gatheringProvider.notifier).restore(restored);

      final after = second.read(gatheringProvider)!;
      expect(after.id, before.id);
      expect(after.status, GatheringStatus.serving);
      expect(after.participants.map((p) => p.name), ['Ravi', 'Meera']);
      expect(after.orderLines.map((l) => l.servedQuantity), [1, 0]);
      expect(after.subtotalPaise, before.subtotalPaise);

      // Carrying on after the restart keeps saving to the same gathering.
      second
          .read(gatheringProvider.notifier)
          .setServedQuantity(after.orderLines.first.id, 2);
      await second.read(gatheringProvider.notifier).flushSaves();
      expect((await repo.listAll()).gatherings, hasLength(1));
      expect(
        (await readFromDisk(after.id))!.orderLines.first.servedQuantity,
        2,
      );
    });

    Gathering at(String id, GatheringStatus status, DateTime createdAt) =>
        Gathering(
          id: id,
          createdAt: createdAt,
          name: id,
          restaurantName: 'R',
          hostName: 'H',
          status: status,
          menu: temporaryMenu,
        );

    test('nothing saved: start at Home', () async {
      final startup = await loadStartupState(connect());
      expect(startup.resumeGathering, isNull);
      expect(startup.initialLocation, Routes.home);
      expect(startup.issue, isNull);
    });

    test('only completed gatherings: start at Home', () async {
      final repo = connect();
      await repo.save(
        at('done', GatheringStatus.completed, DateTime(2026, 11, 1)),
      );
      final startup = await loadStartupState(repo);
      expect(startup.resumeGathering, isNull);
      expect(startup.initialLocation, Routes.home);
    });

    test('several unfinished: ask, never pick one', () async {
      final repo = connect();
      await repo.save(at('a', GatheringStatus.ordering, DateTime(2026, 11, 1)));
      await repo.save(at('b', GatheringStatus.serving, DateTime(2026, 11, 2)));
      final startup = await loadStartupState(repo);
      expect(startup.resumeGathering, isNull);
      expect(startup.initialLocation, Routes.resume);
    });

    test('start-up never writes, so it cannot duplicate', () async {
      final spy = _CountingRepository();
      await spy.save(at('a', GatheringStatus.ordering, DateTime(2026, 11, 1)));
      spy.saves = 0;
      await loadStartupState(spy);
      await loadStartupState(spy);
      expect(spy.saves, 0);
      expect((await spy.listAll()).gatherings, hasLength(1));
    });

    test(
      'a corrupt unfinished row is reported; the readable one resumes',
      () async {
        final repo = connect();
        await repo.save(
          at('good', GatheringStatus.ordering, DateTime(2026, 11, 1)),
        );
        await openDbs.last.customStatement(
          'INSERT INTO gatherings '
          '(id, name, restaurant_name, host_name, created_at, status) '
          "VALUES ('bad', 'bad', 'R', 'H', '2026-11-02T10:00:00.000Z', 'x')",
        );

        final startup = await loadStartupState(repo);
        expect(startup.resumeGathering!.id, 'good');
        expect(startup.issue, contains("couldn't be read"));
      },
    );

    test('unreadable storage: open at Home with a message', () async {
      final startup = await loadStartupState(_FailingRepository());
      expect(startup.resumeGathering, isNull);
      expect(startup.initialLocation, Routes.home);
      expect(startup.issue, isNotNull);
    });
  });
}

class _FailingRepository implements GatheringRepository {
  @override
  Future<void> save(Gathering gathering) async =>
      throw const GatheringStorageException('disk full');

  @override
  Future<Gathering?> load(String id) async =>
      throw const GatheringStorageException('unreadable');

  @override
  Future<void> delete(String id) async =>
      throw const GatheringStorageException('disk full');

  @override
  Future<GatheringList> listAll() async =>
      throw const GatheringStorageException('unreadable');

  @override
  Future<GatheringList> listUnfinished() async =>
      throw const GatheringStorageException('unreadable');
}

class _CountingRepository extends InMemoryGatheringRepository {
  int saves = 0;

  @override
  Future<void> save(Gathering gathering) {
    saves++;
    return super.save(gathering);
  }
}

Gathering _gatheringIn(GatheringStatus status) => Gathering(
  id: 'saved-${status.name}',
  createdAt: DateTime.utc(2026, 11, 8),
  name: 'Brunch',
  restaurantName: 'MTR',
  hostName: 'Asha',
  status: status,
  menu: temporaryMenu,
);

/// Fails only the save that marks a gathering completed, until told not to.
class _FailOnCompleteRepository extends InMemoryGatheringRepository {
  bool failCompletion = true;

  @override
  Future<void> save(Gathering gathering) async {
    if (failCompletion && gathering.status.isFinished) {
      throw const GatheringStorageException('disk full');
    }
    return super.save(gathering);
  }
}

/// Holds every load until [gate] completes, so requests can overlap.
class _SlowRepository extends InMemoryGatheringRepository {
  final gate = Completer<void>();
  int loads = 0;

  @override
  Future<Gathering?> load(String id) async {
    loads++;
    await gate.future;
    return super.load(id);
  }
}

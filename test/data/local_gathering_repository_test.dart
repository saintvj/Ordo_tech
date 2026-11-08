import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ordo/application/gathering_controller.dart';
import 'package:ordo/data/gathering_repository.dart';
import 'package:ordo/data/local/app_database.dart';
import 'package:ordo/data/local/local_gathering_repository.dart';
import 'package:ordo/domain/models.dart';
import 'package:ordo/domain/temporary_menu.dart';

/// Every round trip here saves, closes the database, opens a new connection
/// to the same SQLite file and loads from that, so nothing is read back from
/// memory.
void main() {
  late Directory dir;
  late File dbFile;
  AppDatabase? db;

  LocalGatheringRepository open() {
    db = AppDatabase(NativeDatabase(dbFile));
    return LocalGatheringRepository(db!);
  }

  Future<LocalGatheringRepository> reopen() async {
    await db?.close();
    return open();
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ordo_db_test');
    dbFile = File('${dir.path}/ordo.sqlite');
  });

  tearDown(() async {
    await db?.close();
    db = null;
    await dir.delete(recursive: true);
  });

  /// Builds gatherings through the real controller, so they obey the same
  /// rules as in the app.
  GatheringController controllerOn(ProviderContainer c) =>
      c.read(gatheringProvider.notifier);

  ProviderContainer newContainer([GatheringRepository? repository]) {
    final c = ProviderContainer(
      overrides: [
        if (repository != null)
          gatheringRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// A gathering in serving with two participants, one portion served.
  Gathering servingGathering({String name = 'Brunch'}) {
    final c = newContainer();
    final g = controllerOn(c);
    g.startGathering(
      name: name,
      restaurantName: 'MTR',
      hostName: 'Asha',
      menu: temporaryMenu,
    );
    final category = c.read(gatheringProvider)!.menu.categories.first.id;
    g.addItem(category, name: 'Pongal', pricePaise: 9050);
    g.confirmMenu();
    final ravi = g.addParticipantWithOrder('Ravi', {'m1': 2, 'm6': 1});
    g.addParticipantWithOrder('Meera', {'m4': 1});
    g.startServing();
    final line = c.read(gatheringProvider)!.linesFor(ravi).first;
    g.setServedQuantity(line.id, 1);
    return c.read(gatheringProvider)!;
  }

  void expectSameGathering(Gathering actual, Gathering expected) {
    expect(actual.id, expected.id);
    expect(actual.name, expected.name);
    expect(actual.restaurantName, expected.restaurantName);
    expect(actual.hostName, expected.hostName);
    expect(actual.createdAt.isAtSameMomentAs(expected.createdAt), isTrue);
    expect(actual.status, expected.status);
    // One flat record per item: records holding a List compare that list
    // by identity, not contents.
    List<(String, String, String, String, int)> menuRows(Gathering g) => [
      for (final c in g.menu.categories)
        for (final i in c.items) (c.id, c.name, i.id, i.name, i.pricePaise),
    ];
    expect(
      [for (final c in actual.menu.categories) (c.id, c.name)],
      [for (final c in expected.menu.categories) (c.id, c.name)],
    );
    expect(menuRows(actual), menuRows(expected));
    expect(
      [for (final p in actual.participants) (p.id, p.name)],
      [for (final p in expected.participants) (p.id, p.name)],
    );
    expect(
      [
        for (final l in actual.orderLines)
          (
            l.id,
            l.participantId,
            l.menuItemId,
            l.itemName,
            l.unitPricePaise,
            l.quantity,
            l.servedQuantity,
          ),
      ],
      [
        for (final l in expected.orderLines)
          (
            l.id,
            l.participantId,
            l.menuItemId,
            l.itemName,
            l.unitPricePaise,
            l.quantity,
            l.servedQuantity,
          ),
      ],
    );
  }

  group('round trips through a reopened database', () {
    test('1. creating and saving a gathering', () async {
      final c = newContainer();
      controllerOn(
        c,
      ).startGathering(name: 'Brunch', restaurantName: 'MTR', hostName: 'Asha');
      final gathering = c.read(gatheringProvider)!;

      await open().save(gathering);
      final loaded = await (await reopen()).load(gathering.id);

      expectSameGathering(loaded!, gathering);
      expect(loaded.status, GatheringStatus.menuDraft);
    });

    test('2. menu categories, items, order and paise prices', () async {
      final gathering = servingGathering();
      await open().save(gathering);
      final loaded = (await (await reopen()).load(gathering.id))!;

      expect(loaded.menu.categories.map((c) => c.name), [
        'Breakfast',
        'Beverages',
      ]);
      expect(loaded.menu.categories.first.items.last.name, 'Pongal');
      expect(loaded.menu.findItem('m4')!.pricePaise, 12000);
      expectSameGathering(loaded, gathering);
    });

    test('3. participants keep their ids, names and order', () async {
      final gathering = servingGathering();
      await open().save(gathering);
      final loaded = (await (await reopen()).load(gathering.id))!;

      expect(loaded.participants.map((p) => p.name), ['Ravi', 'Meera']);
      expect(
        loaded.participants.map((p) => p.id),
        gathering.participants.map((p) => p.id),
      );
    });

    test('4. order lines keep quantities and price snapshots', () async {
      final gathering = servingGathering();
      await open().save(gathering);
      final loaded = (await (await reopen()).load(gathering.id))!;

      final ravi = loaded.participants.first.id;
      expect(
        loaded
            .linesFor(ravi)
            .map((l) => (l.itemName, l.unitPricePaise, l.quantity)),
        [('Idli', 5000, 2), ('Tea', 2000, 1)],
      );
      expect(loaded.subtotalPaise, gathering.subtotalPaise);
    });

    test('5. serving progress', () async {
      final gathering = servingGathering();
      await open().save(gathering);
      final loaded = (await (await reopen()).load(gathering.id))!;

      expect(loaded.status, GatheringStatus.serving);
      expect(loaded.orderLines.map((l) => l.servedQuantity), [1, 0, 0]);
    });

    test('a later save replaces the earlier snapshot completely', () async {
      final c = newContainer();
      final g = controllerOn(c);
      g.startGathering(
        name: 'Brunch',
        restaurantName: 'MTR',
        hostName: 'Asha',
        menu: temporaryMenu,
      );
      g.confirmMenu();
      final ravi = g.addParticipantWithOrder('Ravi', {'m1': 1});
      g.addParticipantWithOrder('Meera', {'m2': 1});
      var repo = open();
      await repo.save(c.read(gatheringProvider)!);

      g.replaceOrder(ravi, {}); // removes Ravi
      await repo.save(c.read(gatheringProvider)!);
      repo = await reopen();
      final loaded = (await repo.load(c.read(gatheringProvider)!.id))!;

      expect(loaded.participants.map((p) => p.name), ['Meera']);
      expect(loaded.orderLines, hasLength(1));
    });
  });

  test('6. gatherings with the same starter menu stay independent', () async {
    final c1 = newContainer();
    final g1 = controllerOn(c1);
    g1.startGathering(
      name: 'Lunch',
      restaurantName: 'A',
      hostName: 'Asha',
      menu: temporaryMenu,
    );
    final c2 = newContainer();
    final g2 = controllerOn(c2);
    g2.startGathering(
      name: 'Dinner',
      restaurantName: 'B',
      hostName: 'Ravi',
      menu: temporaryMenu,
    );
    // Both menus use category c1 and item m1; edit only the first.
    g1.updateItem('c1', 'm1', name: 'Ghee Idli', pricePaise: 7000);
    g1.deleteCategory('c2');

    final repo = open();
    await repo.save(c1.read(gatheringProvider)!);
    await repo.save(c2.read(gatheringProvider)!);
    final reopened = await reopen();
    final lunch = (await reopened.load(c1.read(gatheringProvider)!.id))!;
    final dinner = (await reopened.load(c2.read(gatheringProvider)!.id))!;

    expect(lunch.menu.findItem('m1')!.name, 'Ghee Idli');
    expect(lunch.menu.categories, hasLength(1));
    expect(dinner.menu.findItem('m1')!.name, 'Idli');
    expect(dinner.menu.findItem('m1')!.pricePaise, 5000);
    expect(dinner.menu.categories, hasLength(2));
  });

  group('10. repository queries', () {
    test('load returns null for an unknown id', () async {
      expect(await open().load('nope'), isNull);
    });

    test('listAll is newest first; listUnfinished skips completed', () async {
      final repo = open();
      Gathering at(String id, DateTime createdAt, GatheringStatus status) =>
          Gathering(
            id: id,
            createdAt: createdAt,
            name: id,
            restaurantName: 'R',
            hostName: 'H',
            status: status,
            menu: const Menu(),
          );
      await repo.save(
        at('old', DateTime(2026, 1, 1), GatheringStatus.completed),
      );
      await repo.save(
        at('mid', DateTime(2026, 6, 1), GatheringStatus.ordering),
      );
      await repo.save(
        at('new', DateTime(2026, 11, 1), GatheringStatus.serving),
      );

      final reopened = await reopen();
      expect((await reopened.listAll()).gatherings.map((s) => s.id), [
        'new',
        'mid',
        'old',
      ]);
      expect((await reopened.listUnfinished()).gatherings.map((s) => s.id), [
        'new',
        'mid',
      ]);
    });
  });

  group('8. completed gatherings are read-only', () {
    test('saving over a completed gathering is refused', () async {
      final serving = servingGathering();
      final completed = serving.copyWith(status: GatheringStatus.completed);
      var repo = open();
      await repo.save(completed);

      repo = await reopen();
      await expectLater(
        repo.save(serving.copyWith(orderLines: const [])),
        throwsA(isA<ReadOnlyGatheringException>()),
      );
      final loaded = (await repo.load(serving.id))!;
      expect(loaded.status, GatheringStatus.completed);
      expect(loaded.orderLines, hasLength(serving.orderLines.length));
    });

    test('a completed gathering cannot be made active', () async {
      final completed = servingGathering().copyWith(
        status: GatheringStatus.completed,
      );
      final repo = open();
      await repo.save(completed);
      final c = newContainer(repo);

      expect(() => controllerOn(c).restore(completed), throwsStateError);
      await expectLater(controllerOn(c).resume(completed.id), throwsStateError);
      expect(c.read(gatheringProvider), isNull);
    });
  });

  group('9. transactions and errors', () {
    test('a failed save rolls back and keeps the previous snapshot', () async {
      final gathering = servingGathering();
      var repo = open();
      await repo.save(gathering);

      // servedQuantity > quantity breaks a CHECK constraint part-way through
      // the transaction, after the old rows were already deleted.
      final broken = gathering.copyWith(
        orderLines: [
          for (final l in gathering.orderLines)
            OrderLine(
              id: l.id,
              participantId: l.participantId,
              menuItemId: l.menuItemId,
              itemName: l.itemName,
              unitPricePaise: l.unitPricePaise,
              quantity: l.quantity,
              servedQuantity: l.quantity + 1,
            ),
        ],
      );
      await expectLater(
        repo.save(broken),
        throwsA(isA<GatheringStorageException>()),
      );

      repo = await reopen();
      expectSameGathering((await repo.load(gathering.id))!, gathering);
    });

    test('unreadable stored data is reported, not returned', () async {
      final gathering = servingGathering();
      open();
      await LocalGatheringRepository(db!).save(gathering);
      await db!.customStatement(
        "UPDATE gatherings SET status = 'nonsense' WHERE id = ?",
        [gathering.id],
      );

      final repo = await reopen();
      await expectLater(
        repo.load(gathering.id),
        throwsA(isA<GatheringStorageException>()),
      );
    });

    test('foreign keys are enforced', () async {
      open();
      await expectLater(
        db!
            .into(db!.participants)
            .insert(
              ParticipantsCompanion.insert(
                id: 'p',
                gatheringId: 'no-such-gathering',
                name: 'Ghost',
                position: 0,
              ),
            ),
        throwsA(anything),
      );
    });
  });

  /// Inserts a gatherings row exactly as given, bypassing the repository
  /// (e.g. as an older version or a damaged file might have it).
  Future<void> insertRawGathering(
    String id, {
    String createdAt = '2026-11-08T14:00:00.000Z',
    String status = 'ordering',
  }) async {
    await db!.customStatement(
      'INSERT INTO gatherings '
      '(id, name, restaurant_name, host_name, created_at, status) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [id, id, 'R', 'H', createdAt, status],
    );
  }

  group('fix 1: history order by actual time', () {
    test('rows written with different offsets sort by moment', () async {
      open();
      // 19:05 +05:30 = 13:35Z; 09:00 -04:00 = 13:00Z. As text, "19:05"
      // sorts first, which was the bug.
      await insertRawGathering(
        'ist',
        createdAt: '2026-11-08T19:05:00.000 +05:30',
      );
      await insertRawGathering('utc', createdAt: '2026-11-08T14:00:00.000Z');
      await insertRawGathering(
        'ny',
        createdAt: '2026-11-08T09:00:00.000 -04:00',
      );

      final reopened = await reopen();
      expect((await reopened.listAll()).gatherings.map((g) => g.id), [
        'utc',
        'ist',
        'ny',
      ]);
    });

    test('creation times are stored in UTC and keep their moment', () async {
      final local = DateTime(2026, 11, 8, 19, 5);
      final repo = open();
      await repo.save(
        Gathering(
          id: 'g',
          createdAt: local,
          name: 'g',
          restaurantName: 'R',
          hostName: 'H',
          status: GatheringStatus.ordering,
          menu: const Menu(),
        ),
      );

      final reopened = await reopen();
      final raw = await db!
          .customSelect("SELECT created_at FROM gatherings WHERE id = 'g'")
          .getSingle();
      expect(raw.read<String>('created_at'), endsWith('Z'));
      final loaded = (await reopened.load('g'))!;
      expect(loaded.createdAt.isAtSameMomentAs(local), isTrue);
      final summary = (await reopened.listAll()).gatherings.single;
      expect(summary.createdAt.isAtSameMomentAs(local), isTrue);
    });
  });

  group('fix 2: unreadable rows', () {
    test('are skipped and reported, and the rest still list', () async {
      final repo = open();
      final good = servingGathering(name: 'Good');
      await repo.save(good);
      await insertRawGathering('bad-status', status: 'nonsense');
      await insertRawGathering('bad-date', createdAt: 'not a date');

      final reopened = await reopen();
      final all = await reopened.listAll();
      expect(all.gatherings.map((g) => g.id), [good.id]);
      expect(all.unreadableIds, unorderedEquals(['bad-status', 'bad-date']));
      final unfinished = await reopened.listUnfinished();
      expect(unfinished.gatherings.map((g) => g.id), [good.id]);
      expect(unfinished.unreadableIds, hasLength(2));
      expect((await reopened.load(good.id))!.name, 'Good');
    });

    test('are left untouched in storage', () async {
      open();
      await insertRawGathering('bad-status', status: 'nonsense');
      final repo = await reopen();
      await repo.listAll();
      await repo.listUnfinished();

      final row = await db!
          .customSelect("SELECT status FROM gatherings WHERE id = 'bad-status'")
          .getSingle();
      expect(row.read<String>('status'), 'nonsense');
    });
  });

  group('fix 4: order lines stay within their gathering', () {
    test("a line can't point at another gathering's participant", () async {
      final repo = open();
      final a = servingGathering(name: 'A');
      final b = servingGathering(name: 'B');
      await repo.save(a);
      await repo.save(b);
      final participantOfA = a.participants.first.id;
      await reopen();

      Future<void> insertLine(String id, String gatheringId) =>
          db!.customStatement(
            'INSERT INTO order_lines (id, gathering_id, participant_id, '
            'menu_item_id, item_name, unit_price_paise, quantity, '
            'served_quantity, position) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [id, gatheringId, participantOfA, 'm1', 'Idli', 5000, 1, 0, 9],
          );

      await expectLater(insertLine('cross', b.id), throwsA(anything));
      await insertLine('same', a.id); // allowed
      final rows = await db!
          .customSelect(
            "SELECT id FROM order_lines WHERE id IN ('cross', 'same')",
          )
          .get();
      expect(rows.map((r) => r.read<String>('id')), ['same']);
    });

    test(
      'saving through the repository rejects a cross-gathering line',
      () async {
        final repo = open();
        final a = servingGathering(name: 'A');
        final b = servingGathering(name: 'B');
        await repo.save(a);
        final line = b.orderLines.first;
        final crossed = b.copyWith(
          orderLines: [
            OrderLine(
              id: line.id,
              participantId: a.participants.first.id,
              menuItemId: line.menuItemId,
              itemName: line.itemName,
              unitPricePaise: line.unitPricePaise,
              quantity: line.quantity,
            ),
          ],
        );
        await expectLater(
          repo.save(crossed),
          throwsA(isA<GatheringStorageException>()),
        );
        final reopened = await reopen();
        expect(await reopened.load(b.id), isNull); // rolled back entirely
      },
    );
  });

  group('schema versioning', () {
    test(
      'a new database is created at the current schema version (2)',
      () async {
        open();
        await db!.customSelect('SELECT 1').get(); // opens and runs onCreate
        final version = await db!
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.data.values.single, 2);
        expect(db!.schemaVersion, 2);
      },
    );

    test('a database from a newer app version is refused, not wiped', () async {
      final gathering = servingGathering();
      open();
      await LocalGatheringRepository(db!).save(gathering);
      // Pretend a newer Ordo wrote this file.
      await db!.customStatement('PRAGMA user_version = 3');
      await db!.close();

      final raw = NativeDatabase(dbFile);
      db = AppDatabase(raw);
      await expectLater(
        db!.customSelect('SELECT 1').get(),
        throwsA(isA<UnsupportedError>()),
      );
      await db!.close();

      // The rows are still there.
      final check = NativeDatabase(dbFile);
      await check.ensureOpen(_RawReader());
      final rows = await check.runSelect(
        'SELECT COUNT(*) AS n FROM order_lines',
        const [],
      );
      expect(rows.single['n'], gathering.orderLines.length);
      await check.close();
      db = null;
    });
  });
}

/// Opens a database file as-is (at schema version 3, so drift runs no
/// migration) to inspect its rows.
class _RawReader extends QueryExecutorUser {
  @override
  int get schemaVersion => 3;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

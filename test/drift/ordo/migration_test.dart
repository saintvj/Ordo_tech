// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:ordo/data/local/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // Every row survives the v1 -> v2 migration unchanged, except that
  // created_at is rewritten from local time with an offset to UTC (same
  // moment).
  test('migration from v1 to v2 does not corrupt data', () async {
    final oldGatheringsData = <v1.GatheringsData>[
      const v1.GatheringsData(
        id: 'g1',
        name: 'Brunch',
        restaurantName: 'MTR',
        hostName: 'Asha',
        createdAt: '2026-11-08T19:05:00.000 +05:30',
        status: 'serving',
      ),
      const v1.GatheringsData(
        id: 'g2',
        name: 'Dinner',
        restaurantName: 'Vidyarthi Bhavan',
        hostName: 'Ravi',
        createdAt: '2026-11-07T21:30:00.000 -04:00',
        status: 'completed',
      ),
    ];
    final expectedNewGatheringsData = <v2.GatheringsData>[
      const v2.GatheringsData(
        id: 'g1',
        name: 'Brunch',
        restaurantName: 'MTR',
        hostName: 'Asha',
        createdAt: '2026-11-08T13:35:00.000Z',
        status: 'serving',
      ),
      const v2.GatheringsData(
        id: 'g2',
        name: 'Dinner',
        restaurantName: 'Vidyarthi Bhavan',
        hostName: 'Ravi',
        createdAt: '2026-11-08T01:30:00.000Z',
        status: 'completed',
      ),
    ];

    // Both gatherings use the same starter-menu ids.
    final oldMenuCategoriesData = <v1.MenuCategoriesData>[
      for (final g in ['g1', 'g2'])
        v1.MenuCategoriesData(
          gatheringId: g,
          id: 'c1',
          name: 'Breakfast',
          position: 0,
        ),
    ];
    final expectedNewMenuCategoriesData = <v2.MenuCategoriesData>[
      for (final g in ['g1', 'g2'])
        v2.MenuCategoriesData(
          gatheringId: g,
          id: 'c1',
          name: 'Breakfast',
          position: 0,
        ),
    ];

    final oldMenuItemsData = <v1.MenuItemsData>[
      for (final g in ['g1', 'g2'])
        v1.MenuItemsData(
          gatheringId: g,
          categoryId: 'c1',
          id: 'm1',
          name: 'Idli',
          pricePaise: 5000,
          position: 0,
        ),
    ];
    final expectedNewMenuItemsData = <v2.MenuItemsData>[
      for (final g in ['g1', 'g2'])
        v2.MenuItemsData(
          gatheringId: g,
          categoryId: 'c1',
          id: 'm1',
          name: 'Idli',
          pricePaise: 5000,
          position: 0,
        ),
    ];

    final oldParticipantsData = <v1.ParticipantsData>[
      const v1.ParticipantsData(
        id: 'p1',
        gatheringId: 'g1',
        name: 'Ravi',
        position: 0,
      ),
      const v1.ParticipantsData(
        id: 'p2',
        gatheringId: 'g2',
        name: 'Meera',
        position: 0,
      ),
    ];
    final expectedNewParticipantsData = <v2.ParticipantsData>[
      const v2.ParticipantsData(
        id: 'p1',
        gatheringId: 'g1',
        name: 'Ravi',
        position: 0,
      ),
      const v2.ParticipantsData(
        id: 'p2',
        gatheringId: 'g2',
        name: 'Meera',
        position: 0,
      ),
    ];

    final oldOrderLinesData = <v1.OrderLinesData>[
      const v1.OrderLinesData(
        id: 'l1',
        gatheringId: 'g1',
        participantId: 'p1',
        menuItemId: 'm1',
        itemName: 'Idli',
        unitPricePaise: 5000,
        quantity: 2,
        servedQuantity: 1,
        position: 0,
      ),
      const v1.OrderLinesData(
        id: 'l2',
        gatheringId: 'g2',
        participantId: 'p2',
        menuItemId: 'm1',
        itemName: 'Old Idli Name',
        unitPricePaise: 4500,
        quantity: 1,
        servedQuantity: 1,
        position: 0,
      ),
    ];
    final expectedNewOrderLinesData = <v2.OrderLinesData>[
      const v2.OrderLinesData(
        id: 'l1',
        gatheringId: 'g1',
        participantId: 'p1',
        menuItemId: 'm1',
        itemName: 'Idli',
        unitPricePaise: 5000,
        quantity: 2,
        servedQuantity: 1,
        position: 0,
      ),
      const v2.OrderLinesData(
        id: 'l2',
        gatheringId: 'g2',
        participantId: 'p2',
        menuItemId: 'm1',
        itemName: 'Old Idli Name',
        unitPricePaise: 4500,
        quantity: 1,
        servedQuantity: 1,
        position: 0,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.gatherings, oldGatheringsData);
        batch.insertAll(oldDb.menuCategories, oldMenuCategoriesData);
        batch.insertAll(oldDb.menuItems, oldMenuItemsData);
        batch.insertAll(oldDb.participants, oldParticipantsData);
        batch.insertAll(oldDb.orderLines, oldOrderLinesData);
      },
      validateItems: (newDb) async {
        expect(
          expectedNewGatheringsData,
          await newDb.select(newDb.gatherings).get(),
        );
        expect(
          expectedNewMenuCategoriesData,
          await newDb.select(newDb.menuCategories).get(),
        );
        expect(
          expectedNewMenuItemsData,
          await newDb.select(newDb.menuItems).get(),
        );
        expect(
          expectedNewParticipantsData,
          await newDb.select(newDb.participants).get(),
        );
        expect(
          expectedNewOrderLinesData,
          await newDb.select(newDb.orderLines).get(),
        );
      },
    );
  });
}

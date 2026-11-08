import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'app_database.steps.dart';

part 'app_database.g.dart';

// Tables. Only LocalGatheringRepository reads or writes these; the rest of
// the app works with the domain models in lib/domain/models.dart.

@DataClassName('GatheringRow')
class Gatherings extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get restaurantName => text()();
  TextColumn get hostName => text()();

  /// Always written in UTC (ISO-8601 text ending in `Z`), so stored values
  /// compare by actual time. Shown in local time.
  DateTimeColumn get createdAt => dateTime()();

  /// [GatheringStatus.name], e.g. `ordering`.
  TextColumn get status => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Category ids are only unique within a gathering (the starter menu reuses
/// the same ids in every gathering), hence the composite key.
@DataClassName('MenuCategoryRow')
class MenuCategories extends Table {
  TextColumn get gatheringId =>
      text().references(Gatherings, #id, onDelete: KeyAction.cascade)();
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {gatheringId, id};
}

@DataClassName('MenuItemRow')
class MenuItems extends Table {
  TextColumn get gatheringId =>
      text().references(Gatherings, #id, onDelete: KeyAction.cascade)();
  TextColumn get categoryId => text()();
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get pricePaise => integer()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {gatheringId, id};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (gathering_id, category_id) '
        'REFERENCES menu_categories (gathering_id, id) ON DELETE CASCADE',
    'CHECK (price_paise > 0)',
  ];
}

@DataClassName('ParticipantRow')
class Participants extends Table {
  TextColumn get id => text()();
  TextColumn get gatheringId =>
      text().references(Gatherings, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {id};

  /// Lets order lines reference a participant *within their gathering*.
  @override
  List<Set<Column>> get uniqueKeys => [
    {gatheringId, id},
  ];
}

/// [menuItemId] is deliberately not a foreign key: an order line keeps its
/// own copy of the item name and price, so it stays valid whatever happens
/// to the menu row.
@DataClassName('OrderLineRow')
class OrderLines extends Table {
  TextColumn get id => text()();
  TextColumn get gatheringId =>
      text().references(Gatherings, #id, onDelete: KeyAction.cascade)();
  TextColumn get participantId => text()();
  TextColumn get menuItemId => text()();
  TextColumn get itemName => text()();
  IntColumn get unitPricePaise => integer()();
  IntColumn get quantity => integer()();
  IntColumn get servedQuantity => integer()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    // A line can only belong to a participant of the same gathering.
    'FOREIGN KEY (gathering_id, participant_id) '
        'REFERENCES participants (gathering_id, id) ON DELETE CASCADE',
    'CHECK (unit_price_paise >= 0)',
    'CHECK (quantity > 0)',
    'CHECK (served_quantity BETWEEN 0 AND quantity)',
  ];
}

@DriftDatabase(
  tables: [Gatherings, MenuCategories, MenuItems, Participants, OrderLines],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// The app's on-device database file.
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'ordo'));

  /// Bump this for every schema change, then run
  /// `dart run drift_dev make-migrations` to export the new schema to
  /// `drift_schemas/` and generate a step for [migration].
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // An older app opening a file from a newer one: refuse rather than
      // guess and risk losing gatherings.
      if (from > to) {
        throw UnsupportedError(
          'Database schema $from is newer than this app ($to)',
        );
      }
      // Rebuilding tables needs foreign keys off; it can't change inside a
      // transaction, so it is switched here and back on in beforeOpen.
      await customStatement('PRAGMA foreign_keys = OFF');
      await transaction(() => _upgrade(m, from, to));
      final broken = await customSelect('PRAGMA foreign_key_check').get();
      if (broken.isNotEmpty) {
        throw StateError(
          'Migration from schema $from to $to left ${broken.length} '
          'inconsistent rows',
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// One step per schema version. Steps may add or rebuild tables (drift's
  /// alterTable copies every row); they must never drop user data.
  ///
  /// After changing the schema, bump [schemaVersion] and run
  /// `dart run drift_dev make-migrations` to export it and regenerate
  /// app_database.steps.dart and the migration tests.
  static final _upgrade = stepByStep(
    from1To2: (m, schema) async {
      // Order lines now reference a participant within their gathering.
      await m.alterTable(TableMigration(schema.participants));
      await m.alterTable(TableMigration(schema.orderLines));

      // Timestamps were stored in local time with an offset, which doesn't
      // sort by actual time. Rewrite each one as UTC; the moment it
      // represents is unchanged.
      final db = m.database;
      final rows = await db
          .customSelect('SELECT id, created_at FROM gatherings')
          .get();
      for (final row in rows) {
        await db.customUpdate(
          'UPDATE gatherings SET created_at = ? WHERE id = ?',
          variables: [
            Variable<DateTime>(row.read<DateTime>('created_at').toUtc()),
            Variable<String>(row.read<String>('id')),
          ],
          updates: {},
        );
      }
    },
  );
}

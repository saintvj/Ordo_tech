import 'package:drift/drift.dart';

import '../../domain/models.dart';
import '../gathering_repository.dart';
import 'app_database.dart';

/// Stores gatherings on the device with Drift (SQLite).
///
/// A save replaces all of a gathering's rows inside one transaction, so the
/// stored gathering is always a complete snapshot of one domain state; a
/// failure part-way leaves the previous snapshot untouched.
class LocalGatheringRepository implements GatheringRepository {
  LocalGatheringRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> save(Gathering gathering) async {
    try {
      await _db.transaction(() async {
        final stored = await (_db.select(
          _db.gatherings,
        )..where((t) => t.id.equals(gathering.id))).getSingleOrNull();
        if (stored != null && _statusOf(stored).isFinished) {
          throw ReadOnlyGatheringException(gathering.id);
        }

        // An upsert, not delete-and-insert, so the cascade from
        // `gatherings` never fires.
        await _db
            .into(_db.gatherings)
            .insertOnConflictUpdate(
              GatheringsCompanion.insert(
                id: gathering.id,
                name: gathering.name,
                restaurantName: gathering.restaurantName,
                hostName: gathering.hostName,
                // UTC, so stored times compare by actual moment.
                createdAt: gathering.createdAt.toUtc(),
                status: gathering.status.name,
              ),
            );

        final id = gathering.id;
        await (_db.delete(
          _db.orderLines,
        )..where((t) => t.gatheringId.equals(id))).go();
        await (_db.delete(
          _db.participants,
        )..where((t) => t.gatheringId.equals(id))).go();
        await (_db.delete(
          _db.menuItems,
        )..where((t) => t.gatheringId.equals(id))).go();
        await (_db.delete(
          _db.menuCategories,
        )..where((t) => t.gatheringId.equals(id))).go();

        await _db.batch((batch) {
          final categories = gathering.menu.categories;
          batch.insertAll(_db.menuCategories, [
            for (final (i, c) in categories.indexed)
              MenuCategoriesCompanion.insert(
                gatheringId: id,
                id: c.id,
                name: c.name,
                position: i,
              ),
          ]);
          batch.insertAll(_db.menuItems, [
            for (final c in categories)
              for (final (i, item) in c.items.indexed)
                MenuItemsCompanion.insert(
                  gatheringId: id,
                  categoryId: c.id,
                  id: item.id,
                  name: item.name,
                  pricePaise: item.pricePaise,
                  position: i,
                ),
          ]);
          batch.insertAll(_db.participants, [
            for (final (i, p) in gathering.participants.indexed)
              ParticipantsCompanion.insert(
                id: p.id,
                gatheringId: id,
                name: p.name,
                position: i,
              ),
          ]);
          batch.insertAll(_db.orderLines, [
            for (final (i, l) in gathering.orderLines.indexed)
              OrderLinesCompanion.insert(
                id: l.id,
                gatheringId: id,
                participantId: l.participantId,
                menuItemId: l.menuItemId,
                itemName: l.itemName,
                unitPricePaise: l.unitPricePaise,
                quantity: l.quantity,
                servedQuantity: l.servedQuantity,
                position: i,
              ),
          ]);
        });
      });
    } on ReadOnlyGatheringException {
      rethrow;
    } catch (e) {
      throw GatheringStorageException(
        'Could not save gathering ${gathering.id}',
        e,
      );
    }
  }

  @override
  Future<Gathering?> load(String id) async {
    try {
      // One read transaction, so the rows come from a single snapshot.
      return await _db.transaction(() async {
        final row = await (_db.select(
          _db.gatherings,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row == null) return null;

        final categoryRows =
            await (_db.select(_db.menuCategories)
                  ..where((t) => t.gatheringId.equals(id))
                  ..orderBy([(t) => OrderingTerm.asc(t.position)]))
                .get();
        final itemRows =
            await (_db.select(_db.menuItems)
                  ..where((t) => t.gatheringId.equals(id))
                  ..orderBy([(t) => OrderingTerm.asc(t.position)]))
                .get();
        final participantRows =
            await (_db.select(_db.participants)
                  ..where((t) => t.gatheringId.equals(id))
                  ..orderBy([(t) => OrderingTerm.asc(t.position)]))
                .get();
        final lineRows =
            await (_db.select(_db.orderLines)
                  ..where((t) => t.gatheringId.equals(id))
                  ..orderBy([(t) => OrderingTerm.asc(t.position)]))
                .get();

        return Gathering(
          id: row.id,
          createdAt: row.createdAt,
          name: row.name,
          restaurantName: row.restaurantName,
          hostName: row.hostName,
          status: _statusOf(row),
          menu: Menu(
            categories: List.unmodifiable([
              for (final c in categoryRows)
                MenuCategory(
                  id: c.id,
                  name: c.name,
                  items: List.unmodifiable([
                    for (final i in itemRows)
                      if (i.categoryId == c.id)
                        MenuItem(
                          id: i.id,
                          name: i.name,
                          pricePaise: i.pricePaise,
                        ),
                  ]),
                ),
            ]),
          ),
          participants: List.unmodifiable([
            for (final p in participantRows)
              Participant(id: p.id, name: p.name),
          ]),
          orderLines: List.unmodifiable([
            for (final l in lineRows)
              OrderLine(
                id: l.id,
                participantId: l.participantId,
                menuItemId: l.menuItemId,
                itemName: l.itemName,
                unitPricePaise: l.unitPricePaise,
                quantity: l.quantity,
                servedQuantity: l.servedQuantity,
              ),
          ]),
        );
      });
    } catch (e) {
      throw GatheringStorageException('Could not load gathering $id', e);
    }
  }

  @override
  Future<GatheringList> listAll() => _list(unfinishedOnly: false);

  @override
  Future<GatheringList> listUnfinished() => _list(unfinishedOnly: true);

  /// Reads rows one by one, so a row with an unknown stage or an unparsable
  /// date is skipped and reported instead of failing the whole list. Rows
  /// are only read here, never changed.
  Future<GatheringList> _list({required bool unfinishedOnly}) async {
    final List<QueryRow> rows;
    try {
      rows = await _db
          .customSelect(
            'SELECT id, name, restaurant_name, host_name, created_at, status '
            'FROM gatherings',
            readsFrom: {_db.gatherings},
          )
          .get();
    } catch (e) {
      throw GatheringStorageException('Could not list gatherings', e);
    }

    final summaries = <GatheringSummary>[];
    final unreadable = <String>[];
    for (final row in rows) {
      final id = row.read<String>('id');
      try {
        final summary = GatheringSummary(
          id: id,
          name: row.read<String>('name'),
          restaurantName: row.read<String>('restaurant_name'),
          hostName: row.read<String>('host_name'),
          createdAt: row.read<DateTime>('created_at'),
          status: GatheringStatus.values.byName(row.read<String>('status')),
        );
        if (!unfinishedOnly || !summary.status.isFinished) {
          summaries.add(summary);
        }
      } catch (_) {
        unreadable.add(id);
      }
    }
    return GatheringList(newestFirst(summaries), unreadableIds: unreadable);
  }

  static GatheringStatus _statusOf(GatheringRow row) =>
      GatheringStatus.values.byName(row.status);
}

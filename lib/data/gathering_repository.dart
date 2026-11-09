import '../domain/models.dart';

/// Stores gatherings. The application layer depends only on this interface;
/// [LocalGatheringRepository] implements it with Drift today, and a
/// Firestore implementation can implement it later.
///
/// Gatherings are always saved and loaded whole, so an implementation can
/// keep a gathering's rows consistent inside one transaction.
abstract interface class GatheringRepository {
  /// Inserts or replaces [gathering] and all its menu, participant and order
  /// data.
  ///
  /// Throws [ReadOnlyGatheringException] if the stored gathering is already
  /// completed, and [GatheringStorageException] if the write fails.
  Future<void> save(Gathering gathering);

  /// Returns the gathering with [id], or null if there is none.
  ///
  /// Throws [GatheringStorageException] if the stored data can't be read.
  Future<Gathering?> load(String id);

  /// Permanently deletes the unfinished gathering [id] and all its menu,
  /// participant and order data. Deleting a gathering that is not stored
  /// does nothing.
  ///
  /// Throws [ReadOnlyGatheringException] for a completed gathering, which
  /// stays in history, and [GatheringStorageException] if the delete fails.
  Future<void> delete(String id);

  /// Every stored gathering, newest first.
  ///
  /// A gathering that can't be read is left out of
  /// [GatheringList.gatherings] and named in [GatheringList.unreadableIds]
  /// instead of failing the whole list. It is never changed or deleted.
  Future<GatheringList> listAll();

  /// Gatherings that are not completed, newest first. Unreadable ones are
  /// reported as in [listAll].
  Future<GatheringList> listUnfinished();
}

/// The result of listing gatherings.
class GatheringList {
  const GatheringList(this.gatherings, {this.unreadableIds = const []});

  /// Readable gatherings, newest first.
  final List<GatheringSummary> gatherings;

  /// Stored gatherings that couldn't be read (for example an unknown
  /// lifecycle stage). They are left untouched in storage.
  final List<String> unreadableIds;

  bool get hasUnreadable => unreadableIds.isNotEmpty;
}

/// Newest first, by actual moment (not by how the time was written).
List<GatheringSummary> newestFirst(Iterable<GatheringSummary> summaries) =>
    summaries.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

/// Thrown when saving over a gathering that is already completed.
class ReadOnlyGatheringException implements Exception {
  const ReadOnlyGatheringException(this.gatheringId);

  final String gatheringId;

  @override
  String toString() =>
      'ReadOnlyGatheringException: gathering $gatheringId is completed';
}

/// Thrown when the underlying storage can't be read or written.
class GatheringStorageException implements Exception {
  const GatheringStorageException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'GatheringStorageException: $message${cause == null ? '' : ' ($cause)'}';
}

/// Keeps gatherings in memory only. Used as the default in tests; the app
/// overrides it with [LocalGatheringRepository] in `main.dart`.
class InMemoryGatheringRepository implements GatheringRepository {
  final Map<String, Gathering> _gatherings = {};

  @override
  Future<void> save(Gathering gathering) async {
    final stored = _gatherings[gathering.id];
    if (stored != null && stored.status.isFinished) {
      throw ReadOnlyGatheringException(gathering.id);
    }
    _gatherings[gathering.id] = gathering;
  }

  @override
  Future<Gathering?> load(String id) async => _gatherings[id];

  @override
  Future<void> delete(String id) async {
    final stored = _gatherings[id];
    if (stored == null) return;
    if (stored.status.isFinished) throw ReadOnlyGatheringException(id);
    _gatherings.remove(id);
  }

  @override
  Future<GatheringList> listAll() async =>
      GatheringList(_summaries(_gatherings.values));

  @override
  Future<GatheringList> listUnfinished() async => GatheringList(
    _summaries(_gatherings.values.where((g) => !g.status.isFinished)),
  );

  static List<GatheringSummary> _summaries(Iterable<Gathering> gatherings) =>
      newestFirst([
        for (final g in gatherings)
          GatheringSummary(
            id: g.id,
            name: g.name,
            restaurantName: g.restaurantName,
            hostName: g.hostName,
            createdAt: g.createdAt,
            status: g.status,
          ),
      ]);
}

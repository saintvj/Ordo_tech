import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/gathering_repository.dart';
import '../domain/models.dart';

final gatheringProvider = NotifierProvider<GatheringController, Gathering?>(
  GatheringController.new,
);

/// Where gatherings are saved. Defaults to memory only (used by tests);
/// `main.dart` overrides it with the on-device Drift repository.
final gatheringRepositoryProvider = Provider<GatheringRepository>(
  (ref) => InMemoryGatheringRepository(),
);

/// The latest storage problem to tell the user about, or null.
final storageIssueProvider =
    NotifierProvider<StorageIssueNotifier, StorageIssue?>(
      StorageIssueNotifier.new,
    );

/// A message about storage, with an optional action such as "Try Again".
class StorageIssue {
  const StorageIssue(this.message, {this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
}

class StorageIssueNotifier extends Notifier<StorageIssue?> {
  @override
  StorageIssue? build() => null;

  void report(String message, {String? actionLabel, VoidCallback? onAction}) =>
      state = StorageIssue(
        message,
        actionLabel: actionLabel,
        onAction: onAction,
      );

  void clear() => state = null;
}

/// Owns the active gathering. Screens read it and change it only through
/// these methods, which enforce the gathering lifecycle:
/// menuDraft → ordering → serving.
///
/// Calling an action in the wrong state throws a [StateError]; that is a
/// programming error, not a user error.
///
/// Every change is saved through [gatheringRepositoryProvider] as soon as it
/// happens (see [_update]); nothing waits for the app to close.
class GatheringController extends Notifier<Gathering?> {
  static const _uuid = Uuid();

  /// Saves run one at a time, in the order the changes happened, so an
  /// older snapshot can never overwrite a newer one.
  Future<void> _saveQueue = Future.value();

  @override
  Gathering? build() => null;

  /// Completes once every change made so far has been written (or has
  /// failed and been reported).
  Future<void> flushSaves() => _saveQueue;

  void _update(Gathering next) {
    state = next;
    _enqueueSave(next);
  }

  void _enqueueSave(Gathering gathering) {
    final repository = ref.read(gatheringRepositoryProvider);
    _saveQueue = _saveQueue
        .then((_) => repository.save(gathering))
        .onError<Object>((error, stackTrace) {
          if (ref.mounted) {
            ref
                .read(storageIssueProvider.notifier)
                .report(
                  "Ordo couldn't save your latest change. "
                  'Keep the app open and try again.',
                );
          }
        });
  }

  Gathering get _current {
    final gathering = state;
    if (gathering == null) throw StateError('No active gathering');
    return gathering;
  }

  void _requireStatus(GatheringStatus status) {
    final current = _current.status;
    if (current != status) {
      throw StateError(
        'Action requires ${status.name}, but gathering is ${current.name}',
      );
    }
  }

  String _newId() => _uuid.v4();

  void startGathering({
    required String name,
    required String restaurantName,
    required String hostName,
    Menu menu = const Menu(),
  }) {
    _update(
      Gathering(
        id: _newId(),
        createdAt: DateTime.now().toUtc(),
        name: name.trim(),
        restaurantName: restaurantName.trim(),
        hostName: hostName.trim(),
        status: GatheringStatus.menuDraft,
        menu: menu,
      ),
    );
  }

  /// Makes a saved, unfinished gathering the active one again (after a
  /// restart, or from history). It is already saved, so nothing is written.
  void restore(Gathering gathering) {
    if (state != null) throw StateError('A gathering is already active');
    if (gathering.status.isFinished) {
      throw StateError('Completed gatherings are read-only');
    }
    state = gathering;
  }

  /// The resume that is still loading, if any. See [resume].
  Future<void>? _pendingResume;

  /// Loads the saved gathering [gatheringId] and makes it active.
  ///
  /// A second call while one is still loading (e.g. a double tap) joins the
  /// first instead of failing, and asking for the gathering that is already
  /// active does nothing.
  Future<void> resume(String gatheringId) {
    if (state?.id == gatheringId) return Future.value();
    final pending = _pendingResume;
    if (pending != null) return pending;
    final load = _loadAndRestore(gatheringId);
    _pendingResume = load;
    return load.whenComplete(() => _pendingResume = null);
  }

  Future<void> _loadAndRestore(String gatheringId) async {
    final gathering = await ref
        .read(gatheringRepositoryProvider)
        .load(gatheringId);
    if (gathering == null) {
      throw StateError('No saved gathering $gatheringId');
    }
    restore(gathering);
  }

  /// Stops working on the active gathering without finishing it. It stays
  /// saved and can be resumed.
  void closeGathering() => state = null;

  /// Finishes the active gathering: it is saved as completed (read-only
  /// from then on) and, once that save has succeeded, is no longer active.
  ///
  /// Returns false if the save failed. The gathering then stays active and
  /// unchanged, the user is told, and calling this again retries.
  Future<bool> completeGathering() async {
    _requireStatus(GatheringStatus.serving);
    final completed = _current.copyWith(status: GatheringStatus.completed);
    final repository = ref.read(gatheringRepositoryProvider);

    // After every earlier change, so this is the last write.
    final save = _saveQueue.then((_) => repository.save(completed));
    _saveQueue = save.then((_) {}, onError: (Object _) {});
    try {
      await save;
    } on ReadOnlyGatheringException {
      // Already stored as completed (e.g. a repeated tap): nothing to undo.
    } catch (_) {
      if (ref.mounted) {
        ref
            .read(storageIssueProvider.notifier)
            .report(
              "Ordo couldn't finish this gathering. Your bill is still here.",
              actionLabel: 'Try Again',
              onAction: completeGathering,
            );
      }
      return false;
    }
    if (ref.mounted && state?.id == completed.id) state = null;
    return true;
  }

  // Menu editing (menuDraft only).

  void _updateMenu(List<MenuCategory> Function(List<MenuCategory>) update) {
    _requireStatus(GatheringStatus.menuDraft);
    final categories = update(_current.menu.categories);
    _update(
      _current.copyWith(menu: Menu(categories: List.unmodifiable(categories))),
    );
  }

  void _updateCategory(
    String categoryId,
    MenuCategory Function(MenuCategory) update,
  ) {
    _updateMenu(
      (categories) => [
        for (final c in categories) c.id == categoryId ? update(c) : c,
      ],
    );
  }

  static String _requireName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'Empty');
    return trimmed;
  }

  static int _requirePrice(int pricePaise) {
    if (pricePaise <= 0) {
      throw ArgumentError.value(pricePaise, 'pricePaise', 'Must be positive');
    }
    return pricePaise;
  }

  void addCategory(String name) {
    final category = MenuCategory(id: _newId(), name: _requireName(name));
    _updateMenu((categories) => [...categories, category]);
  }

  void renameCategory(String categoryId, String name) {
    final trimmed = _requireName(name);
    _updateCategory(categoryId, (c) => c.copyWith(name: trimmed));
  }

  void deleteCategory(String categoryId) {
    _updateMenu(
      (categories) => categories.where((c) => c.id != categoryId).toList(),
    );
  }

  void addItem(
    String categoryId, {
    required String name,
    required int pricePaise,
  }) {
    final item = MenuItem(
      id: _newId(),
      name: _requireName(name),
      pricePaise: _requirePrice(pricePaise),
    );
    _updateCategory(
      categoryId,
      (c) => c.copyWith(items: List.unmodifiable([...c.items, item])),
    );
  }

  void updateItem(
    String categoryId,
    String itemId, {
    required String name,
    required int pricePaise,
  }) {
    final trimmed = _requireName(name);
    _requirePrice(pricePaise);
    _updateCategory(
      categoryId,
      (c) => c.copyWith(
        items: List.unmodifiable([
          for (final i in c.items)
            i.id == itemId
                ? i.copyWith(name: trimmed, pricePaise: pricePaise)
                : i,
        ]),
      ),
    );
  }

  void deleteItem(String categoryId, String itemId) {
    _updateCategory(
      categoryId,
      (c) => c.copyWith(
        items: List.unmodifiable(c.items.where((i) => i.id != itemId)),
      ),
    );
  }

  /// Locks the menu and opens ordering.
  void confirmMenu() {
    _requireStatus(GatheringStatus.menuDraft);
    if (!_current.menu.hasItems) throw StateError('Menu has no items');
    _update(_current.copyWith(status: GatheringStatus.ordering));
  }

  // Ordering (ordering only).

  List<OrderLine> _buildLines(
    String participantId,
    Map<String, int> quantities,
  ) {
    final menu = _current.menu;
    return [
      for (final MapEntry(key: itemId, value: quantity) in quantities.entries)
        if (quantity > 0)
          _lineFor(
            participantId,
            menu.findItem(itemId) ??
                (throw ArgumentError.value(itemId, 'itemId', 'Not on menu')),
            quantity,
          ),
    ];
  }

  OrderLine _lineFor(String participantId, MenuItem item, int quantity) =>
      OrderLine(
        id: _newId(),
        participantId: participantId,
        menuItemId: item.id,
        itemName: item.name,
        unitPricePaise: item.pricePaise,
        quantity: quantity,
      );

  /// Adds a participant and their order in one step, so a participant only
  /// exists once they have confirmed an order. Returns the participant id.
  String addParticipantWithOrder(String name, Map<String, int> quantities) {
    _requireStatus(GatheringStatus.ordering);
    final participant = Participant(id: _newId(), name: _requireName(name));
    final lines = _buildLines(participant.id, quantities);
    if (lines.isEmpty) {
      throw ArgumentError.value(quantities, 'quantities', 'No items ordered');
    }
    _update(
      _current.copyWith(
        participants: List.unmodifiable([
          ..._current.participants,
          participant,
        ]),
        orderLines: List.unmodifiable([..._current.orderLines, ...lines]),
      ),
    );
    return participant.id;
  }

  /// Replaces a participant's order. An empty order removes the participant.
  void replaceOrder(String participantId, Map<String, int> quantities) {
    _requireStatus(GatheringStatus.ordering);
    final gathering = _current;
    if (gathering.findParticipant(participantId) == null) {
      throw ArgumentError.value(participantId, 'participantId', 'Unknown');
    }
    final lines = _buildLines(participantId, quantities);
    _update(
      gathering.copyWith(
        participants: lines.isEmpty
            ? List.unmodifiable(
                gathering.participants.where((p) => p.id != participantId),
              )
            : gathering.participants,
        orderLines: List.unmodifiable([
          ...gathering.orderLines.where(
            (l) => l.participantId != participantId,
          ),
          ...lines,
        ]),
      ),
    );
  }

  // Serving (serving only).

  /// Ends ordering. Orders cannot change after this.
  void startServing() {
    _requireStatus(GatheringStatus.ordering);
    if (_current.orderLines.isEmpty) throw StateError('No orders to serve');
    _update(_current.copyWith(status: GatheringStatus.serving));
  }

  void setServedQuantity(String lineId, int servedQuantity) {
    _requireStatus(GatheringStatus.serving);
    final gathering = _current;
    final line = gathering.orderLines.firstWhere(
      (l) => l.id == lineId,
      orElse: () => throw ArgumentError.value(lineId, 'lineId', 'Unknown'),
    );
    if (servedQuantity < 0 || servedQuantity > line.quantity) {
      throw RangeError.range(servedQuantity, 0, line.quantity);
    }
    _update(
      gathering.copyWith(
        orderLines: List.unmodifiable([
          for (final l in gathering.orderLines)
            l.id == lineId ? l.copyWith(servedQuantity: servedQuantity) : l,
        ]),
      ),
    );
  }
}

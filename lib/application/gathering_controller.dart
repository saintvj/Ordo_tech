import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';

final gatheringProvider = NotifierProvider<GatheringController, Gathering?>(
  GatheringController.new,
);

/// Owns the active gathering. Screens read it and change it only through
/// these methods, which enforce the gathering lifecycle:
/// menuDraft → ordering → serving.
///
/// Calling an action in the wrong state throws a [StateError]; that is a
/// programming error, not a user error.
class GatheringController extends Notifier<Gathering?> {
  static const _uuid = Uuid();

  @override
  Gathering? build() => null;

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
    state = Gathering(
      id: _newId(),
      createdAt: DateTime.now(),
      name: name.trim(),
      restaurantName: restaurantName.trim(),
      hostName: hostName.trim(),
      status: GatheringStatus.menuDraft,
      menu: menu,
    );
  }

  void closeGathering() => state = null;

  // Menu editing (menuDraft only).

  void _updateMenu(List<MenuCategory> Function(List<MenuCategory>) update) {
    _requireStatus(GatheringStatus.menuDraft);
    final categories = update(_current.menu.categories);
    state = _current.copyWith(
      menu: Menu(categories: List.unmodifiable(categories)),
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
    state = _current.copyWith(status: GatheringStatus.ordering);
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
    state = _current.copyWith(
      participants: List.unmodifiable([..._current.participants, participant]),
      orderLines: List.unmodifiable([..._current.orderLines, ...lines]),
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
    state = gathering.copyWith(
      participants: lines.isEmpty
          ? List.unmodifiable(
              gathering.participants.where((p) => p.id != participantId),
            )
          : gathering.participants,
      orderLines: List.unmodifiable([
        ...gathering.orderLines.where((l) => l.participantId != participantId),
        ...lines,
      ]),
    );
  }

  // Serving (serving only).

  /// Ends ordering. Orders cannot change after this.
  void startServing() {
    _requireStatus(GatheringStatus.ordering);
    if (_current.orderLines.isEmpty) throw StateError('No orders to serve');
    state = _current.copyWith(status: GatheringStatus.serving);
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
    state = gathering.copyWith(
      orderLines: List.unmodifiable([
        for (final l in gathering.orderLines)
          l.id == lineId ? l.copyWith(servedQuantity: servedQuantity) : l,
      ]),
    );
  }
}

import 'package:flutter/foundation.dart';

/// Lifecycle of a gathering. Each action in [GatheringController] is only
/// allowed in one of these states.
///
/// A [completed] gathering is finished and read-only; it only appears in
/// session history.
enum GatheringStatus {
  menuDraft,
  ordering,
  serving,
  completed;

  bool get isFinished => this == completed;
}

@immutable
class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.pricePaise,
  });

  final String id;
  final String name;
  final int pricePaise;

  MenuItem copyWith({String? name, int? pricePaise}) => MenuItem(
    id: id,
    name: name ?? this.name,
    pricePaise: pricePaise ?? this.pricePaise,
  );
}

@immutable
class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.name,
    this.items = const [],
  });

  final String id;
  final String name;
  final List<MenuItem> items;

  MenuCategory copyWith({String? name, List<MenuItem>? items}) =>
      MenuCategory(id: id, name: name ?? this.name, items: items ?? this.items);
}

@immutable
class Menu {
  const Menu({this.categories = const []});

  final List<MenuCategory> categories;

  Iterable<MenuItem> get items => categories.expand((c) => c.items);

  bool get hasItems => items.isNotEmpty;

  MenuItem? findItem(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}

@immutable
class Participant {
  const Participant({required this.id, required this.name});

  final String id;
  final String name;
}

/// One menu item ordered by one participant.
///
/// The item's name and price are copied when the order is placed, so later
/// menu changes never alter an existing order.
@immutable
class OrderLine {
  const OrderLine({
    required this.id,
    required this.participantId,
    required this.menuItemId,
    required this.itemName,
    required this.unitPricePaise,
    required this.quantity,
    this.servedQuantity = 0,
  });

  final String id;
  final String participantId;
  final String menuItemId;
  final String itemName;
  final int unitPricePaise;
  final int quantity;
  final int servedQuantity;

  int get totalPaise => unitPricePaise * quantity;

  OrderLine copyWith({int? servedQuantity}) => OrderLine(
    id: id,
    participantId: participantId,
    menuItemId: menuItemId,
    itemName: itemName,
    unitPricePaise: unitPricePaise,
    quantity: quantity,
    servedQuantity: servedQuantity ?? this.servedQuantity,
  );
}

@immutable
class Gathering {
  const Gathering({
    required this.id,
    required this.createdAt,
    required this.name,
    required this.restaurantName,
    required this.hostName,
    required this.status,
    required this.menu,
    this.participants = const [],
    this.orderLines = const [],
  });

  final String id;
  final DateTime createdAt;
  final String name;
  final String restaurantName;
  final String hostName;
  final GatheringStatus status;
  final Menu menu;
  final List<Participant> participants;
  final List<OrderLine> orderLines;

  Participant? findParticipant(String id) {
    for (final p in participants) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<OrderLine> linesFor(String participantId) =>
      orderLines.where((l) => l.participantId == participantId).toList();

  int subtotalFor(String participantId) =>
      linesFor(participantId).fold(0, (sum, l) => sum + l.totalPaise);

  int get subtotalPaise => orderLines.fold(0, (sum, l) => sum + l.totalPaise);

  Gathering copyWith({
    GatheringStatus? status,
    Menu? menu,
    List<Participant>? participants,
    List<OrderLine>? orderLines,
  }) => Gathering(
    id: id,
    createdAt: createdAt,
    name: name,
    restaurantName: restaurantName,
    hostName: hostName,
    status: status ?? this.status,
    menu: menu ?? this.menu,
    participants: participants ?? this.participants,
    orderLines: orderLines ?? this.orderLines,
  );
}

/// The fields shown in session history, without the menu or orders.
@immutable
class GatheringSummary {
  const GatheringSummary({
    required this.id,
    required this.name,
    required this.restaurantName,
    required this.hostName,
    required this.createdAt,
    required this.status,
  });

  final String id;
  final String name;
  final String restaurantName;
  final String hostName;
  final DateTime createdAt;
  final GatheringStatus status;
}

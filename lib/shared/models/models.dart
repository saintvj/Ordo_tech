class Participant {
  final String id;
  final String name;

  Participant({required this.id, required this.name});
}

class MenuItem {
  String id;
  String name;
  double price;

  MenuItem({required this.id, required this.name, required this.price});
}

class MenuCategory {
  String name;
  List<MenuItem> items;

  MenuCategory({required this.name, required this.items});
}

class Menu {
  List<MenuCategory> categories;

  Menu({required this.categories});
}

class OrderItem {
  final String id;
  final Participant participant;
  final MenuItem menuItem;
  bool isServed;

  OrderItem({
    required this.id,
    required this.participant,
    required this.menuItem,
    this.isServed = false,
  });
}

class Session {
  final String sessionId;
  final DateTime createdAt;
  final String gatheringName;
  final String restaurantName;
  final String hostName;
  final List<Participant> participants = [];
  Menu menu;
  final List<OrderItem> orders = [];
  String servingStatus;

  Session({
    required this.sessionId,
    required this.createdAt,
    required this.gatheringName,
    required this.restaurantName,
    required this.hostName,
    required this.menu,
    this.servingStatus = 'ordering',
  });
}

// Hardcoded Mock Menu for MVP fallback
final Menu mockMenu = Menu(
  categories: [
    MenuCategory(
      name: 'Breakfast',
      items: [
        MenuItem(id: 'm1', name: 'Idli', price: 50),
        MenuItem(id: 'm2', name: 'Vada', price: 60),
        MenuItem(id: 'm3', name: 'Plain Dosa', price: 80),
        MenuItem(id: 'm4', name: 'Masala Dosa', price: 120),
        MenuItem(id: 'm5', name: 'Rava Dosa', price: 130),
      ],
    ),
    MenuCategory(
      name: 'Beverages',
      items: [
        MenuItem(id: 'm6', name: 'Tea', price: 20),
        MenuItem(id: 'm7', name: 'Coffee', price: 30),
      ],
    ),
  ],
);

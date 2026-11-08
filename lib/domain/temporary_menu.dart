import 'models.dart';

/// Starter menu offered until menu scanning exists. It is immutable, so every
/// gathering that starts from it edits its own copy.
const temporaryMenu = Menu(
  categories: [
    MenuCategory(
      id: 'c1',
      name: 'Breakfast',
      items: [
        MenuItem(id: 'm1', name: 'Idli', pricePaise: 5000),
        MenuItem(id: 'm2', name: 'Vada', pricePaise: 6000),
        MenuItem(id: 'm3', name: 'Plain Dosa', pricePaise: 8000),
        MenuItem(id: 'm4', name: 'Masala Dosa', pricePaise: 12000),
        MenuItem(id: 'm5', name: 'Rava Dosa', pricePaise: 13000),
      ],
    ),
    MenuCategory(
      id: 'c2',
      name: 'Beverages',
      items: [
        MenuItem(id: 'm6', name: 'Tea', pricePaise: 2000),
        MenuItem(id: 'm7', name: 'Coffee', pricePaise: 3000),
      ],
    ),
  ],
);

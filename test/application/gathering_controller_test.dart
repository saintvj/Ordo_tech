import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ordo/application/gathering_controller.dart';
import 'package:ordo/domain/models.dart';
import 'package:ordo/domain/temporary_menu.dart';

void main() {
  late ProviderContainer container;
  late GatheringController controller;

  Gathering current() => container.read(gatheringProvider)!;

  void start() => controller.startGathering(
    name: 'Sunday Brunch',
    restaurantName: 'MTR',
    hostName: 'Asha',
    menu: temporaryMenu,
  );

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    controller = container.read(gatheringProvider.notifier);
  });

  test('starts with no gathering', () {
    expect(container.read(gatheringProvider), isNull);
  });

  test('startGathering trims details and starts in menuDraft', () {
    controller.startGathering(
      name: '  Brunch ',
      restaurantName: ' MTR ',
      hostName: ' Asha ',
    );
    expect(current().name, 'Brunch');
    expect(current().restaurantName, 'MTR');
    expect(current().hostName, 'Asha');
    expect(current().status, GatheringStatus.menuDraft);
  });

  group('menu editing', () {
    setUp(start);

    test('B1: edits do not leak into the next gathering', () {
      final categoryId = current().menu.categories.first.id;
      controller.updateItem(
        categoryId,
        'm1',
        name: 'Ghee Idli',
        pricePaise: 9900,
      );
      controller.deleteCategory(current().menu.categories.last.id);

      expect(temporaryMenu.categories, hasLength(2));
      expect(temporaryMenu.findItem('m1')!.name, 'Idli');

      start();
      expect(current().menu.categories, hasLength(2));
      expect(current().menu.findItem('m1')!.pricePaise, 5000);
    });

    test('adds, renames and deletes categories and items', () {
      controller.addCategory(' Desserts ');
      final desserts = current().menu.categories.last;
      expect(desserts.name, 'Desserts');

      controller.renameCategory(desserts.id, 'Sweets');
      controller.addItem(desserts.id, name: 'Kesari', pricePaise: 6000);
      final kesari = current().menu.categories.last.items.single;
      expect(current().menu.categories.last.name, 'Sweets');
      expect(kesari.pricePaise, 6000);

      controller.deleteItem(desserts.id, kesari.id);
      expect(current().menu.categories.last.items, isEmpty);
    });

    test('rejects empty names and non-positive prices', () {
      final categoryId = current().menu.categories.first.id;
      expect(() => controller.addCategory('   '), throwsArgumentError);
      expect(
        () => controller.addItem(categoryId, name: 'Upma', pricePaise: 0),
        throwsArgumentError,
      );
      expect(
        () => controller.addItem(categoryId, name: ' ', pricePaise: 100),
        throwsArgumentError,
      );
    });

    test('cannot confirm a menu with no items', () {
      controller.startGathering(name: 'a', restaurantName: 'b', hostName: 'c');
      expect(controller.confirmMenu, throwsStateError);
    });
  });

  group('ordering', () {
    setUp(() {
      start();
      controller.confirmMenu();
    });

    test('B2: menu is locked once ordering starts', () {
      final categoryId = current().menu.categories.first.id;
      expect(() => controller.addCategory('Late'), throwsStateError);
      expect(
        () => controller.updateItem(
          categoryId,
          'm1',
          name: 'Idli',
          pricePaise: 1,
        ),
        throwsStateError,
      );
      expect(() => controller.deleteItem(categoryId, 'm1'), throwsStateError);
    });

    test('B2: order lines snapshot item name and price', () {
      final id = controller.addParticipantWithOrder('Ravi', {'m1': 2, 'm6': 1});
      final lines = current().linesFor(id);
      expect(lines.map((l) => (l.itemName, l.unitPricePaise, l.quantity)), [
        ('Idli', 5000, 2),
        ('Tea', 2000, 1),
      ]);
      expect(current().subtotalFor(id), 12000);
    });

    test('B3: a participant only exists after confirming an order', () {
      expect(
        () => controller.addParticipantWithOrder('Ravi', {}),
        throwsArgumentError,
      );
      expect(
        () => controller.addParticipantWithOrder('Ravi', {'m1': 0}),
        throwsArgumentError,
      );
      expect(current().participants, isEmpty);

      controller.addParticipantWithOrder('Ravi', {'m1': 1});
      expect(current().participants.map((p) => p.name), ['Ravi']);
    });

    test('rejects items that are not on the menu', () {
      expect(
        () => controller.addParticipantWithOrder('Ravi', {'nope': 1}),
        throwsArgumentError,
      );
    });

    test('replaceOrder changes only that participant', () {
      final ravi = controller.addParticipantWithOrder('Ravi', {'m1': 1});
      final meera = controller.addParticipantWithOrder('Meera', {'m2': 1});

      controller.replaceOrder(ravi, {'m4': 3});

      expect(current().linesFor(ravi).single.quantity, 3);
      expect(current().linesFor(meera).single.itemName, 'Vada');
      expect(current().subtotalPaise, 3 * 12000 + 6000);
    });

    test('B7: an empty order removes the participant', () {
      final ravi = controller.addParticipantWithOrder('Ravi', {'m1': 1});
      controller.addParticipantWithOrder('Meera', {'m2': 1});

      controller.replaceOrder(ravi, {});

      expect(current().participants.map((p) => p.name), ['Meera']);
      expect(current().linesFor(ravi), isEmpty);
    });

    test('cannot start serving without orders', () {
      expect(controller.startServing, throwsStateError);
    });
  });

  group('serving', () {
    late String ravi;

    setUp(() {
      start();
      controller.confirmMenu();
      ravi = controller.addParticipantWithOrder('Ravi', {'m1': 2});
      controller.startServing();
    });

    test('B4: orders are locked once serving starts', () {
      expect(
        () => controller.addParticipantWithOrder('Late', {'m1': 1}),
        throwsStateError,
      );
      expect(() => controller.replaceOrder(ravi, {}), throwsStateError);
    });

    test('tracks served quantity within bounds', () {
      final line = current().orderLines.single;
      controller.setServedQuantity(line.id, 1);
      expect(current().orderLines.single.servedQuantity, 1);
      controller.setServedQuantity(line.id, 2);
      expect(current().orderLines.single.servedQuantity, 2);
      expect(() => controller.setServedQuantity(line.id, 3), throwsRangeError);
      expect(() => controller.setServedQuantity(line.id, -1), throwsRangeError);
    });

    test('closeGathering clears state', () {
      controller.closeGathering();
      expect(container.read(gatheringProvider), isNull);
    });
  });
}

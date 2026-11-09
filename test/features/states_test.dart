import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ordo/app/app.dart';
import 'package:ordo/app/router.dart';
import 'package:ordo/app/routes.dart';
import 'package:ordo/application/gathering_controller.dart';
import 'package:ordo/data/gathering_repository.dart';
import 'package:ordo/domain/models.dart';
import 'package:ordo/domain/temporary_menu.dart';
import 'package:ordo/features/session_flow/participant_order_screen.dart';

/// Empty, failed-load and missing-argument states.
void main() {
  late ProviderContainer container;

  Future<void> launch(
    WidgetTester tester, {
    GatheringRepository? repository,
    String initialLocation = Routes.home,
  }) async {
    container = ProviderContainer(
      overrides: [
        gatheringRepositoryProvider.overrideWithValue(
          repository ?? InMemoryGatheringRepository(),
        ),
        initialLocationProvider.overrideWithValue(initialLocation),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const OrdoApp()),
    );
    await tester.pumpAndSettle();
  }

  GatheringController controller() =>
      container.read(gatheringProvider.notifier);

  String location() => container
      .read(routerProvider)
      .routerDelegate
      .currentConfiguration
      .matches
      .last
      .matchedLocation;

  Future<void> go(WidgetTester tester, String to) async {
    container.read(routerProvider).go(to);
    await tester.pumpAndSettle();
  }

  group('empty states', () {
    testWidgets('an empty menu explains how to start', (tester) async {
      await launch(tester);
      controller().startGathering(
        name: 'Brunch',
        restaurantName: 'MTR',
        hostName: 'Asha',
      );
      await go(tester, Routes.editMenu);

      expect(find.text('Start your menu'), findsOneWidget);
      await tester.tap(find.text('Add Category'));
      await tester.pumpAndSettle();
      expect(find.text('Category Name'), findsOneWidget); // the dialog
    });

    testWidgets('a menu without dishes says why it cannot be confirmed', (
      tester,
    ) async {
      await launch(tester);
      controller()
        ..startGathering(name: 'Brunch', restaurantName: 'MTR', hostName: 'A')
        ..addCategory('Mains');
      await go(tester, Routes.editMenu);

      expect(find.text('Add at least one dish to continue.'), findsOneWidget);
      controller().addItem(
        container.read(gatheringProvider)!.menu.categories.single.id,
        name: 'Thali',
        pricePaise: 25000,
      );
      await tester.pumpAndSettle();
      expect(find.text('Add at least one dish to continue.'), findsNothing);
    });

    testWidgets('Review Orders with every order removed offers a way on', (
      tester,
    ) async {
      await launch(tester);
      controller()
        ..startGathering(
          name: 'Brunch',
          restaurantName: 'MTR',
          hostName: 'Asha',
          menu: temporaryMenu,
        )
        ..confirmMenu();
      final ravi = controller().addParticipantWithOrder('Ravi', {'m1': 1});
      controller().replaceOrder(ravi, {}); // removes Ravi
      await go(tester, Routes.reviewOrders);

      expect(find.text('No orders yet'), findsOneWidget);
      await tester.tap(find.text('Add Someone'));
      await tester.pumpAndSettle();
      expect(location(), Routes.participantName);
    });

    testWidgets('empty history says what will appear', (tester) async {
      await launch(tester);
      await tester.tap(find.text('Past Gatherings'));
      await tester.pumpAndSettle();
      expect(
        find.text('Gatherings you start will appear here.'),
        findsOneWidget,
      );
    });
  });

  group('failed loads offer Try Again', () {
    testWidgets('history', (tester) async {
      final repo = _FlakyRepository();
      await launch(tester, repository: repo);
      await tester.tap(find.text('Past Gatherings'));
      await tester.pumpAndSettle();

      expect(find.text("Past gatherings couldn't be loaded."), findsOneWidget);
      repo.failing = false;
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(
        find.text('Gatherings you start will appear here.'),
        findsOneWidget,
      );
    });

    testWidgets('the unfinished-gatherings picker', (tester) async {
      final repo = _FlakyRepository();
      await launch(tester, repository: repo, initialLocation: Routes.resume);

      expect(
        find.text("Unfinished gatherings couldn't be loaded."),
        findsOneWidget,
      );
      repo.failing = false;
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(find.text('Pick up where you left off.'), findsOneWidget);
    });

    testWidgets('a past bill', (tester) async {
      final repo = _FlakyRepository();
      await launch(tester, repository: repo);
      await go(tester, Routes.historyDetailFor('some-id'));

      expect(find.text("This gathering couldn't be loaded."), findsOneWidget);
      repo.failing = false;
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(
        find.text('This gathering is no longer saved on this phone.'),
        findsOneWidget,
      );
    });
  });

  group('missing or invalid route details', () {
    testWidgets('Menu Selection without details asks for them again', (
      tester,
    ) async {
      await launch(tester);
      await go(tester, Routes.menuSelection);
      expect(location(), Routes.createGathering);
      await go(tester, '${Routes.menuSelection}?gathering=Brunch&host=%20');
      expect(location(), Routes.createGathering);
    });

    testWidgets('the order screen without a name goes to Participant Name', (
      tester,
    ) async {
      await launch(tester);
      controller()
        ..startGathering(
          name: 'Brunch',
          restaurantName: 'MTR',
          hostName: 'Asha',
          menu: temporaryMenu,
        )
        ..confirmMenu();
      await go(tester, Routes.participantOrder);
      expect(location(), Routes.participantName);
      await go(tester, '${Routes.participantOrder}?name=%20%20');
      expect(location(), Routes.participantName);
    });

    testWidgets("editing someone who isn't in the gathering goes to Review", (
      tester,
    ) async {
      await launch(tester);
      controller()
        ..startGathering(
          name: 'Brunch',
          restaurantName: 'MTR',
          hostName: 'Asha',
          menu: temporaryMenu,
        )
        ..confirmMenu()
        ..addParticipantWithOrder('Ravi', {'m1': 1});
      await go(tester, const ParticipantOrderArgs.edit('nobody').location);
      expect(location(), Routes.reviewOrders);
    });

    testWidgets('a name with spaces and symbols arrives intact', (
      tester,
    ) async {
      await launch(tester);
      controller()
        ..startGathering(
          name: 'Brunch',
          restaurantName: 'MTR',
          hostName: 'Asha',
          menu: temporaryMenu,
        )
        ..confirmMenu();
      await go(
        tester,
        const ParticipantOrderArgs.newParticipant('Zoë & Ravi?').location,
      );
      expect(location(), Routes.participantOrder);
      expect(find.text("Zoë & Ravi?'s Order"), findsOneWidget);
    });
  });
}

/// Fails every read until [failing] is set to false.
class _FlakyRepository extends InMemoryGatheringRepository {
  bool failing = true;

  void _check() {
    if (failing) throw const GatheringStorageException('unreadable');
  }

  @override
  Future<GatheringList> listAll() async {
    _check();
    return super.listAll();
  }

  @override
  Future<GatheringList> listUnfinished() async {
    _check();
    return super.listUnfinished();
  }

  @override
  Future<Gathering?> load(String id) async {
    _check();
    return super.load(id);
  }
}

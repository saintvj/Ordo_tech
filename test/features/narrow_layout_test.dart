import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ordo/app/app.dart';
import 'package:ordo/app/routes.dart';
import 'package:ordo/application/gathering_controller.dart';
import 'package:ordo/data/gathering_repository.dart';
import 'package:ordo/domain/models.dart';
import 'package:ordo/features/session_flow/participant_order_screen.dart';

/// Every screen at a 360dp-wide phone, with the real bundled fonts and
/// deliberately long names and large amounts. A layout overflow is reported
/// as a test failure.
void main() {
  const longDish = 'Paneer Butter Masala with Garlic Naan and Extra Cheese';
  const longGuest = 'Venkataraghavan Subramaniam';
  const longGathering = "Grandmother's Eightieth Birthday Dinner";
  const longRestaurant = 'The Grand Imperial Heritage Kitchen';

  const menu = Menu(
    categories: [
      MenuCategory(
        id: 'c1',
        name: 'Chef Specials From The Tandoor',
        items: [
          MenuItem(id: 'm1', name: longDish, pricePaise: 12345600),
          MenuItem(id: 'm2', name: 'Masala Dosa', pricePaise: 12000),
        ],
      ),
    ],
  );

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final textScale in [1.0, 1.3]) {
    group('360dp wide, text ${(textScale * 100).round()}%', () {
      late ProviderContainer container;

      Future<void> showAt(WidgetTester tester, String route) async {
        container.read(routerProvider).go(route);
        await tester.pumpAndSettle();
      }

      Future<void> launch(WidgetTester tester, GatheringStatus status) async {
        tester.view.physicalSize = const Size(1080, 1920); // 360x640dp
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        container = ProviderContainer(
          overrides: [
            gatheringRepositoryProvider.overrideWithValue(
              InMemoryGatheringRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);
        final g = container.read(gatheringProvider.notifier);
        g.startGathering(
          name: longGathering,
          restaurantName: longRestaurant,
          hostName: longGuest,
          menu: menu,
        );
        if (status.index >= GatheringStatus.ordering.index) {
          g.confirmMenu();
          g.addParticipantWithOrder(longGuest, {'m1': 12, 'm2': 3});
          g.addParticipantWithOrder('Ravi', {'m1': 1});
        }
        if (status.index >= GatheringStatus.serving.index) g.startServing();

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const OrdoApp(),
          ),
        );
        // Real glyph widths, not the square test font.
        await tester.runAsync(() => GoogleFonts.pendingFonts());
        await tester.pumpAndSettle();
      }

      testWidgets('Edit Menu', (tester) async {
        await launch(tester, GatheringStatus.menuDraft);
        await showAt(tester, Routes.editMenu);
        expect(find.text(longDish), findsOneWidget);
      });

      testWidgets('Participant Order', (tester) async {
        await launch(tester, GatheringStatus.ordering);
        final id = container.read(gatheringProvider)!.participants.first.id;
        await showAt(tester, ParticipantOrderArgs.edit(id).location);
        expect(find.text(longDish), findsOneWidget);
      });

      testWidgets('Review Orders', (tester) async {
        await launch(tester, GatheringStatus.ordering);
        await showAt(tester, Routes.reviewOrders);
      });

      testWidgets('Waiter Mode', (tester) async {
        await launch(tester, GatheringStatus.serving);
        await showAt(tester, Routes.waiterMode);
      });

      testWidgets('Session Summary', (tester) async {
        await launch(tester, GatheringStatus.serving);
        await showAt(tester, Routes.sessionSummary);
      });

      testWidgets('Bill Summary', (tester) async {
        await launch(tester, GatheringStatus.serving);
        await showAt(tester, Routes.billSummary);
        // The bill scrolls as one list; the totals are reachable by
        // scrolling, and Close Session stays fully on screen.
        await tester.scrollUntilVisible(find.text('Grand Total'), 200);
        expect(find.text('Grand Total'), findsOneWidget);
        final button = tester.getRect(find.text('Close Session'));
        expect(button.bottom, lessThanOrEqualTo(640));
        expect(button.top, greaterThanOrEqualTo(0));
      });

      testWidgets('Past Gatherings and a past bill', (tester) async {
        await launch(tester, GatheringStatus.serving);
        final repo = container.read(gatheringRepositoryProvider);
        final done = container
            .read(gatheringProvider)!
            .copyWith(status: GatheringStatus.completed);
        await tester.runAsync(() => repo.save(done));
        container.read(gatheringProvider.notifier).closeGathering();
        await tester.pumpAndSettle();

        await showAt(tester, Routes.history);
        expect(find.text(longGathering), findsOneWidget);
        await showAt(tester, Routes.historyDetailFor(done.id));
        await tester.scrollUntilVisible(find.text('Grand Total'), 200);
      });

      testWidgets('Pass Phone and Participant Name', (tester) async {
        await launch(tester, GatheringStatus.ordering);
        await showAt(tester, Routes.passPhone);
        await showAt(tester, Routes.participantName);
      });
    });
  }
}

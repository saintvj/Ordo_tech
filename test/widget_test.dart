import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ordo/app/app.dart';

void main() {
  testWidgets('Home screen renders properly', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OrdoApp()));

    expect(find.text('Ordo'), findsOneWidget);
    expect(find.text('Start a Session'), findsOneWidget);
  });

  testWidgets('pass-and-play flow from gathering to bill', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2; // 540dp wide: test glyphs are square
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: OrdoApp()));

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tap(find.text('Start a Session'));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Brunch');
    await tester.enterText(fields.at(1), 'MTR');
    await tester.enterText(fields.at(2), 'Asha');
    await tap(find.text('Continue'));
    await tap(find.text('Use Temporary Menu'));
    await tap(find.text('Confirm Menu'));

    // The first participant cannot go back to the locked menu.
    expect(find.byType(BackButton), findsNothing);

    await tester.enterText(find.byType(TextField), 'Ravi');
    await tap(find.text('Continue to Menu'));
    await tap(find.byIcon(Icons.add).first); // Idli
    await tap(find.byIcon(Icons.add).first); // Idli again
    expect(find.text('₹100.00'), findsOneWidget);
    await tap(find.text('Confirm Order'));

    await tap(find.text('Finish Ordering'));
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Idli × 2'), findsOneWidget);

    await tap(find.text('Start Waiter Mode'));
    expect(find.text('0 / 2 Served'), findsOneWidget);
    await tap(find.text('Ravi').first);
    expect(find.text('1 / 2 Served'), findsOneWidget);

    // System back must not leave Waiter Mode.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 / 2 Served'), findsOneWidget);

    await tap(find.text('Finish Service'));
    await tap(find.text('View Bill'));
    expect(find.text('₹105.00'), findsOneWidget); // 100 + 2.5% + 2.5%

    await tap(find.text('Close Session'));
    expect(find.text('Start a Session'), findsOneWidget);
  });
}

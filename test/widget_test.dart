import 'package:flutter_test/flutter_test.dart';
import 'package:ordo/app/app.dart';

void main() {
  testWidgets('Home screen renders properly', (WidgetTester tester) async {
    await tester.pumpWidget(const OrdoApp());

    expect(find.text('Ordo'), findsOneWidget);
    expect(find.text('Start a Session'), findsOneWidget);
  });
}

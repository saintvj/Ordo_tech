import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ordo/core/theme/theme.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('every theme font loads from the bundle, without the network', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Text('Ordo')),
      ),
    );
    // Fails if any font the theme asked for is not bundled. (A missing font
    // makes this wait never finish, hence the timeout.)
    await tester.runAsync(
      () => GoogleFonts.pendingFonts().timeout(const Duration(seconds: 15)),
    );
  });

  test('each font weight the theme uses is in the asset bundle', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final assets = (await AssetManifest.loadFromAssetBundle(
      rootBundle,
    )).listAssets();
    for (final font in [
      'Inter-Regular.ttf',
      'Inter-Medium.ttf',
      'Inter-SemiBold.ttf',
      'PlayfairDisplay-SemiBold.ttf',
    ]) {
      expect(assets, contains('assets/fonts/$font'));
      final bytes = await rootBundle.load('assets/fonts/$font');
      expect(bytes.getUint32(0), 0x00010000, reason: '$font is TrueType');
    }
  });

  test('both font licenses are bundled', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final file in ['OFL-Inter.txt', 'OFL-PlayfairDisplay.txt']) {
      final text = await rootBundle.loadString('assets/fonts/$file');
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
    }
  });
}

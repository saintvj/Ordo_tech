import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app/app.dart';
import 'app/router.dart';
import 'application/gathering_controller.dart';
import 'application/startup.dart';
import 'data/local/app_database.dart';
import 'data/local/local_gathering_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts are bundled in assets/fonts/; never download them.
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(_fontLicenses);

  final repository = LocalGatheringRepository(AppDatabase.open());
  final startup = await loadStartupState(repository);

  final container = ProviderContainer(
    overrides: [
      gatheringRepositoryProvider.overrideWithValue(repository),
      initialLocationProvider.overrideWithValue(startup.initialLocation),
    ],
  );
  final resumed = startup.resumeGathering;
  if (resumed != null) {
    container.read(gatheringProvider.notifier).restore(resumed);
  }
  final issue = startup.issue;
  if (issue != null) {
    container.read(storageIssueProvider.notifier).report(issue);
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const OrdoApp()),
  );
}

/// The bundled fonts' SIL Open Font License texts, for the licenses page.
Stream<LicenseEntry> _fontLicenses() async* {
  for (final (family, file) in [
    ('Inter', 'OFL-Inter.txt'),
    ('Playfair Display', 'OFL-PlayfairDisplay.txt'),
  ]) {
    yield LicenseEntryWithLineBreaks([
      family,
    ], await rootBundle.loadString('assets/fonts/$file'));
  }
}

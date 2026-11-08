import '../app/routes.dart';
import '../data/gathering_repository.dart';
import '../domain/models.dart';

/// What the app should do when it opens, based on what is saved.
class StartupState {
  const StartupState({
    this.resumeGathering,
    this.initialLocation = Routes.home,
    this.issue,
  });

  /// The one unfinished gathering to reopen, if there is exactly one.
  final Gathering? resumeGathering;

  /// Where navigation starts. With several unfinished gatherings this is
  /// [Routes.resume], so the user picks one instead of the app guessing.
  final String initialLocation;

  /// A message for the user if saved gatherings couldn't be read.
  final String? issue;
}

/// Reads saved gatherings and decides how the app should start.
///
/// - No unfinished gathering: start at Home.
/// - Exactly one: reopen it; the router then shows its current stage.
/// - Several: start at the resume picker.
///
/// It never writes, so opening the app can't create or duplicate a
/// gathering. Any read error starts the app at Home with [StartupState.issue]
/// set rather than failing to open.
Future<StartupState> loadStartupState(GatheringRepository repository) async {
  try {
    final listing = await repository.listUnfinished();
    final unfinished = listing.gatherings;
    final issue = listing.hasUnreadable ? unreadableMessage(listing) : null;
    if (unfinished.length > 1) {
      return StartupState(initialLocation: Routes.resume, issue: issue);
    }
    if (unfinished.length == 1) {
      final gathering = await repository.load(unfinished.single.id);
      if (gathering != null) {
        return StartupState(resumeGathering: gathering, issue: issue);
      }
    }
    return StartupState(issue: issue);
  } catch (_) {
    return const StartupState(
      issue: "Ordo couldn't open your saved gatherings.",
    );
  }
}

/// Tells the user some saved gatherings were skipped because they couldn't
/// be read. (They are left untouched in storage.)
String unreadableMessage(GatheringList listing) {
  final n = listing.unreadableIds.length;
  return n == 1
      ? "1 saved gathering couldn't be read and isn't shown."
      : "$n saved gatherings couldn't be read and aren't shown.";
}

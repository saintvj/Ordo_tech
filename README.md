# Ordo

**Offline-first, pass-and-play dining companion for Android.**

One phone goes around the table: the host sets up a gathering, each person adds
their order, a waiter mode tracks what's served, and Ordo produces an itemised,
splittable bill you can settle and share — all with no account and no network.

## Current functionality

- Create a gathering and build a menu by hand, or **scan a menu photo** (a
  Gemini-powered proof of concept via a local proxy).
- Collect per-participant orders and track serving progress.
- **Configurable bill:** CGST/SGST, service charge, flat discount, and
  tax-inclusive or tax-exclusive pricing.
- **Two split modes:** *pay as you eat* (proportional shared charges) and
  *split equally* (every participant by default, with explicit exclusion).
- All money in integer paise; participant totals always sum exactly to the bill.
- **Paid/pending settlement** per participant, preserved across restarts.
- **Export** the bill as plain text or PDF through the **native Android share
  sheet**.
- Fully offline, no sign-in; session history stored locally.

## Tech stack

Flutter · Riverpod · go_router · Drift/SQLite · Node.js/Express proxy · Gemini
API (scanner only) · `pdf` + `printing` + `share_plus` for export.

## Quick setup

```bash
git clone https://github.com/saintvj/Ordo_tech.git
cd Ordo_tech
flutter pub get
flutter run            # with an Android device or emulator connected
```

The menu scanner additionally needs the local proxy running
(`tools/menu-scanner-proxy`) and an adb reverse tunnel — see the handover guide.

## Tests

```bash
flutter analyze
flutter test
cd tools/menu-scanner-proxy && npm test
```

## Documentation

Full setup, architecture, billing/database details, limitations, roadmap and
AI-agent guidelines are in **[docs/PROJECT_HANDOVER.md](docs/PROJECT_HANDOVER.md)**.

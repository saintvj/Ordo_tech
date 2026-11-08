# Architecture Guidelines

## Offline-First Philosophy
Ordo is designed to be a completely offline, single-device app. Every gathering is saved on the device (SQLite via Drift) as it changes, so it survives the app closing, process death and restarts. No backend, no accounts, and no authentication are present in the core flow.

## Folder Organization
We use a feature-based folder structure designed around the linear session flow:
- **`app/`**: Bootstrapping and routing (`app.dart`, `router.dart`).
- **`core/`**: Themes, constants, and utilities.
- **`features/session_flow/`**: All screens representing the step-by-step pass-and-play flow.
- **`domain/`**: Immutable domain models (`models.dart`), money helpers (`money.dart`) and the starter `temporaryMenu`.
- **`application/`**: `GatheringController`, a Riverpod `Notifier` that owns the active gathering and enforces its lifecycle.
- **`data/`**: `GatheringRepository` (the storage interface) and `data/local/`, its Drift implementation. Only `data/local/` touches database tables.
- **`features/history/`**: Session history, the read-only past-gathering view and the resume picker.
- **`shared/`**: Shared widgets and extensions.

## Modular Plugin Architecture
The application is designed so that future features (modules) can be plugged in without disrupting the core offline flow. 

**Future Modules (DO NOT IMPLEMENT CURRENTLY)**:
- **Menu Scan (OCR + AI)**: Will replace the hardcoded mock menu.
- **Billing & Payments**: Will calculate totals and handle split bills after the Session Summary.
- **Multi-device Sync**: Will allow multiple phones to connect over Bluetooth/Local WiFi.
- **QR Sharing**: Will let users join a session via QR.
- **Restaurant Integration & Notifications**: Will allow sending the final order directly to a venue's POS.

## Core Domain Models
All models are immutable. Screens never mutate them; they call `GatheringController` methods, which replace the state.
- **Gathering**: Owns `id`, `createdAt`, gathering/restaurant/host names, `status`, `menu`, `participants` and `orderLines`.
- **GatheringStatus**: `menuDraft → ordering → serving → completed`. Completed gatherings are read-only and only appear in history. Each controller action is allowed in exactly one status and throws `StateError` otherwise.
- **Menu / MenuCategory / MenuItem**: The gathering's own menu. Prices are integer paise (`pricePaise`).
- **Participant**: Created together with their first confirmed order, never before.
- **OrderLine**: One item ordered by one participant, with `quantity` and `servedQuantity`. The item name and unit price are copied when the order is placed.

Money is always integer paise. Use `formatRupees`, `parseRupees` and `percentOf` from `domain/money.dart`; never use `double` for amounts.

## Menu Architecture & Sources
The ordering screens consume `Menu` and `MenuItem` objects without knowing where they originated. This separation allows future menu sources to plug into the single `Menu` model. 

Future architecture conceptualization:
```text
MenuSource
 ├── ManualMenuSource (Implemented)
 ├── OCRMenuSource (Future)
 ├── AIMenuSource (Future)
 └── RestaurantMenuSource (Future)
```
All of these will eventually map down to the same unified `Menu` domain object.

## Waiter Mode Organization
The Waiter Mode groups data strictly by **MenuItem** rather than by participant. This allows the host to quickly see how many of each item were ordered and tick them off as they are served to the respective participants.

## Persistence
- **Repository**: the controller saves through `gatheringRepositoryProvider` (`GatheringRepository`). `main.dart` provides `LocalGatheringRepository`; tests default to `InMemoryGatheringRepository`. A future Firestore repository implements the same interface.
- **Saving**: every controller change calls `_update`, which sets state and queues a save. Saves run one at a time in order. A failed save is shown to the user; the in-memory state is kept.
- **Snapshots**: a save replaces all of a gathering's rows in one transaction, so storage always holds one complete state. Completed gatherings refuse further saves.
- **Tables**: `gatherings`; `menu_categories` and `menu_items` keyed by `(gathering_id, id)` so every gathering has its own menu; `participants`; `order_lines` (with the name/price snapshot, no foreign key to the menu). Child tables cascade from `gatherings`. Money is integer paise, enforced by CHECK constraints.
- **Start-up**: `loadStartupState` reads (never writes). One unfinished gathering is reopened and the router shows its stage; several open the resume picker; none or a read error start at Home.
- **Schema changes**: bump `schemaVersion`, run `dart run drift_dev make-migrations` (exports `drift_schemas/` and generates step and test scaffolding), add the step in `onUpgrade`. Steps must not drop user data. An unknown version (e.g. a downgrade) refuses to open rather than guessing.

## Navigation
Routing uses go_router (`lib/app/router.dart`, paths in `lib/app/routes.dart`). Screens read state from `gatheringProvider`; routes carry only small typed `*Args` objects in `extra`, never a gathering.
- **Lifecycle redirect**: every navigation runs `_redirectForLifecycle`. With no gathering, only Home, Create Gathering and Menu Selection are reachable. Otherwise only the current stage's routes are reachable (menuDraft: Edit Menu; ordering: Participant Name, Participant Order, Pass Phone, Review Orders; serving: Waiter Mode, Session Summary, Bill Summary), and anything else redirects to that stage's entry point.
- **Refresh**: the router re-runs the redirect when the gathering's status changes, so `confirmMenu()`, `startServing()` and `closeGathering()` move the user on their own. Other edits don't refresh the router.
- **Back stack**: stage changes and the pass-and-play cycle use `go`, which replaces history, so the stack doesn't grow with participants. Edits from Review Orders, Review Orders from Pass Phone, and the screens after Waiter Mode use `push`, so back returns to the previous screen.

## State Management & Boundaries
- **State**: The active gathering lives in `gatheringProvider`. Screens `ref.watch` it and call the controller; routes carry no session objects.
- **Menu Locking**: `confirmMenu()` moves the gathering to `ordering`. Menu edits are rejected from then on, and the first participant's screen blocks back navigation to the editor.
- **Order Editing**: `ParticipantOrderScreen` keeps quantities locally and commits them on "Confirm Order" / "Save Changes" via `addParticipantWithOrder` or `replaceOrder`. Backing out commits nothing. Saving an empty order removes the participant.
- **Waiter Mode Boundary**: `startServing()` moves the gathering to `serving` and clears the ordering screens from the back stack. Order changes are rejected from then on.

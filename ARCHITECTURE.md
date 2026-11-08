# Architecture Guidelines

## Offline-First Philosophy
Ordo is designed to be a completely offline, single-device app. We rely entirely on local, in-memory state or lightweight local storage for the duration of a dining session. No backend, no accounts, and no authentication are present in the core flow.

## Folder Organization
We use a feature-based folder structure designed around the linear session flow:
- **`app/`**: Bootstrapping and routing (`app.dart`, `router.dart`).
- **`core/`**: Themes, constants, and utilities.
- **`features/session_flow/`**: All screens representing the step-by-step pass-and-play flow.
- **`shared/`**: Common models (e.g., `Participant`, `OrderItem`) and widgets.

## Modular Plugin Architecture
The application is designed so that future features (modules) can be plugged in without disrupting the core offline flow. 

**Future Modules (DO NOT IMPLEMENT CURRENTLY)**:
- **Menu Scan (OCR + AI)**: Will replace the hardcoded mock menu.
- **Billing & Payments**: Will calculate totals and handle split bills after the Session Summary.
- **Multi-device Sync**: Will allow multiple phones to connect over Bluetooth/Local WiFi.
- **QR Sharing**: Will let users join a session via QR.
- **Restaurant Integration & Notifications**: Will allow sending the final order directly to a venue's POS.

## Core Domain Models
We use a unified `Session` model that owns all state for the current dining session:
- **Session**: Owns `sessionId`, `createdAt`, `participants`, `menu`, `orders`, and `servingStatus`.
- **Menu**: The session's menu containing a list of `MenuCategory`.
- **MenuCategory**: A named category containing a list of `MenuItem`.
- **Participant**: Name and ID of a person in the session.
- **MenuItem**: Available items to order, consisting of `id`, `name`, and `price`.
- **OrderItem**: An item ordered by a specific participant. Includes an `isServed` boolean.

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

## State Management & Boundaries
- **Menu Locking**: Once the first participant begins ordering, the session menu should be treated as locked for this session to prevent items or prices from changing underneath existing orders.
- **Order Editing**: Orders are maintained in local state during the `ParticipantOrderScreen` editing process. Changes are only committed to the `Session` upon pressing "Confirm Order" or "Save Changes". This prevents ghost orders if a user backs out.
- **Waiter Mode Boundary**: The transition from `ReviewOrdersScreen` to `WaiterModeScreen` represents the strict boundary between DRAFT ORDERING and SERVING. Once in Waiter Mode, the order list becomes the definitive serving source.

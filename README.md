# Ordo

**Offline-First Dining Session Organizer**

## Project Overview
Ordo is an offline-first pass-and-play dining companion that lets one person collect everyone's orders on a single phone and helps the waiter serve food accurately.

## Vision
To create a seamless, completely offline pass-and-play experience for group dining. The app operates without accounts, without the internet, and without a backend—ensuring total privacy and immediate usability. All data is stored locally within a unified `Session` model for the current dining session.

## How to Run
1. Ensure you have [Flutter](https://flutter.dev/) installed.
2. Clone this repository.
3. Run `flutter pub get` to install dependencies.
4. Run `flutter run` to launch the app on your connected Android device or emulator.

## Folder Structure
Our project follows a modular feature architecture. Currently, it focuses entirely on the `session_flow`:
- `lib/app`: App root, initialization, and routing.
- `lib/core`: Core configurations, constants, services, and theme.
- `lib/features/session_flow`: The pass-and-play wizard flow (home -> menu editor -> participant name -> order -> pass phone -> review orders & edit -> waiter mode -> summary).
- `lib/shared/models`: Unified domain models like `Session`, `Participant`, `Menu`, `MenuCategory`, `MenuItem`, and `OrderItem`.
- `lib/shared/widgets`: Shared UI components.

## Development Workflow
- Follow the predefined folder structure.
- Use Material 3 for all UI components.
- Do not add unnecessary dependencies or state management packages for the MVP. Pass state through arguments or local providers.
- Maintain the modular plugin architecture described in `ARCHITECTURE.md`.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ordo/app/routes.dart';
import 'package:ordo/application/gathering_controller.dart';
import 'package:ordo/data/menu_scanner.dart';
import 'package:ordo/domain/models.dart';
import 'package:ordo/domain/scanned_menu.dart';
import 'package:ordo/domain/temporary_menu.dart';
import 'package:ordo/features/menu_scanner/menu_scanner_screen.dart';

void main() {
  group('MenuScanResult parsing tests', () {
    test('parses full structured menu scan JSON correctly', () {
      final json = {
        'categories': [
          {
            'name': 'Pizza World',
            'items': [
              {
                'name': 'Capsicum Onion Pizza',
                'description': 'Fresh capsicum with sliced red onion',
                'variants': [
                  {'name': '6 inch', 'price': 90},
                  {'name': '10 inch', 'price': 150},
                ],
                'vegetarian_status': 'vegetarian',
                'add_ons': ['Extra Cheese'],
                'confidence': 'high',
                'needs_review': false,
              },
              {
                'name': 'Special Garlic Bread',
                'description': null,
                'variants': [
                  {'name': 'Regular', 'price': null},
                ],
                'vegetarian_status': 'unknown',
                'add_ons': [],
                'confidence': 'medium',
                'needs_review': false,
              },
            ],
          },
        ],
        'warnings': ['Lighting was uneven in top-right corner.'],
        'unreadable_text': ['Chef ... Today'],
      };

      final result = MenuScanResult.fromJson(json);

      expect(result.categories.length, 1);
      expect(result.categories.first.name, 'Pizza World');
      expect(result.categories.first.items.length, 2);

      final pizza = result.categories.first.items[0];
      expect(pizza.name, 'Capsicum Onion Pizza');
      expect(pizza.description, 'Fresh capsicum with sliced red onion');
      expect(pizza.variants.length, 2);
      expect(pizza.variants[0].name, '6 inch');
      expect(pizza.variants[0].price, 90.0);
      expect(pizza.variants[0].formattedPrice, '90');
      expect(pizza.variants[1].name, '10 inch');
      expect(pizza.variants[1].price, 150.0);
      expect(pizza.vegetarianStatus, 'vegetarian');
      expect(pizza.addOns, ['Extra Cheese']);
      expect(pizza.confidence, 'high');
      expect(pizza.needsReview, false);

      final bread = result.categories.first.items[1];
      expect(bread.name, 'Special Garlic Bread');
      expect(bread.variants.length, 1);
      expect(bread.variants[0].name, 'Regular');
      expect(bread.variants[0].price, null);
      expect(bread.variants[0].formattedPrice, '—');
      // Should automatically flag for review since price is null
      expect(bread.needsReview, true);

      expect(result.warnings, ['Lighting was uneven in top-right corner.']);
      expect(result.unreadableText, ['Chef ... Today']);
      expect(result.totalItemCount, 2);
      expect(result.itemsNeedingReviewCount, 1);
    });

    test('handles missing or empty variants by falling back to Regular', () {
      final json = {
        'categories': [
          {
            'name': 'Beverages',
            'items': [
              {
                'name': 'Mineral Water',
                'variants': [],
                'vegetarian_status': 'vegetarian',
                'confidence': 'high',
                'needs_review': false,
              },
            ],
          },
        ],
        'warnings': [],
        'unreadable_text': [],
      };

      final result = MenuScanResult.fromJson(json);
      expect(result.categories.length, 1);
      final item = result.categories.first.items.first;
      expect(item.variants.length, 1);
      expect(item.variants.first.name, 'Regular');
      expect(item.variants.first.price, null);
      expect(item.needsReview, true);
    });

    test('flags item for review when confidence is low', () {
      final json = {
        'categories': [
          {
            'name': 'Snacks',
            'items': [
              {
                'name': 'Samosa',
                'variants': [
                  {'name': 'Regular', 'price': 20},
                ],
                'vegetarian_status': 'vegetarian',
                'confidence': 'low',
                'needs_review': false,
              },
            ],
          },
        ],
      };

      final result = MenuScanResult.fromJson(json);
      expect(result.categories.first.items.first.needsReview, true);
    });
  });

  group('LocalGeminiMenuScanner API client tests', () {
    test('successful scan parses and returns MenuScanResult', () async {
      final mockData = {
        'categories': [
          {
            'name': 'Starters',
            'items': [
              {
                'name': 'Tomato Soup',
                'variants': [
                  {'name': 'Regular', 'price': 80},
                ],
                'vegetarian_status': 'vegetarian',
                'confidence': 'high',
                'needs_review': false,
              },
            ],
          },
        ],
        'warnings': [],
        'unreadable_text': [],
      };

      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/menu/scan');
        expect(request.method, 'POST');
        return http.Response(
          jsonEncode({'success': true, 'data': mockData}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final scanner = LocalGeminiMenuScanner(
        baseUrl: 'http://127.0.0.1:8787',
        client: mockClient,
      );

      final result = await scanner.scanMenu(
        imageBytes: [1, 2, 3],
        filename: 'menu.jpg',
        mimeType: 'image/jpeg',
      );

      expect(result.categories.length, 1);
      expect(result.categories.first.name, 'Starters');
      expect(result.categories.first.items.first.name, 'Tomato Soup');
      expect(result.categories.first.items.first.variants.first.price, 80.0);
    });

    test('handles 400 Bad Request error from proxy', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': 'Unsupported image type "text/plain".',
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      final scanner = LocalGeminiMenuScanner(
        baseUrl: 'http://127.0.0.1:8787',
        client: mockClient,
      );

      expect(
        () => scanner.scanMenu(
          imageBytes: [1, 2, 3],
          filename: 'test.txt',
          mimeType: 'text/plain',
        ),
        throwsA(
          isA<MenuScanException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported image type'),
          ),
        ),
      );
    });

    test('handles 500 missing API key error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': 'GEMINI_API_KEY is not configured on the server.',
          }),
          500,
          headers: {'content-type': 'application/json'},
        );
      });

      final scanner = LocalGeminiMenuScanner(
        baseUrl: 'http://127.0.0.1:8787',
        client: mockClient,
      );

      expect(
        () => scanner.scanMenu(
          imageBytes: [1, 2, 3],
          filename: 'menu.jpg',
          mimeType: 'image/jpeg',
        ),
        throwsA(
          isA<MenuScanException>().having(
            (e) => e.message,
            'message',
            contains('GEMINI_API_KEY is not configured'),
          ),
        ),
      );
    });

    test('handles 502 malformed Gemini error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': 'Gemini output failed schema validation',
          }),
          502,
          headers: {'content-type': 'application/json'},
        );
      });

      final scanner = LocalGeminiMenuScanner(
        baseUrl: 'http://127.0.0.1:8787',
        client: mockClient,
      );

      expect(
        () => scanner.scanMenu(
          imageBytes: [1, 2, 3],
          filename: 'menu.jpg',
          mimeType: 'image/jpeg',
        ),
        throwsA(
          isA<MenuScanException>().having(
            (e) => e.message,
            'message',
            contains('failed schema validation'),
          ),
        ),
      );
    });
  });

  group('MenuScannerScreen Widget tests', () {
    testWidgets('renders initial upload prompt', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MenuScannerScreen())),
      );

      expect(find.text('Scan Menu'), findsOneWidget);
      expect(find.text('Select a Restaurant Menu Photograph'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
    });

    testWidgets('displays scan results and flagged items on success', (
      tester,
    ) async {
      final testResult = MenuScanResult(
        categories: [
          ScannedCategory(
            name: 'Pizza World',
            items: [
              ScannedMenuItem(
                name: 'Capsicum Pizza',
                variants: [
                  const ScannedVariant(name: '6 inch', price: 90),
                  const ScannedVariant(name: '10 inch', price: 150),
                ],
                vegetarianStatus: 'vegetarian',
                confidence: 'high',
                needsReview: false,
              ),
              ScannedMenuItem(
                name: 'Unknown Dish',
                variants: [const ScannedVariant(name: 'Regular', price: null)],
                vegetarianStatus: 'unknown',
                confidence: 'low',
                needsReview: true,
              ),
            ],
          ),
        ],
        warnings: ['Poor lighting'],
      );

      final container = ProviderContainer(
        overrides: [
          menuScannerControllerProvider.overrideWith(
            () => _PreloadedNotifier(MenuScannerSuccess(testResult)),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MenuScannerScreen()),
        ),
      );

      expect(find.text('Review & Edit Menu'), findsOneWidget);
      expect(find.text('Pizza World'), findsOneWidget);
      expect(find.text('Capsicum Pizza'), findsOneWidget);
      expect(find.text('6 inch: ₹90'), findsOneWidget);
      expect(find.text('10 inch: ₹150'), findsOneWidget);
      expect(find.text('Unknown Dish'), findsOneWidget);
      expect(find.text('Regular: Missing Price'), findsOneWidget);
      expect(find.text('Price Missing'), findsOneWidget);
      expect(
        find.text('1 dish(es) flagged with missing prices or low confidence.'),
        findsOneWidget,
      );
      expect(find.text('Confirm & Import Menu'), findsOneWidget);
    });

    testWidgets('allows editing category name', (tester) async {
      final testResult = MenuScanResult(
        categories: [
          ScannedCategory(
            name: 'Old Category',
            items: [
              ScannedMenuItem(
                name: 'Item 1',
                variants: [const ScannedVariant(name: 'Regular', price: 100)],
              ),
            ],
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          menuScannerControllerProvider.overrideWith(
            () => _PreloadedNotifier(MenuScannerSuccess(testResult)),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MenuScannerScreen()),
        ),
      );

      expect(find.text('Old Category'), findsOneWidget);

      await tester.tap(find.byTooltip('Rename category'));
      await tester.pumpAndSettle();

      expect(find.text('Rename Category'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'New Category Name');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('New Category Name'), findsOneWidget);
      expect(find.text('Old Category'), findsNothing);
    });

    testWidgets('allows editing dish name and price', (tester) async {
      final testResult = MenuScanResult(
        categories: [
          ScannedCategory(
            name: 'Starters',
            items: [
              ScannedMenuItem(
                name: 'Veg Soup',
                variants: [const ScannedVariant(name: 'Regular', price: 70)],
              ),
            ],
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          menuScannerControllerProvider.overrideWith(
            () => _PreloadedNotifier(MenuScannerSuccess(testResult)),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MenuScannerScreen()),
        ),
      );

      expect(find.text('Veg Soup'), findsOneWidget);
      expect(find.text('Regular: ₹70'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('edit-dish-button-0_0')),
        50,
      );
      await tester.tap(find.byKey(const Key('edit-dish-button-0_0')));
      await tester.pumpAndSettle();

      expect(find.text('Edit Dish'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('dish-name-field')),
        'Hot & Sour Soup',
      );
      await tester.enterText(find.byKey(const Key('variant-price-0')), '95');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Hot & Sour Soup'), findsOneWidget);
      expect(find.text('Regular: ₹95'), findsOneWidget);
    });

    testWidgets('allows deleting a dish and adding a missing dish', (
      tester,
    ) async {
      final testResult = MenuScanResult(
        categories: [
          ScannedCategory(
            name: 'Main Course',
            items: [
              ScannedMenuItem(
                name: 'Delete Me',
                variants: [const ScannedVariant(name: 'Regular', price: 50)],
              ),
            ],
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          menuScannerControllerProvider.overrideWith(
            () => _PreloadedNotifier(MenuScannerSuccess(testResult)),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MenuScannerScreen()),
        ),
      );

      expect(find.text('Delete Me'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('delete-dish-button-0_0')),
        50,
      );
      await tester.tap(find.byKey(const Key('delete-dish-button-0_0')));
      await tester.pumpAndSettle();
      expect(find.text('Delete Me'), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const Key('add-dish-button-0')),
        50,
      );
      await tester.tap(find.byKey(const Key('add-dish-button-0')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('dish-name-field')),
        'Paneer Tikka',
      );
      await tester.enterText(find.byKey(const Key('variant-price-0')), '180');
      await tester.tap(find.text('Add Dish').last);
      await tester.pumpAndSettle();

      expect(find.text('Paneer Tikka'), findsOneWidget);
      expect(find.text('Regular: ₹180'), findsOneWidget);
    });

    testWidgets('Confirm & Import starts gathering with GatheringDetailsArgs', (
      tester,
    ) async {
      final testResult = MenuScanResult(
        categories: [
          ScannedCategory(
            name: 'Beverages',
            items: [
              ScannedMenuItem(
                name: 'Chai',
                variants: [const ScannedVariant(name: 'Regular', price: 20)],
              ),
            ],
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          menuScannerControllerProvider.overrideWith(
            () => _PreloadedNotifier(MenuScannerSuccess(testResult)),
          ),
        ],
      );

      const details = GatheringDetailsArgs(
        gatheringName: 'Team Chai Break',
        restaurantName: 'Chai Point',
        hostName: 'Alice',
      );

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const MenuScannerScreen(details: details),
          ),
          GoRoute(
            path: Routes.editMenu,
            builder: (context, state) =>
                const Scaffold(body: Text('EditMenuPage')),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      expect(find.byKey(const Key('confirm-import-button')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('confirm-import-button')),
        100,
      );
      await tester.tap(find.byKey(const Key('confirm-import-button')));
      await tester.pumpAndSettle();

      final gathering = container.read(gatheringProvider);
      expect(gathering, isNotNull);
      expect(gathering!.name, 'Team Chai Break');
      expect(gathering.restaurantName, 'Chai Point');
      expect(gathering.hostName, 'Alice');
      expect(gathering.status, GatheringStatus.menuDraft);
      expect(gathering.menu.categories.length, 1);
      expect(gathering.menu.categories.first.name, 'Beverages');
      expect(gathering.menu.categories.first.items.first.name, 'Chai');
      expect(gathering.menu.categories.first.items.first.pricePaise, 2000);
    });

    testWidgets('displays error message and retry button on failure', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          menuScannerControllerProvider.overrideWith(
            () => _PreloadedNotifier(
              const MenuScannerFailure(
                'GEMINI_API_KEY is not configured on the server.',
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MenuScannerScreen()),
        ),
      );

      expect(find.text('Scan Failed'), findsOneWidget);
      expect(
        find.text('GEMINI_API_KEY is not configured on the server.'),
        findsOneWidget,
      );
      expect(find.text('Retry Scan'), findsOneWidget);
    });
  });

  group('MenuScanResult domain conversion & validation tests', () {
    test(
      'flattens multiple variants into distinct MenuItems with variant suffix',
      () {
        final scanResult = MenuScanResult(
          categories: [
            ScannedCategory(
              id: 'cat-1',
              name: 'Pizzas',
              items: [
                ScannedMenuItem(
                  id: 'item-1',
                  name: 'Margherita Pizza',
                  variants: [
                    const ScannedVariant(name: '6 inch', price: 90),
                    const ScannedVariant(name: '10 inch', price: 150),
                  ],
                ),
              ],
            ),
          ],
        );

        final domainMenu = scanResult.toDomainMenu();
        expect(domainMenu.categories.length, 1);
        final cat = domainMenu.categories.first;
        expect(cat.name, 'Pizzas');
        expect(cat.items.length, 2);

        expect(cat.items[0].name, 'Margherita Pizza (6 inch)');
        expect(cat.items[0].pricePaise, 9000);

        expect(cat.items[1].name, 'Margherita Pizza (10 inch)');
        expect(cat.items[1].pricePaise, 15000);
      },
    );

    test(
      'preserves simple item name when only one generic Regular variant is present',
      () {
        final scanResult = MenuScanResult(
          categories: [
            ScannedCategory(
              id: 'cat-1',
              name: 'South Indian',
              items: [
                ScannedMenuItem(
                  id: 'item-1',
                  name: 'Masala Dosa',
                  variants: [
                    const ScannedVariant(name: 'Regular', price: 80.5),
                  ],
                ),
              ],
            ),
          ],
        );

        final domainMenu = scanResult.toDomainMenu();
        expect(domainMenu.categories.first.items.first.name, 'Masala Dosa');
        expect(domainMenu.categories.first.items.first.pricePaise, 8050);
      },
    );

    test('validateForImport flags missing categories, dishes, or prices', () {
      const emptyResult = MenuScanResult(categories: []);
      expect(
        emptyResult.validateForImport(),
        contains('The menu must have at least one category.'),
      );

      final unpricedResult = MenuScanResult(
        categories: [
          ScannedCategory(
            name: 'Beverages',
            items: [
              ScannedMenuItem(
                name: 'Filter Coffee',
                variants: [const ScannedVariant(name: 'Regular', price: null)],
              ),
            ],
          ),
        ],
      );
      final issues = unpricedResult.validateForImport();
      expect(issues.any((i) => i.contains('missing a valid price')), isTrue);
      expect(() => unpricedResult.toDomainMenu(), throwsA(isA<StateError>()));
    });

    test('preserves temporaryMenu and domain model consistency', () {
      expect(temporaryMenu.categories.isNotEmpty, isTrue);
      expect(temporaryMenu.hasItems, isTrue);
      expect(temporaryMenu.findItem('m1')?.name, 'Idli');
      expect(temporaryMenu.findItem('m1')?.pricePaise, 5000);
    });
  });
}

class _PreloadedNotifier extends MenuScannerNotifier {
  _PreloadedNotifier(this._initialState);
  final MenuScannerState _initialState;

  @override
  MenuScannerState build() => _initialState;
}

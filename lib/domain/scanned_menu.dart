import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();

/// The result returned by a menu scanner containing parsed categories,
/// items, variants, prices, and any warnings.
@immutable
class MenuScanResult {
  const MenuScanResult({
    required this.categories,
    this.warnings = const [],
    this.unreadableText = const [],
  });

  factory MenuScanResult.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'];
    final categories = <ScannedCategory>[];
    if (rawCategories is List) {
      for (final cat in rawCategories) {
        if (cat is Map<String, dynamic>) {
          categories.add(ScannedCategory.fromJson(cat));
        }
      }
    }

    final warnings = <String>[];
    if (json['warnings'] is List) {
      for (final w in json['warnings'] as List) {
        warnings.add(w.toString());
      }
    }

    final unreadable = <String>[];
    if (json['unreadable_text'] is List) {
      for (final u in json['unreadable_text'] as List) {
        unreadable.add(u.toString());
      }
    }

    return MenuScanResult(
      categories: List.unmodifiable(categories),
      warnings: List.unmodifiable(warnings),
      unreadableText: List.unmodifiable(unreadable),
    );
  }

  final List<ScannedCategory> categories;
  final List<String> warnings;
  final List<String> unreadableText;

  int get totalItemCount =>
      categories.fold(0, (sum, cat) => sum + cat.items.length);

  int get itemsNeedingReviewCount => categories.fold(
    0,
    (sum, cat) => sum + cat.items.where((item) => item.needsReview).length,
  );

  MenuScanResult copyWith({
    List<ScannedCategory>? categories,
    List<String>? warnings,
    List<String>? unreadableText,
  }) {
    return MenuScanResult(
      categories: categories ?? this.categories,
      warnings: warnings ?? this.warnings,
      unreadableText: unreadableText ?? this.unreadableText,
    );
  }

  /// Validates whether this menu is ready to be imported into Ordo.
  /// Returns a list of human-readable issues, or an empty list if valid.
  List<String> validateForImport() {
    final issues = <String>[];
    if (categories.isEmpty) {
      issues.add('The menu must have at least one category.');
      return issues;
    }
    final allItems = categories.expand((c) => c.items).toList();
    if (allItems.isEmpty) {
      issues.add('The menu must contain at least one dish.');
      return issues;
    }
    for (final cat in categories) {
      if (cat.name.trim().isEmpty) {
        issues.add('All categories must have a name.');
      }
      for (final item in cat.items) {
        if (item.name.trim().isEmpty) {
          issues.add('All dishes must have a name.');
        }
        if (item.variants.isEmpty) {
          issues.add('Dish "${item.name}" has no price variant.');
        } else {
          for (final variant in item.variants) {
            if (variant.price == null || variant.price! <= 0) {
              issues.add(
                'Dish "${item.name}" (${variant.name}) is missing a valid price.',
              );
            }
          }
        }
      }
    }
    return issues;
  }

  /// Converts the reviewed menu to Ordo's domain [Menu].
  ///
  /// Multi-variant dishes are flattened into distinct [MenuItem]s with the
  /// variant name appended in parentheses (e.g. "Pizza (6 inch)").
  /// Single-variant items with generic variant names ("Regular", "Default")
  /// preserve the dish's base name.
  /// All prices are converted from rupees into integer paise (`(price * 100).round()`).
  Menu toDomainMenu({String Function()? idGenerator}) {
    final gen = idGenerator ?? _uuid.v4;
    final issues = validateForImport();
    if (issues.isNotEmpty) {
      throw StateError('Cannot import invalid menu: ${issues.join("; ")}');
    }

    final domainCategories = <MenuCategory>[];

    for (final cat in categories) {
      final domainItems = <MenuItem>[];
      for (final item in cat.items) {
        if (item.variants.length == 1) {
          final variant = item.variants.first;
          final paise = (variant.price! * 100).round();
          final isGeneric =
              variant.name.trim().toLowerCase() == 'regular' ||
              variant.name.trim().toLowerCase() == 'default' ||
              variant.name.trim().isEmpty;
          final displayName = isGeneric
              ? item.name.trim()
              : '${item.name.trim()} (${variant.name.trim()})';
          domainItems.add(
            MenuItem(id: gen(), name: displayName, pricePaise: paise),
          );
        } else {
          for (final variant in item.variants) {
            final paise = (variant.price! * 100).round();
            domainItems.add(
              MenuItem(
                id: gen(),
                name: '${item.name.trim()} (${variant.name.trim()})',
                pricePaise: paise,
              ),
            );
          }
        }
      }
      domainCategories.add(
        MenuCategory(
          id: gen(),
          name: cat.name.trim(),
          items: List.unmodifiable(domainItems),
        ),
      );
    }

    return Menu(categories: List.unmodifiable(domainCategories));
  }
}

@immutable
class ScannedCategory {
  ScannedCategory({String? id, required this.name, required this.items})
    : id = id ?? _uuid.v4();

  factory ScannedCategory.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? 'General';
    final items = <ScannedMenuItem>[];
    final rawItems = json['items'];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          items.add(ScannedMenuItem.fromJson(item));
        }
      }
    }
    return ScannedCategory(
      name: name.isEmpty ? 'General' : name,
      items: List.unmodifiable(items),
    );
  }

  final String id;
  final String name;
  final List<ScannedMenuItem> items;

  ScannedCategory copyWith({
    String? id,
    String? name,
    List<ScannedMenuItem>? items,
  }) {
    return ScannedCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      items: items ?? this.items,
    );
  }
}

@immutable
class ScannedMenuItem {
  ScannedMenuItem({
    String? id,
    required this.name,
    this.description,
    required this.variants,
    this.vegetarianStatus = 'unknown',
    this.addOns = const [],
    this.confidence = 'medium',
    this.needsReview = false,
  }) : id = id ?? _uuid.v4();

  factory ScannedMenuItem.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? 'Unnamed Item';
    final desc = json['description']?.toString().trim();

    final variants = <ScannedVariant>[];
    final rawVariants = json['variants'];
    if (rawVariants is List && rawVariants.isNotEmpty) {
      for (final v in rawVariants) {
        if (v is Map<String, dynamic>) {
          variants.add(ScannedVariant.fromJson(v));
        }
      }
    }
    if (variants.isEmpty) {
      variants.add(const ScannedVariant(name: 'Regular', price: null));
    }

    final addOns = <String>[];
    if (json['add_ons'] is List) {
      for (final a in json['add_ons'] as List) {
        addOns.add(a.toString());
      }
    }

    final confidence =
        json['confidence']?.toString().toLowerCase().trim() ?? 'medium';
    final vegStatus =
        json['vegetarian_status']?.toString().toLowerCase().trim() ?? 'unknown';

    final needsReview =
        json['needs_review'] == true ||
        confidence == 'low' ||
        variants.any((v) => v.price == null);

    return ScannedMenuItem(
      name: name,
      description: desc?.isEmpty == true ? null : desc,
      variants: List.unmodifiable(variants),
      vegetarianStatus: vegStatus,
      addOns: List.unmodifiable(addOns),
      confidence: confidence,
      needsReview: needsReview,
    );
  }

  final String id;
  final String name;
  final String? description;
  final List<ScannedVariant> variants;
  final String vegetarianStatus;
  final List<String> addOns;
  final String confidence;
  final bool needsReview;

  ScannedMenuItem copyWith({
    String? id,
    String? name,
    String? description,
    List<ScannedVariant>? variants,
    String? vegetarianStatus,
    List<String>? addOns,
    String? confidence,
    bool? needsReview,
  }) {
    return ScannedMenuItem(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      variants: variants ?? this.variants,
      vegetarianStatus: vegetarianStatus ?? this.vegetarianStatus,
      addOns: addOns ?? this.addOns,
      confidence: confidence ?? this.confidence,
      needsReview: needsReview ?? this.needsReview,
    );
  }
}

@immutable
class ScannedVariant {
  const ScannedVariant({this.id, required this.name, this.price});

  factory ScannedVariant.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? 'Regular';
    final rawPrice = json['price'];
    double? price;
    if (rawPrice is num) {
      price = rawPrice.toDouble();
    } else if (rawPrice is String && rawPrice.isNotEmpty) {
      final sanitized = rawPrice.replaceAll(RegExp(r'[^0-9.]'), '');
      price = double.tryParse(sanitized);
    }

    return ScannedVariant(name: name.isEmpty ? 'Regular' : name, price: price);
  }

  final String? id;
  final String name;
  final double? price;

  String get formattedPrice =>
      price != null ? price!.toStringAsFixed(price! % 1 == 0 ? 0 : 2) : '—';

  ScannedVariant copyWith({String? id, String? name, double? price}) {
    return ScannedVariant(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
    );
  }
}

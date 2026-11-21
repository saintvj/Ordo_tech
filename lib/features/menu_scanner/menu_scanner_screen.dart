import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/routes.dart';
import '../../application/gathering_controller.dart';
import '../../data/menu_scanner.dart';
import '../../domain/models.dart';
import '../../domain/scanned_menu.dart';

/// State of the menu scanner screen.
sealed class MenuScannerState {
  const MenuScannerState();
}

class MenuScannerInitial extends MenuScannerState {
  const MenuScannerInitial();
}

class MenuScannerLoading extends MenuScannerState {
  const MenuScannerLoading();
}

class MenuScannerSuccess extends MenuScannerState {
  const MenuScannerSuccess(this.result);
  final MenuScanResult result;
}

class MenuScannerFailure extends MenuScannerState {
  const MenuScannerFailure(this.error);
  final String error;
}

class MenuScannerNotifier extends Notifier<MenuScannerState> {
  @override
  MenuScannerState build() => const MenuScannerInitial();

  Future<void> scan({
    required List<int> imageBytes,
    required String filename,
    required String mimeType,
  }) async {
    state = const MenuScannerLoading();
    try {
      final scanner = ref.read(menuScannerProvider);
      final result = await scanner.scanMenu(
        imageBytes: imageBytes,
        filename: filename,
        mimeType: mimeType,
      );
      state = MenuScannerSuccess(result);
    } catch (e) {
      state = MenuScannerFailure(e.toString());
    }
  }

  void reset() {
    state = const MenuScannerInitial();
  }
}

final menuScannerControllerProvider =
    NotifierProvider<MenuScannerNotifier, MenuScannerState>(
      MenuScannerNotifier.new,
    );

/// Screen for selecting a menu photograph, sending it to the local Gemini proxy,
/// reviewing & editing extracted categories, dishes, prices, and variants,
/// and confirming import into the active gathering session.
class MenuScannerScreen extends ConsumerStatefulWidget {
  const MenuScannerScreen({super.key, this.imagePicker, this.details});

  final ImagePicker? imagePicker;
  final GatheringDetailsArgs? details;

  @override
  ConsumerState<MenuScannerScreen> createState() => _MenuScannerScreenState();
}

class _MenuScannerScreenState extends ConsumerState<MenuScannerScreen> {
  Uint8List? _selectedImageBytes;
  String? _selectedFilename;
  String? _selectedMimeType;
  late final ImagePicker _picker;

  /// Local mutable draft of the scanned menu currently being reviewed and edited.
  MenuScanResult? _reviewedMenu;

  @override
  void initState() {
    super.initState();
    _picker = widget.imagePicker ?? ImagePicker();
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final name = file.name.isNotEmpty ? file.name : 'menu_image.jpg';
      final mime = _inferMimeType(name, file.mimeType);

      setState(() {
        _selectedImageBytes = bytes;
        _selectedFilename = name;
        _selectedMimeType = mime;
        _reviewedMenu = null;
      });

      // Reset previous scan results when a new photo is chosen
      ref.read(menuScannerControllerProvider.notifier).reset();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  String _inferMimeType(String filename, String? platformMime) {
    if (platformMime != null && platformMime.contains('/')) {
      return platformMime;
    }
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  void _triggerScan() {
    if (_selectedImageBytes == null ||
        _selectedFilename == null ||
        _selectedMimeType == null) {
      return;
    }
    setState(() {
      _reviewedMenu = null;
    });
    ref
        .read(menuScannerControllerProvider.notifier)
        .scan(
          imageBytes: _selectedImageBytes!,
          filename: _selectedFilename!,
          mimeType: _selectedMimeType!,
        );
  }

  // --- Category Editing Operations ---

  void _showCategoryDialog({int? categoryIndex}) {
    final isNew = categoryIndex == null;
    final initialName = isNew
        ? ''
        : _reviewedMenu!.categories[categoryIndex].name;
    final controller = TextEditingController(text: initialName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isNew ? 'Add Category' : 'Rename Category'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            hintText: 'e.g. Starters, Main Course, Beverages',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  final categories = List<ScannedCategory>.from(
                    _reviewedMenu!.categories,
                  );
                  if (isNew) {
                    categories.add(ScannedCategory(name: name, items: []));
                  } else {
                    categories[categoryIndex] = categories[categoryIndex]
                        .copyWith(name: name);
                  }
                  _reviewedMenu = _reviewedMenu!.copyWith(
                    categories: categories,
                  );
                });
              }
              Navigator.pop(context);
            },
            child: Text(isNew ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }

  void _deleteCategory(int index) {
    setState(() {
      final categories = List<ScannedCategory>.from(_reviewedMenu!.categories);
      categories.removeAt(index);
      _reviewedMenu = _reviewedMenu!.copyWith(categories: categories);
    });
  }

  // --- Dish / Item Editing Operations ---

  void _showItemDialog({required int categoryIndex, int? itemIndex}) {
    final isNew = itemIndex == null;
    final category = _reviewedMenu!.categories[categoryIndex];
    final currentItem = isNew ? null : category.items[itemIndex];

    final nameController = TextEditingController(text: currentItem?.name ?? '');
    final descController = TextEditingController(
      text: currentItem?.description ?? '',
    );

    // Variants state
    final variantsList = isNew
        ? <ScannedVariant>[const ScannedVariant(name: 'Regular', price: null)]
        : List<ScannedVariant>.from(currentItem!.variants);

    String vegStatus = currentItem?.vegetarianStatus ?? 'unknown';
    bool needsReview = currentItem?.needsReview ?? false;
    String? validationError;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isNew ? 'Add Dish' : 'Edit Dish'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('dish-name-field'),
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Dish Name',
                        hintText: 'e.g. Masala Dosa, Paneer Butter Masala',
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('dish-desc-field'),
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'Short description or notes',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: vegStatus,
                      decoration: const InputDecoration(labelText: 'Food Type'),
                      items: const [
                        DropdownMenuItem(
                          value: 'vegetarian',
                          child: Text('Vegetarian'),
                        ),
                        DropdownMenuItem(value: 'vegan', child: Text('Vegan')),
                        DropdownMenuItem(
                          value: 'egg',
                          child: Text('Contains Egg'),
                        ),
                        DropdownMenuItem(
                          value: 'non_vegetarian',
                          child: Text('Non-Vegetarian'),
                        ),
                        DropdownMenuItem(
                          value: 'unknown',
                          child: Text('Not Specified'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => vegStatus = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Prices & Variants',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              variantsList.add(
                                const ScannedVariant(
                                  name: 'Option',
                                  price: null,
                                ),
                              );
                            });
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Variant'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (int vIdx = 0; vIdx < variantsList.length; vIdx++) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                key: Key('variant-name-$vIdx'),
                                initialValue: variantsList[vIdx].name,
                                decoration: const InputDecoration(
                                  labelText: 'Variant / Size',
                                  hintText: 'Regular / Half',
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  variantsList[vIdx] = variantsList[vIdx]
                                      .copyWith(
                                        name: val.trim().isEmpty
                                            ? 'Regular'
                                            : val.trim(),
                                      );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                key: Key('variant-price-$vIdx'),
                                initialValue: variantsList[vIdx].price != null
                                    ? variantsList[vIdx].formattedPrice
                                    : '',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Price (₹)',
                                  hintText: '120',
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  final parsed = double.tryParse(val.trim());
                                  variantsList[vIdx] = variantsList[vIdx]
                                      .copyWith(price: parsed);
                                },
                              ),
                            ),
                            if (variantsList.length > 1)
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                tooltip: 'Remove variant',
                                onPressed: () {
                                  setDialogState(() {
                                    variantsList.removeAt(vIdx);
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: needsReview,
                      title: const Text('Flag for review'),
                      subtitle: const Text('Keeps amber highlight in the list'),
                      onChanged: (val) {
                        setDialogState(() {
                          needsReview = val ?? false;
                        });
                      },
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    setDialogState(() {
                      validationError = 'Please enter a dish name.';
                    });
                    return;
                  }
                  if (variantsList.isEmpty) {
                    setDialogState(() {
                      validationError =
                          'At least one variant/price is required.';
                    });
                    return;
                  }
                  for (final v in variantsList) {
                    if (v.price == null || v.price! <= 0) {
                      setDialogState(() {
                        validationError =
                            'Please provide a valid price above ₹0 for "${v.name}".';
                      });
                      return;
                    }
                  }

                  final desc = descController.text.trim();
                  final updatedItem = ScannedMenuItem(
                    id: currentItem?.id,
                    name: name,
                    description: desc.isNotEmpty ? desc : null,
                    variants: variantsList,
                    vegetarianStatus: vegStatus,
                    needsReview: needsReview,
                    confidence: currentItem?.confidence ?? 'high',
                  );

                  setState(() {
                    final categories = List<ScannedCategory>.from(
                      _reviewedMenu!.categories,
                    );
                    final catItems = List<ScannedMenuItem>.from(
                      categories[categoryIndex].items,
                    );
                    if (isNew) {
                      catItems.add(updatedItem);
                    } else {
                      catItems[itemIndex] = updatedItem;
                    }
                    categories[categoryIndex] = categories[categoryIndex]
                        .copyWith(items: catItems);
                    _reviewedMenu = _reviewedMenu!.copyWith(
                      categories: categories,
                    );
                  });
                  Navigator.pop(dialogCtx);
                },
                child: Text(isNew ? 'Add Dish' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _deleteItem(int categoryIndex, int itemIndex) {
    setState(() {
      final categories = List<ScannedCategory>.from(_reviewedMenu!.categories);
      final catItems = List<ScannedMenuItem>.from(
        categories[categoryIndex].items,
      );
      catItems.removeAt(itemIndex);
      categories[categoryIndex] = categories[categoryIndex].copyWith(
        items: catItems,
      );
      _reviewedMenu = _reviewedMenu!.copyWith(categories: categories);
    });
  }

  // --- Confirm & Import Flow ---

  void _confirmAndImport() {
    if (_reviewedMenu == null) return;

    final issues = _reviewedMenu!.validateForImport();
    if (issues.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              const Text('Menu Needs Attention'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please resolve the following before confirming import:',
              ),
              const SizedBox(height: 12),
              for (final issue in issues.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Expanded(
                        child: Text(
                          issue,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              if (issues.length > 4)
                Text(
                  '+ ${issues.length - 4} more item(s)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Review Items'),
            ),
          ],
        ),
      );
      return;
    }

    final domainMenu = _reviewedMenu!.toDomainMenu();

    if (widget.details != null) {
      // Directly start the gathering with the reviewed menu
      ref
          .read(gatheringProvider.notifier)
          .startGathering(
            name: widget.details!.gatheringName,
            restaurantName: widget.details!.restaurantName,
            hostName: widget.details!.hostName,
            menu: domainMenu,
          );
      context.go(Routes.editMenu);
    } else {
      // Dev mode: ask for quick session details before importing
      _showDevImportDialog(domainMenu);
    }
  }

  void _showDevImportDialog(Menu domainMenu) {
    final gatheringController = TextEditingController();
    final restaurantController = TextEditingController();
    final hostController = TextEditingController();
    String? dialogError;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Start Session with Scanned Menu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: gatheringController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Gathering Name',
                  hintText: 'e.g. Dinner at Spice Route',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: restaurantController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Restaurant Name',
                  hintText: 'e.g. Spice Route',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: hostController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Host Name',
                  hintText: 'e.g. Priya',
                ),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 8),
                Text(
                  dialogError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final gName = gatheringController.text.trim();
                final rName = restaurantController.text.trim();
                final hName = hostController.text.trim();
                if (gName.isEmpty || rName.isEmpty || hName.isEmpty) {
                  setDialogState(
                    () => dialogError = 'Please fill in all fields.',
                  );
                  return;
                }
                ref
                    .read(gatheringProvider.notifier)
                    .startGathering(
                      name: gName,
                      restaurantName: rName,
                      hostName: hName,
                      menu: domainMenu,
                    );
                Navigator.pop(dialogCtx);
                context.go(Routes.editMenu);
              },
              child: const Text('Start Gathering'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scanState = ref.watch(menuScannerControllerProvider);

    // Synchronize scanned result with review draft
    if (scanState is MenuScannerSuccess && _reviewedMenu == null) {
      _reviewedMenu = scanState.result;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _reviewedMenu != null ? 'Review Scanned Menu' : 'Scan Menu',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImageSection(theme),
              const SizedBox(height: 24),
              _buildStatusSection(theme, scanState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection(ThemeData theme) {
    if (_selectedImageBytes == null) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.4),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 36.0, horizontal: 20.0),
          child: Column(
            children: [
              Icon(
                Icons.add_photo_alternate_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Select a Restaurant Menu Photograph',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Supports JPEG, PNG, or WebP up to 10MB.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_library),
                label: const Text('Choose from Gallery'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: Image.memory(
              _selectedImageBytes!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 140,
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: Text('Could not render image preview'),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Change Photo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _triggerScan,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Scan Menu'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection(ThemeData theme, MenuScannerState scanState) {
    return switch (scanState) {
      MenuScannerInitial() => const SizedBox.shrink(),
      MenuScannerLoading() => Card(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                'Extracting menu with Gemini...',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Sending image to local proxy on 127.0.0.1:8787',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
      MenuScannerFailure(:final error) => Card(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: theme.colorScheme.error.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                  const SizedBox(width: 12),
                  Text(
                    'Scan Failed',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                error,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _triggerScan,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Scan'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
              ),
            ],
          ),
        ),
      ),
      MenuScannerSuccess() => _buildReviewInterface(theme),
    };
  }

  Widget _buildReviewInterface(ThemeData theme) {
    if (_reviewedMenu == null) return const SizedBox.shrink();

    final menu = _reviewedMenu!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary banner with stats and review warning
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.edit_note_rounded,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Review & Edit Menu',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Extracted ${menu.categories.length} categories and ${menu.totalItemCount} dishes. Review and refine below before importing.',
                style: theme.textTheme.bodyMedium,
              ),
              if (menu.itemsNeedingReviewCount > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade700),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: Colors.amber.shade800,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${menu.itemsNeedingReviewCount} dish(es) flagged with missing prices or low confidence.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Categories & dishes list
        for (int cIdx = 0; cIdx < menu.categories.length; cIdx++) ...[
          _buildCategoryCard(theme, menu.categories[cIdx], cIdx),
          const SizedBox(height: 16),
        ],

        // Add Category button
        OutlinedButton.icon(
          onPressed: () => _showCategoryDialog(),
          icon: const Icon(Icons.add),
          label: const Text('Add Category'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 24),

        // Confirm & Import Action Button
        FilledButton.icon(
          key: const Key('confirm-import-button'),
          onPressed: menu.totalItemCount > 0 ? _confirmAndImport : null,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text(
            'Confirm & Import Menu',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Imports the verified menu into your active Ordo gathering session.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCategoryCard(
    ThemeData theme,
    ScannedCategory category,
    int categoryIndex,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.restaurant_menu,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    category.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  key: Key('edit-category-button-$categoryIndex'),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Rename category',
                  onPressed: () =>
                      _showCategoryDialog(categoryIndex: categoryIndex),
                ),
                IconButton(
                  key: Key('delete-category-button-$categoryIndex'),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete category',
                  onPressed: () => _deleteCategory(categoryIndex),
                ),
              ],
            ),
            const Divider(height: 20),
            if (category.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Center(
                  child: Text(
                    'No dishes in this category yet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            for (int iIdx = 0; iIdx < category.items.length; iIdx++) ...[
              if (iIdx > 0) const Divider(height: 16, thickness: 0.5),
              _buildDishItem(theme, category.items[iIdx], categoryIndex, iIdx),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('add-dish-button-$categoryIndex'),
                onPressed: () => _showItemDialog(categoryIndex: categoryIndex),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Dish'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDishItem(
    ThemeData theme,
    ScannedMenuItem item,
    int categoryIndex,
    int itemIndex,
  ) {
    final hasMissingPrice = item.variants.any(
      (v) => v.price == null || v.price! <= 0,
    );
    final isFlagged =
        item.needsReview || item.confidence == 'low' || hasMissingPrice;

    return Container(
      padding: EdgeInsets.all(isFlagged ? 10.0 : 6.0),
      decoration: BoxDecoration(
        color: isFlagged
            ? Colors.amber.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isFlagged ? Border.all(color: Colors.amber.shade400) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: _buildVegBadge(item.vegetarianStatus),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.description != null &&
                        item.description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isFlagged)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.amber.shade600),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flag, size: 12, color: Colors.amber.shade900),
                      const SizedBox(width: 4),
                      Text(
                        hasMissingPrice ? 'Price Missing' : 'Needs Review',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              IconButton(
                key: Key('edit-dish-button-${categoryIndex}_$itemIndex'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit dish',
                onPressed: () => _showItemDialog(
                  categoryIndex: categoryIndex,
                  itemIndex: itemIndex,
                ),
              ),
              IconButton(
                key: Key('delete-dish-button-${categoryIndex}_$itemIndex'),
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Delete dish',
                onPressed: () => _deleteItem(categoryIndex, itemIndex),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Variants and prices
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final v in item.variants)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: v.price == null || v.price! <= 0
                        ? Colors.red.shade50
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    border: v.price == null || v.price! <= 0
                        ? Border.all(color: Colors.red.shade300)
                        : null,
                  ),
                  child: Text(
                    '${v.name}: ${v.price != null && v.price! > 0 ? "₹${v.formattedPrice}" : "Missing Price"}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: v.price == null || v.price! <= 0
                          ? Colors.red.shade800
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVegBadge(String status) {
    final (icon, color) = switch (status) {
      'vegetarian' || 'vegan' => (Icons.eco, Colors.green.shade700),
      'egg' => (Icons.egg, Colors.orange.shade700),
      'non_vegetarian' => (Icons.restaurant, Colors.red.shade700),
      _ => (Icons.help_outline, Colors.grey.shade600),
    };

    return Icon(icon, size: 16, color: color);
  }
}

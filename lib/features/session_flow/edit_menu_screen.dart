import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/gathering_controller.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';

class EditMenuScreen extends ConsumerWidget {
  const EditMenuScreen({super.key});

  void _showCategoryDialog(
    BuildContext context,
    WidgetRef ref,
    MenuCategory? category,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: category?.name ?? '');
        return AlertDialog(
          title: Text(category == null ? 'Add Category' : 'Edit Category'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Category Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final notifier = ref.read(gatheringProvider.notifier);
                  if (category == null) {
                    notifier.addCategory(name);
                  } else {
                    notifier.renameCategory(category.id, name);
                  }
                }
                Navigator.pop(context);
              },
              child: Text(category == null ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    );
  }

  void _showItemDialog(
    BuildContext context,
    WidgetRef ref,
    MenuCategory category,
    MenuItem? item,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        final nameController = TextEditingController(text: item?.name ?? '');
        final priceController = TextEditingController(
          text: item != null ? rupeesInputText(item.pricePaise) : '',
        );
        String? nameError;
        String? priceError;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(item == null ? 'Add Item' : 'Edit Item'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Item Name',
                    errorText: nameError,
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceController,
                  decoration: InputDecoration(
                    labelText: 'Price',
                    errorText: priceError,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final price = parseRupees(priceController.text);
                  setDialogState(() {
                    nameError = name.isEmpty ? 'Enter a name' : null;
                    priceError = price == null || price <= 0
                        ? 'Enter a price above 0, e.g. 120 or 120.50'
                        : null;
                  });
                  if (nameError != null || priceError != null) return;
                  final notifier = ref.read(gatheringProvider.notifier);
                  if (item == null) {
                    notifier.addItem(
                      category.id,
                      name: name,
                      pricePaise: price!,
                    );
                  } else {
                    notifier.updateItem(
                      category.id,
                      item.id,
                      name: name,
                      pricePaise: price!,
                    );
                  }
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gathering = ref.watch(gatheringProvider);
    if (gathering == null) return const Scaffold();
    final menu = gathering.menu;
    final notifier = ref.read(gatheringProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Menu'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Category',
            onPressed: () => _showCategoryDialog(context, ref, null),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: menu.categories.length,
                itemBuilder: (context, index) {
                  final category = menu.categories[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  category.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed: () => _showCategoryDialog(
                                      context,
                                      ref,
                                      category,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 20),
                                    onPressed: () =>
                                        notifier.deleteCategory(category.id),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (category.items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('No items in this category.'),
                          ),
                        ...category.items.map((item) {
                          return ListTile(
                            title: Text(item.name),
                            subtitle: Text(formatRupees(item.pricePaise)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () => _showItemDialog(
                                    context,
                                    ref,
                                    category,
                                    item,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20),
                                  onPressed: () =>
                                      notifier.deleteItem(category.id, item.id),
                                ),
                              ],
                            ),
                          );
                        }),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextButton.icon(
                            onPressed: () =>
                                _showItemDialog(context, ref, category, null),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Item'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: menu.hasItems
                      ? () {
                          notifier.confirmMenu();
                          Navigator.pushNamed(context, '/participant_name');
                        }
                      : null,
                  child: const Text('Confirm Menu'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../shared/models/models.dart';

class EditMenuScreen extends StatefulWidget {
  final Session session;

  const EditMenuScreen({super.key, required this.session});

  @override
  State<EditMenuScreen> createState() => _EditMenuScreenState();
}

class _EditMenuScreenState extends State<EditMenuScreen> {
  late Menu _menu;

  @override
  void initState() {
    super.initState();
    _menu = widget.session.menu;
  }

  void _addCategory() {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Add Category'),
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
                if (controller.text.trim().isNotEmpty) {
                  setState(() {
                    _menu.categories.add(MenuCategory(name: controller.text.trim(), items: []));
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _editCategory(MenuCategory category) {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: category.name);
        return AlertDialog(
          title: const Text('Edit Category'),
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
                if (controller.text.trim().isNotEmpty) {
                  setState(() {
                    category.name = controller.text.trim();
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _deleteCategory(MenuCategory category) {
    setState(() {
      _menu.categories.remove(category);
    });
  }

  void _addMenuItem(MenuCategory category) {
    _showItemDialog(category, null);
  }

  void _editMenuItem(MenuCategory category, MenuItem item) {
    _showItemDialog(category, item);
  }

  void _showItemDialog(MenuCategory category, MenuItem? item) {
    showDialog(
      context: context,
      builder: (context) {
        final nameController = TextEditingController(text: item?.name ?? '');
        final priceController = TextEditingController(text: item != null ? item.price.toString() : '');
        return AlertDialog(
          title: Text(item == null ? 'Add Item' : 'Edit Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Item Name'),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(labelText: 'Price'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                final price = double.tryParse(priceController.text.trim()) ?? 0.0;
                if (name.isNotEmpty && price > 0) {
                  setState(() {
                    if (item == null) {
                      category.items.add(MenuItem(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        name: name,
                        price: price,
                      ));
                    } else {
                      item.name = name;
                      item.price = price;
                    }
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _deleteMenuItem(MenuCategory category, MenuItem item) {
    setState(() {
      category.items.remove(item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Menu'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Category',
            onPressed: _addCategory,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: _menu.categories.length,
                itemBuilder: (context, index) {
                  final category = _menu.categories[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
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
                                    onPressed: () => _editCategory(category),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 20),
                                    onPressed: () => _deleteCategory(category),
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
                            subtitle: Text('₹${item.price.toStringAsFixed(2)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () => _editMenuItem(category, item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20),
                                  onPressed: () => _deleteMenuItem(category, item),
                                ),
                              ],
                            ),
                          );
                        }),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextButton.icon(
                            onPressed: () => _addMenuItem(category),
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
                  onPressed: () {
                    widget.session.menu = _menu;
                    Navigator.pushNamed(
                      context,
                      '/participant_name',
                      arguments: widget.session,
                    );
                  },
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

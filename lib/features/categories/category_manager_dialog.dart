import 'package:flutter/material.dart';
import '../../models/transaction.dart';

const Color categoryGreen = Color(0xFF167D65);

class CategoryManagerDialog extends StatefulWidget {
  final List<String> categories;
  final List<Transaction> transactions;

  const CategoryManagerDialog({
    super.key,
    required this.categories,
    required this.transactions,
  });

  @override
  State<CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<CategoryManagerDialog> {
  late List<String> categories;
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    categories = List<String>.from(widget.categories);
  }

  void addCategory() {
    final name = controller.text.trim();

    if (name.isEmpty) return;

    final exists = categories.any(
      (category) => category.toLowerCase() == name.toLowerCase(),
    );

    if (exists) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Category already exists.')));
      return;
    }

    setState(() {
      categories.add(name);
    });

    controller.clear();
  }

  void deleteCategory(String category) {
    final inUse = widget.transactions.any(
      (transaction) => transaction.category == category,
    );

    if (inUse) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$category is used in transaction history and cannot be deleted.',
          ),
        ),
      );
      return;
    }

    setState(() {
      categories.remove(category);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Categories'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'New category name',
                    ),
                    onSubmitted: (_) => addCategory(),
                  ),
                ),
                IconButton(
                  onPressed: addCategory,
                  icon: const Icon(Icons.add_circle, color: categoryGreen),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: categories.isEmpty
                  ? const Text('No categories yet. Add one above.')
                  : ListView(
                      shrinkWrap: true,
                      children: categories.map((category) {
                        return ListTile(
                          title: Text(category),
                          trailing: IconButton(
                            tooltip: 'Delete category',
                            onPressed: () => deleteCategory(category),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, categories),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

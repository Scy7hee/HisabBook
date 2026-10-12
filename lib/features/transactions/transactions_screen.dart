import 'package:flutter/material.dart';

import '../../models/transaction.dart';
import '../../services/database_service.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() =>
      _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final DatabaseService _database = DatabaseService.instance;
  final TextEditingController _searchController =
      TextEditingController();

  List<Transaction> _transactions = [];
  List<String> _categories = [];

  bool _isLoading = true;
  String? _loadError;

  String _typeFilter = 'All';
  String _paymentFilter = 'All';

  Color get _mutedColor =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF9BAAC0)
          : const Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      await _database.initialize();

      final transactions = await _database.getTransactions();
      final categories = await _database.getCategories();

      if (!mounted) return;

      setState(() {
        _transactions = transactions;
        _categories = categories;
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      debugPrint('Loading transactions failed: $error');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadError = 'Could not load transactions. Please retry.';
      });
    }
  }

  List<Transaction> get _filteredTransactions {
    final query = _searchController.text.trim().toLowerCase();

    return _transactions.where((transaction) {
      final matchesSearch = query.isEmpty ||
          transaction.title.toLowerCase().contains(query) ||
          transaction.category.toLowerCase().contains(query) ||
          transaction.amount.toString().contains(query);

      final matchesType = _typeFilter == 'All' ||
          (_typeFilter == 'Income' && transaction.isIncome) ||
          (_typeFilter == 'Expense' && !transaction.isIncome);

      final matchesPayment = _paymentFilter == 'All' ||
          transaction.paymentMode == _paymentFilter;

      return matchesSearch && matchesType && matchesPayment;
    }).toList();
  }

  double get _filteredIncome => _filteredTransactions
      .where((transaction) => transaction.isIncome)
      .fold(0.0, (sum, transaction) => sum + transaction.amount);

  double get _filteredExpenses => _filteredTransactions
      .where((transaction) => !transaction.isIncome)
      .fold(0.0, (sum, transaction) => sum + transaction.amount);

  String _money(double amount) =>
      '₹ ${amount.toStringAsFixed(2)}';

  String _date(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _editTransaction(Transaction transaction) async {
    final updated = await showDialog<Transaction>(
      context: context,
      builder: (_) => _EditTransactionDialog(
        transaction: transaction,
        categories: _categories,
      ),
    );

    if (updated == null || !mounted) return;

    try {
      await _database.updateTransaction(updated);
      await _loadData();
      _showMessage('Transaction updated successfully.');
    } catch (error) {
      debugPrint('Updating transaction failed: $error');
      _showMessage('Could not update transaction.');
    }
  }

  Future<void> _deleteTransaction(Transaction transaction) async {
    if (transaction.id == null) {
      _showMessage('This transaction has no database ID.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text(
          'Delete "${transaction.title}" permanently?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _database.deleteTransaction(transaction.id!);
      await _loadData();
      _showMessage('Transaction deleted.');
    } catch (error) {
      debugPrint('Deleting transaction failed: $error');
      _showMessage('Could not delete transaction.');
    }
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Icons.restaurant_rounded;
      case 'travel':
        return Icons.directions_bus_rounded;
      case 'shopping':
        return Icons.shopping_bag_outlined;
      case 'bills':
        return Icons.receipt_long_rounded;
      case 'education':
        return Icons.school_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  Widget _filterChips({
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((option) {
          final isSelected = selected == option;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (_) => onSelected(option),
              selectedColor: colors.primary.withValues(
                alpha: 0.18,
              ),
              backgroundColor: colors.surface,
              side: BorderSide(
                color: isSelected
                    ? colors.primary
                    : colors.outlineVariant,
              ),
              labelStyle: TextStyle(
                color: isSelected
                    ? colors.primary
                    : colors.onSurface,
                fontWeight: isSelected
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final filtered = _filteredTransactions;
    final muted = _mutedColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your complete money history',
                style: TextStyle(
                  color: muted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search title, category or amount',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'TRANSACTION TYPE',
                style: TextStyle(
                  color: muted,
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),

              _filterChips(
                options: const ['All', 'Income', 'Expense'],
                selected: _typeFilter,
                onSelected: (value) {
                  setState(() => _typeFilter = value);
                },
              ),

              const SizedBox(height: 8),

              Text(
                'PAYMENT METHOD',
                style: TextStyle(
                  color: muted,
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),

              _filterChips(
                options: const ['All', 'Cash', 'Online'],
                selected: _paymentFilter,
                onSelected: (value) {
                  setState(() => _paymentFilter = value);
                },
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Transactions (${filtered.length})',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh history',
                    onPressed: () => _loadData(showLoading: true),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),

              if (!_isLoading && _loadError == null &&
                  filtered.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Income: ${_money(_filteredIncome)}',
                        style: const TextStyle(
                          color: Color(0xFF168568),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Expenses: ${_money(_filteredExpenses)}',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: colors.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),

        Expanded(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: colors.primary,
                  ),
                )
              : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _loadError!,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () =>
                                  _loadData(showLoading: true),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 46,
                                  color: muted,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _transactions.isEmpty
                                      ? 'No transactions yet.'
                                      : 'No matching transactions.',
                                  style: TextStyle(
                                    color: colors.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Try changing your search or filters.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: muted),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          child: ListView.separated(
                            physics:
                                const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(
                              18, 4, 18, 24,
                            ),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 9),
                            itemBuilder: (context, index) {
                              final transaction = filtered[index];
                              final isIncome =
                                  transaction.isIncome;

                              return Card(
                                color: colors.surface,
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: colors.primary
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Icon(
                                          isIncome
                                              ? Icons
                                                  .account_balance_wallet_rounded
                                              : _categoryIcon(
                                                  transaction.category,
                                                ),
                                          color: isIncome
                                              ? colors.primary
                                              : colors.error,
                                        ),
                                      ),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              transaction.title,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: colors.onSurface,
                                                fontWeight:
                                                    FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${transaction.category} • '
                                              '${_date(transaction.date)}',
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: muted,
                                                fontSize: 11,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Row(
                                              children: [
                                                Icon(
                                                  transaction.paymentMode ==
                                                          'Cash'
                                                      ? Icons
                                                          .payments_outlined
                                                      : Icons
                                                          .account_balance_outlined,
                                                  size: 13,
                                                  color: muted,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  transaction.paymentMode,
                                                  style: TextStyle(
                                                    color: muted,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${isIncome ? '+' : '-'}'
                                            '${_money(transaction.amount)}',
                                            style: TextStyle(
                                              color: isIncome
                                                  ? colors.primary
                                                  : colors.error,
                                              fontSize: 11,
                                              fontWeight:
                                                  FontWeight.w800,
                                            ),
                                          ),
                                          Row(
                                            mainAxisSize:
                                                MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                tooltip: 'Edit',
                                                onPressed: () =>
                                                    _editTransaction(
                                                  transaction,
                                                ),
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18,
                                                ),
                                              ),
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                tooltip: 'Delete',
                                                onPressed: () =>
                                                    _deleteTransaction(
                                                  transaction,
                                                ),
                                                icon: Icon(
                                                  Icons
                                                      .delete_outline_rounded,
                                                  size: 18,
                                                  color: colors.error,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class _EditTransactionDialog extends StatefulWidget {
  final Transaction transaction;
  final List<String> categories;

  const _EditTransactionDialog({
    required this.transaction,
    required this.categories,
  });

  @override
  State<_EditTransactionDialog> createState() =>
      _EditTransactionDialogState();
}

class _EditTransactionDialogState
    extends State<_EditTransactionDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late final TextEditingController _customCategoryController;

  late String _category;
  late String _paymentMode;
  late DateTime _date;

  bool get _isIncome => widget.transaction.isIncome;

  List<String> get _availableCategories {
    final result = widget.categories
        .where((category) => category != 'Income')
        .toList();

    if (!result.contains('Other')) {
      result.add('Other');
    }

    return result;
  }

  @override
  void initState() {
    super.initState();

    final transaction = widget.transaction;

    _amountController = TextEditingController(
      text: transaction.amount.toString(),
    );

    _noteController = TextEditingController(
      text: transaction.title == transaction.category
          ? ''
          : transaction.title,
    );

    final categoryExists =
        widget.categories.contains(transaction.category) &&
        transaction.category != 'Income';

    _category = categoryExists
        ? transaction.category
        : 'Other';

    _customCategoryController = TextEditingController(
      text: categoryExists || _isIncome
          ? ''
          : transaction.category,
    );

    _paymentMode = transaction.paymentMode;
    _date = transaction.date;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text.trim());

    final category = _isIncome
        ? 'Income'
        : (_category == 'Other'
            ? _customCategoryController.text.trim()
            : _category);

    final note = _noteController.text.trim();

    Navigator.pop(
      context,
      Transaction(
        id: widget.transaction.id,
        title: note.isEmpty
            ? (_isIncome ? 'Income' : category)
            : note,
        category: category,
        amount: amount,
        date: _date,
        isIncome: _isIncome,
        paymentMode: _paymentMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? const Color(0xFF9BAAC0)
        : const Color(0xFF64748B);

    return AlertDialog(
      title: const Text('Edit transaction'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹)',
                    prefixIcon:
                        Icon(Icons.currency_rupee_rounded),
                  ),
                  validator: (value) {
                    final amount =
                        double.tryParse(value?.trim() ?? '');

                    if (amount == null ||
                        !amount.isFinite ||
                        amount <= 0) {
                      return 'Enter a valid amount';
                    }

                    return null;
                  },
                ),
                if (!_isIncome) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: _availableCategories.map((category) {
                      return DropdownMenuItem<String>(
                        value: category,
                        child: Text(category),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;

                      setState(() {
                        if (value != 'Other' &&
                            _category != value) {
                          _customCategoryController.clear();
                        }

                        _category = value;
                      });
                    },
                  ),
                  if (_category == 'Other') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customCategoryController,
                      decoration: const InputDecoration(
                        labelText: 'Custom category',
                      ),
                      validator: (value) {
                        if (_category == 'Other' &&
                            (value?.trim().isEmpty ?? true)) {
                          return 'Enter a category name';
                        }

                        return null;
                      },
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                    prefixIcon:
                        Icon(Icons.account_balance_wallet_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Cash',
                      child: Text('Cash'),
                    ),
                    DropdownMenuItem(
                      value: 'Online',
                      child: Text('Online'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _paymentMode = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: _isIncome
                        ? 'Income source / note'
                        : 'Note (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(
                    'Date: ${_date.day}/${_date.month}/${_date.year}',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save Changes'),
        ),
      ],
    );
  }
}
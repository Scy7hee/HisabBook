import 'package:flutter/material.dart';
import '../../models/transaction.dart';
import '../../services/database_service.dart';
import '../categories/category_manager_dialog.dart';

const Color appGreen = Color(0xFF39D6A0);
const Color appBackground = Color(0xFF101827);
const Color appCard = Color(0xFF192436);
const Color appMuted = Color(0xFF9BAAC0);
const Color appRed = Color(0xFFFF8793);

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onSeeAllTransactions;
  const DashboardScreen({super.key, this.onSeeAllTransactions});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseService _database = DatabaseService.instance;
  final List<String> categories = [];
  final List<Transaction> transactions = [];
  bool _isLoading = true;
  String? _loadError;
  Color get _mutedColor => Theme.of(context).brightness == Brightness.dark
      ? appMuted
      : const Color(0xFF64748B);
  // Udhaar affects the actual wallet balance, but it is not ordinary
  // income or spending and should not inflate these two summaries.
  double get totalIncome => transactions
      .where((t) => t.isIncome && !t.isUdhaar)
      .fold(0.0, (sum, t) => sum + t.amount);
  double get totalExpenses => transactions
      .where((t) => !t.isIncome && !t.isUdhaar)
      .fold(0.0, (sum, t) => sum + t.amount);
  double get balance => transactions.fold(
    0.0,
    (sum, t) => sum + (t.isIncome ? t.amount : -t.amount),
  );
  double get cashBalance => transactions.fold(
    0.0,
    (sum, t) =>
        sum +
        (t.paymentMode == 'Cash' ? (t.isIncome ? t.amount : -t.amount) : 0),
  );
  double get onlineBalance => transactions.fold(
    0.0,
    (sum, t) =>
        sum +
        (t.paymentMode == 'Online' ? (t.isIncome ? t.amount : -t.amount) : 0),
  );
  String money(double amount) {
    if (amount < 0) {
      return '-₹ ${(-amount).toStringAsFixed(2)}';
    }
    return '₹ ${amount.toStringAsFixed(2)}';
  }

  String formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';
  @override
  void initState() {
    super.initState();
    _loadData();
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
      final savedCategories = await _database.getCategories();
      final savedTransactions = await _database.getTransactions();
      if (!mounted) return;
      setState(() {
        categories
          ..clear()
          ..addAll(savedCategories);
        transactions
          ..clear()
          ..addAll(savedTransactions);
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      debugPrint('Failed to load HisabBook data: $error');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load saved data. Please try again.';
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> openCategoryManager() async {
    final originalCategories = List<String>.from(categories);
    final updatedCategories = await showDialog<List<String>>(
      context: context,
      builder: (_) => CategoryManagerDialog(
        categories: originalCategories,
        transactions: List<Transaction>.from(transactions),
      ),
    );
    if (updatedCategories == null || !mounted) return;
    try {
      for (final category in updatedCategories) {
        if (!originalCategories.contains(category)) {
          await _database.addCategory(category);
        }
      }
      for (final category in originalCategories) {
        if (!updatedCategories.contains(category)) {
          final deleted = await _database.deleteCategory(category);
          if (!deleted) {
            _showMessage(
              '$category is used by a transaction '
              'and cannot be deleted.',
            );
          }
        }
      }
      await _loadData();
    } catch (error) {
      debugPrint('Category update failed: $error');
      _showMessage('Could not update categories.');
    }
  }

  Future<void> _addTransaction({required bool isIncome}) async {
    if (!isIncome && categories.isEmpty) {
      await openCategoryManager();
      if (!mounted || categories.isEmpty) return;
    }
    final result = await showDialog<Transaction>(
      context: context,
      builder: (_) => _TransactionFormDialog(
        categories: categories,
        isIncome: isIncome,
        onManageCategories: openCategoryManager,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await _database.insertTransaction(result);
      await _loadData();
      _showMessage(
        isIncome ? 'Income saved successfully.' : 'Expense saved successfully.',
      );
    } catch (error) {
      debugPrint('Saving transaction failed: $error');
      _showMessage('Could not save the transaction.');
    }
  }

  Future<void> addExpense() => _addTransaction(isIncome: false);
  Future<void> addIncome() => _addTransaction(isIncome: true);
  Future<void> editTransaction(Transaction transaction) async {
    if (transaction.id == null) {
      _showMessage('This transaction has no database ID.');
      return;
    }
    final updated = await showDialog<Transaction>(
      context: context,
      builder: (_) => _TransactionFormDialog(
        categories: categories,
        transaction: transaction,
        onManageCategories: openCategoryManager,
      ),
    );
    if (updated == null || !mounted) return;
    try {
      await _database.updateTransaction(updated);
      await _loadData();
      _showMessage('Transaction updated successfully.');
    } catch (error) {
      debugPrint('Updating transaction failed: $error');
      _showMessage('Could not update the transaction.');
    }
  }

  Future<void> deleteTransaction(Transaction transaction) async {
    if (transaction.id == null) {
      _showMessage('This transaction has no database ID.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text(
          'Are you sure you want to delete "${transaction.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _database.deleteTransaction(transaction.id!);
      await _loadData();
      _showMessage('Transaction deleted.');
    } catch (error) {
      debugPrint('Deleting transaction failed: $error');
      _showMessage('Could not delete the transaction.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = _mutedColor;
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: colors.error, size: 42),
              const SizedBox(height: 12),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurface),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _loadData(showLoading: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final recent =
        transactions.where((transaction) => !transaction.isUdhaar).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        Text(
          'Good to see you 👋',
          style: TextStyle(color: muted, fontSize: 14),
        ),
        const SizedBox(height: 5),
        Text(
          'Your money at a glance',
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        // Total, Cash and Online balances.
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF174E47), Color(0xFF1A7560)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TOTAL BALANCE',
                style: TextStyle(
                  color: Color(0xFFD0F6E8),
                  fontSize: 11,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  money(balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _AccountBalance(
                      title: 'Cash Balance',
                      amount: cashBalance,
                      icon: Icons.payments_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AccountBalance(
                      title: 'Online Balance',
                      amount: onlineBalance,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(color: Color(0x556FE0BB)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _IncomeExpenseSummary(
                      title: 'Income',
                      amount: money(totalIncome),
                      icon: Icons.south_west_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _IncomeExpenseSummary(
                      title: 'Expenses',
                      amount: money(totalExpenses),
                      icon: Icons.north_east_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _QuickAction(
                label: 'Add Expense',
                subtitle: 'Record money spent',
                icon: Icons.remove_circle_outline_rounded,
                color: colors.error,
                onTap: addExpense,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickAction(
                label: 'Add Income',
                subtitle: 'Record money received',
                icon: Icons.add_circle_outline_rounded,
                color: colors.primary,
                onTap: addIncome,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: openCategoryManager,
          icon: const Icon(Icons.category_outlined),
          label: const Text('Manage Categories'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent Transactions',
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text('Latest 5', style: TextStyle(color: muted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Center(
                child: Text(
                  'No transactions yet. Add income or expense.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              ),
            ),
          )
        else
          ...recent.take(5).map(transactionTile),
        const SizedBox(height: 10),
        // Opens the complete transaction history page.
        OutlinedButton.icon(
          onPressed: widget.onSeeAllTransactions,
          icon: const Icon(Icons.receipt_long_rounded),
          label: const Text('See Full Transaction History'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.primary,
            minimumSize: const Size.fromHeight(52),
            side: BorderSide(color: colors.primary.withValues(alpha: 0.65)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget transactionTile(Transaction transaction) {
    final colors = Theme.of(context).colorScheme;
    final muted = _mutedColor;
    final isIncome = transaction.isIncome;
    return Card(
      color: colors.surface,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: colors.primary.withValues(alpha: 0.12),
              child: Icon(
                isIncome
                    ? Icons.account_balance_wallet_rounded
                    : _categoryIcon(transaction.category),
                color: isIncome ? colors.primary : colors.error,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${transaction.category} • '
                    '${formatDate(transaction.date)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        transaction.paymentMode == 'Cash'
                            ? Icons.payments_outlined
                            : Icons.account_balance_wallet_outlined,
                        size: 13,
                        color: muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        transaction.paymentMode,
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${isIncome ? '+' : '-'}${money(transaction.amount)}',
                  style: TextStyle(
                    color: isIncome ? colors.primary : colors.error,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Edit transaction',
                      onPressed: () => editTransaction(transaction),
                      icon: Icon(Icons.edit_outlined, size: 18, color: muted),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Delete transaction',
                      onPressed: () => deleteTransaction(transaction),
                      icon: Icon(
                        Icons.delete_outline_rounded,
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
}

class _TransactionFormDialog extends StatefulWidget {
  final List<String> categories;
  final bool isIncome;
  final Transaction? transaction;
  final Future<void> Function() onManageCategories;
  const _TransactionFormDialog({
    required this.categories,
    required this.onManageCategories,
    this.isIncome = false,
    this.transaction,
  });
  @override
  State<_TransactionFormDialog> createState() => _TransactionFormDialogState();
}

class _TransactionFormDialogState extends State<_TransactionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late final TextEditingController _customCategoryController;
  late String _selectedCategory;
  late String _paymentMode;
  late DateTime _selectedDate;
  late bool _isIncome;
  bool get _isEditing => widget.transaction != null;
  @override
  void initState() {
    super.initState();
    final existing = widget.transaction;
    _isIncome = existing?.isIncome ?? widget.isIncome;
    _amountController = TextEditingController(
      text: existing == null ? '' : existing.amount.toString(),
    );
    _noteController = TextEditingController(
      text: existing == null || existing.title == existing.category
          ? ''
          : existing.title,
    );
    _paymentMode = existing?.paymentMode ?? 'Cash';
    _selectedDate = existing?.date ?? DateTime.now();
    final availableCategories = widget.categories
        .where((category) => category != 'Income')
        .toList();
    if (!availableCategories.contains('Other')) {
      availableCategories.add('Other');
    }
    final currentCategory = existing?.category;
    if (currentCategory != null &&
        availableCategories.contains(currentCategory)) {
      _selectedCategory = currentCategory;
    } else if (currentCategory != null && !_isIncome) {
      _selectedCategory = 'Other';
    } else if (availableCategories.isNotEmpty) {
      _selectedCategory = availableCategories.first;
    } else {
      _selectedCategory = 'Other';
    }
    final customName =
        existing != null &&
            !_isIncome &&
            !widget.categories.contains(existing.category)
        ? existing.category
        : '';
    _customCategoryController = TextEditingController(text: customName);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  Future<void> _manageCategories() async {
    await widget.onManageCategories();
    if (!mounted) return;
    setState(() {
      final available = widget.categories
          .where((category) => category != 'Income')
          .toList();
      if (!available.contains('Other')) {
        available.add('Other');
      }
      if (!available.contains(_selectedCategory)) {
        _selectedCategory = available.isNotEmpty ? available.first : 'Other';
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountController.text.trim());
    String finalCategory = 'Income';
    if (!_isIncome) {
      finalCategory = _selectedCategory == 'Other'
          ? _customCategoryController.text.trim()
          : _selectedCategory;
    }
    final note = _noteController.text.trim();
    final previous = widget.transaction;
    Navigator.of(context).pop(
      Transaction(
        id: previous?.id,
        title: note.isEmpty ? (_isIncome ? 'Income' : finalCategory) : note,
        category: finalCategory,
        amount: amount,
        date: _selectedDate,
        isIncome: _isIncome,
        paymentMode: _paymentMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? appMuted
        : const Color(0xFF64748B);
    final availableCategories = widget.categories
        .where((category) => category != 'Income')
        .toList();
    if (!availableCategories.contains('Other')) {
      availableCategories.add('Other');
    }
    return AlertDialog(
      title: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              _isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isEditing
                  ? (_isIncome ? 'Edit Income' : 'Edit Expense')
                  : (_isIncome ? 'Add Income' : 'Add Expense'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'TRANSACTION DETAILS',
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    hintText: '0.00',
                    prefixIcon: Icon(Icons.currency_rupee_rounded),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(value?.trim() ?? '');
                    if (amount == null || !amount.isFinite || amount <= 0) {
                      return 'Enter an amount greater than zero';
                    }
                    return null;
                  },
                ),
                if (!_isIncome) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue:
                        availableCategories.contains(_selectedCategory)
                        ? _selectedCategory
                        : 'Other',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Expense category',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: availableCategories.map((category) {
                      return DropdownMenuItem<String>(
                        value: category,
                        child: Text(category),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedCategory = value;
                        if (value != 'Other') {
                          _customCategoryController.clear();
                        }
                      });
                    },
                  ),
                  if (_selectedCategory == 'Other') ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _customCategoryController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Custom category',
                        hintText: 'e.g. Medicine, Recharge',
                        prefixIcon: Icon(Icons.edit_outlined),
                      ),
                      validator: (value) {
                        if (_selectedCategory == 'Other' &&
                            (value?.trim().isEmpty ?? true)) {
                          return 'Enter a category name';
                        }
                        return null;
                      },
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _manageCategories,
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Manage categories'),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'PAYMENT DETAILS',
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                  items: const [
                    DropdownMenuItem<String>(
                      value: 'Cash',
                      child: Row(
                        children: [
                          Icon(Icons.payments_outlined, size: 20),
                          SizedBox(width: 10),
                          Text('Cash'),
                        ],
                      ),
                    ),
                    DropdownMenuItem<String>(
                      value: 'Online',
                      child: Row(
                        children: [
                          Icon(Icons.account_balance_outlined, size: 20),
                          SizedBox(width: 10),
                          Text('Online'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _paymentMode = value;
                    });
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _noteController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _isIncome
                        ? 'Income source / note'
                        : 'Note (optional)',
                    hintText: _isIncome
                        ? 'e.g. Salary, Pocket money'
                        : 'e.g. Lunch with friends',
                    prefixIcon: Icon(
                      _isIncome ? Icons.savings_outlined : Icons.notes_rounded,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(
                    'Date: ${_selectedDate.day}/'
                    '${_selectedDate.month}/'
                    '${_selectedDate.year}',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: Icon(
            _isIncome
                ? Icons.add_circle_outline_rounded
                : Icons.check_circle_outline_rounded,
          ),
          label: Text(
            _isEditing
                ? 'Save Changes'
                : (_isIncome ? 'Save Income' : 'Save Expense'),
          ),
        ),
      ],
    );
  }
}

class _AccountBalance extends StatelessWidget {
  final String title;
  final double amount;
  final IconData icon;
  const _AccountBalance({
    required this.title,
    required this.amount,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) {
    final amountColor = amount < 0 ? const Color(0xFFFFC2C8) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: const Color(0xFFD0F6E8)),
          const SizedBox(height: 9),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFD0F6E8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount < 0
                  ? '-₹ ${(-amount).toStringAsFixed(2)}'
                  : '₹ ${amount.toStringAsFixed(2)}',
              style: TextStyle(
                color: amountColor,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomeExpenseSummary extends StatelessWidget {
  final String title;
  final String amount;
  final IconData icon;
  const _IncomeExpenseSummary({
    required this.title,
    required this.amount,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: const Color(0xFFD0F6E8)),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Color(0xFFD0F6E8), fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                amount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? appMuted
                            : const Color(0xFF64748B),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

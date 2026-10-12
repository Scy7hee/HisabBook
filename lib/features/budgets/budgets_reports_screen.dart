import 'package:flutter/material.dart';

import '../../models/monthly_budget.dart';
import '../../models/transaction.dart';
import '../../services/database_service.dart';

class BudgetsReportsScreen extends StatefulWidget {
  const BudgetsReportsScreen({super.key});

  @override
  State<BudgetsReportsScreen> createState() => _BudgetsReportsScreenState();
}

class _BudgetsReportsScreenState extends State<BudgetsReportsScreen> {
  final DatabaseService _database = DatabaseService.instance;

  final List<String> _categories = [];
  final List<Transaction> _transactions = [];
  final List<MonthlyBudget> _budgets = [];

  late DateTime _selectedMonth;

  bool _isLoading = true;
  String? _loadError;

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);

    _loadData();
  }

  String get _monthLabel =>
      '${_monthNames[_selectedMonth.month - 1]} '
      '${_selectedMonth.year}';

  List<Transaction> get _monthTransactions {
    return _transactions.where((transaction) {
      return transaction.date.month == _selectedMonth.month &&
          transaction.date.year == _selectedMonth.year;
    }).toList();
  }

  double get _monthlyIncome {
    return _monthTransactions
        .where((transaction) => transaction.isIncome)
        .fold(0.0, (sum, transaction) => sum + transaction.amount);
  }

  double get _monthlyExpenses {
    return _monthTransactions
        .where((transaction) => !transaction.isIncome)
        .fold(0.0, (sum, transaction) => sum + transaction.amount);
  }

  double get _monthlyNet => _monthlyIncome - _monthlyExpenses;

  List<MapEntry<String, double>> get _categoryExpenseTotals {
    final totals = <String, double>{};

    for (final transaction in _monthTransactions) {
      if (transaction.isIncome) continue;

      totals.update(
        transaction.category,
        (value) => value + transaction.amount,
        ifAbsent: () => transaction.amount,
      );
    }

    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return entries;
  }

  double _spentForCategory(String category) {
    return _monthTransactions
        .where(
          (transaction) =>
              !transaction.isIncome &&
              transaction.category.toLowerCase() == category.toLowerCase(),
        )
        .fold(0.0, (sum, transaction) => sum + transaction.amount);
  }

  String _money(double amount) {
    final formatted = amount.toStringAsFixed(2);

    if (amount < 0) {
      return '-₹ ${formatted.substring(1)}';
    }

    return '₹ $formatted';
  }

  Future<void> _loadData({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    final requestedMonth = _selectedMonth;

    try {
      await _database.initialize();

      final savedCategories = await _database.getCategories();
      final savedTransactions = await _database.getTransactions();

      final savedBudgets = await _database.getMonthlyBudgets(
        month: requestedMonth.month,
        year: requestedMonth.year,
      );

      if (!mounted) return;

      // Ignore stale results if the user has already selected another month.
      if (requestedMonth.month != _selectedMonth.month ||
          requestedMonth.year != _selectedMonth.year) {
        return;
      }

      setState(() {
        _categories
          ..clear()
          ..addAll(
            savedCategories.where(
              (category) => category.toLowerCase() != 'income',
            ),
          );

        _transactions
          ..clear()
          ..addAll(savedTransactions);

        _budgets
          ..clear()
          ..addAll(savedBudgets);

        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      debugPrint('Failed to load budget data: $error');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadError = 'Could not load budgets and reports.';
      });
    }
  }

  Future<void> _changeMonth(int amount) async {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + amount,
        1,
      );
      _isLoading = true;
      _loadError = null;
    });

    await _loadData();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openBudgetDialog({MonthlyBudget? existing}) async {
    final Set<String> usedCategories = _budgets
        .map((budget) => budget.category.toLowerCase())
        .toSet();

    final availableCategories = _categories.where((category) {
      if (existing != null &&
          category.toLowerCase() == existing.category.toLowerCase()) {
        return true;
      }

      return !usedCategories.contains(category.toLowerCase());
    }).toList();

    // Preserve a saved budget's category even if it was later removed
    // from the category list.
    if (existing != null &&
        !availableCategories.any(
          (category) =>
              category.toLowerCase() == existing.category.toLowerCase(),
        )) {
      availableCategories.add(existing.category);
    }

    if (availableCategories.isEmpty) {
      _showMessage(
        _categories.isEmpty
            ? 'Add an expense category before setting a budget.'
            : 'All available categories already have a budget '
                  'for this month.',
      );
      return;
    }

    final result = await showDialog<MonthlyBudget>(
      context: context,
      builder: (_) => _BudgetEditorDialog(
        categories: availableCategories,
        month: _selectedMonth.month,
        year: _selectedMonth.year,
        existing: existing,
      ),
    );

    if (result == null || !mounted) return;

    try {
      await _database.saveMonthlyBudget(result);
      await _loadData();

      _showMessage(
        existing == null ? 'Monthly budget saved.' : 'Monthly budget updated.',
      );
    } catch (error) {
      debugPrint('Saving budget failed: $error');
      _showMessage('Could not save the budget.');
    }
  }

  Future<void> _deleteBudget(MonthlyBudget budget) async {
    if (budget.id == null) {
      _showMessage('Could not identify this budget.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete budget?'),
        content: Text('Delete the ${budget.category} budget for $_monthLabel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _database.deleteMonthlyBudget(budget.id!);
      await _loadData();

      _showMessage('Budget deleted.');
    } catch (error) {
      debugPrint('Deleting budget failed: $error');
      _showMessage('Could not delete the budget.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

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

    return RefreshIndicator(
      onRefresh: () => _loadData(showLoading: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            'Plan your spending. Stay in control.',
            style: TextStyle(
              color: colors.onSurface.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),

          // Month selector.
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _monthLabel,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Monthly overview',
                          style: TextStyle(
                            color: colors.onSurface.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          _sectionHeading('Monthly Summary'),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  title: 'Income',
                  amount: _money(_monthlyIncome),
                  icon: Icons.south_west_rounded,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  title: 'Expenses',
                  amount: _money(_monthlyExpenses),
                  icon: Icons.north_east_rounded,
                  color: colors.error,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  title: 'Net',
                  amount: _money(_monthlyNet),
                  icon: Icons.account_balance_wallet_outlined,
                  color: _monthlyNet < 0 ? colors.error : colors.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(child: _sectionHeading('Category Budgets')),
              FilledButton.icon(
                onPressed: () => _openBudgetDialog(),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Add'),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Text(
            'Set a spending limit for each expense category.',
            style: TextStyle(
              color: colors.onSurface.withValues(alpha: 0.65),
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 12),

          if (_budgets.isEmpty)
            _EmptyState(
              icon: Icons.savings_outlined,
              title: 'No budgets for $_monthLabel',
              description:
                  'Set a category budget to track spending and '
                  'see how much money you have left.',
              actionLabel: 'Set Your First Budget',
              onAction: () => _openBudgetDialog(),
            )
          else
            ..._budgets.map((budget) {
              final spent = _spentForCategory(budget.category);

              return _BudgetProgressCard(
                budget: budget,
                spent: spent,
                money: _money,
                onEdit: () => _openBudgetDialog(existing: budget),
                onDelete: () => _deleteBudget(budget),
              );
            }),

          const SizedBox(height: 24),

          _sectionHeading('Spending by Category'),

          const SizedBox(height: 6),

          Text(
            'Your expenses for $_monthLabel, from saved transactions.',
            style: TextStyle(
              color: colors.onSurface.withValues(alpha: 0.65),
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 12),

          if (_categoryExpenseTotals.isEmpty)
            const _EmptyState(
              icon: Icons.bar_chart_rounded,
              title: 'No expenses this month',
              description: 'When you record an expense, it will appear here.',
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: _categoryExpenseTotals.map((entry) {
                    final fraction = _monthlyExpenses > 0
                        ? entry.value / _monthlyExpenses
                        : 0.0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _money(entry.value),
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: fraction.clamp(0.0, 1.0).toDouble(),
                              minHeight: 8,
                              backgroundColor: colors.onSurface.withValues(
                                alpha: 0.08,
                              ),
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${(fraction * 100).round()}% of monthly expenses',
                            style: TextStyle(
                              color: colors.onSurface.withValues(alpha: 0.6),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          const SizedBox(height: 8),

          Text(
            'Budgets are based on expense categories and the month '
            'of each transaction. Net = income − expenses.',
            style: TextStyle(
              color: colors.onSurface.withValues(alpha: 0.55),
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(String title) {
    final colors = Theme.of(context).colorScheme;

    return Text(
      title,
      style: TextStyle(
        color: colors.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String amount;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.65),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  amount,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetProgressCard extends StatelessWidget {
  final MonthlyBudget budget;
  final double spent;
  final String Function(double) money;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BudgetProgressCard({
    required this.budget,
    required this.spent,
    required this.money,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ratio = spent / budget.limitAmount;
    final progress = ratio.clamp(0.0, 1.0).toDouble();
    final isOverBudget = spent > budget.limitAmount;
    final isNearLimit = !isOverBudget && ratio >= 0.8;

    final statusColor = isOverBudget
        ? colors.error
        : isNearLimit
        ? Colors.orange
        : colors.primary;

    final remaining = budget.limitAmount - spent;

    final statusText = isOverBudget
        ? 'Over budget by ${money(-remaining)}'
        : '${money(remaining)} remaining';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    budget.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit budget',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 19),
                ),
                IconButton(
                  tooltip: 'Delete budget',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: colors.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        money(spent),
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'of ${money(budget.limitAmount)}',
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.65),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(ratio * 100).round()}% used',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 9,
                backgroundColor: colors.onSurface.withValues(alpha: 0.08),
                color: statusColor,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(icon, color: colors.primary, size: 36),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.65),
                fontSize: 12,
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 15),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetEditorDialog extends StatefulWidget {
  final List<String> categories;
  final int month;
  final int year;
  final MonthlyBudget? existing;

  const _BudgetEditorDialog({
    required this.categories,
    required this.month,
    required this.year,
    this.existing,
  });

  @override
  State<_BudgetEditorDialog> createState() => _BudgetEditorDialogState();
}

class _BudgetEditorDialogState extends State<_BudgetEditorDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late String _selectedCategory;

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();

    _selectedCategory = widget.existing?.category ?? widget.categories.first;

    _amountController = TextEditingController(
      text: widget.existing == null
          ? ''
          : widget.existing!.limitAmount.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text.trim());

    Navigator.of(context).pop(
      MonthlyBudget(
        id: widget.existing?.id,
        category: _selectedCategory,
        month: widget.month,
        year: widget.year,
        limitAmount: amount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final monthName = _monthNames[widget.month - 1];

    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Set Monthly Budget' : 'Edit Monthly Budget',
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '$monthName ${widget.year}',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Expense category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: widget.categories.map((category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: widget.existing != null
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _selectedCategory = value;
                          });
                        },
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _amountController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Monthly limit',
                    hintText: 'e.g. 3000',
                    prefixIcon: Icon(Icons.currency_rupee_rounded),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(value?.trim() ?? '');

                    if (amount == null || !amount.isFinite || amount <= 0) {
                      return 'Enter a limit greater than zero';
                    }

                    return null;
                  },
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
          icon: const Icon(Icons.check_rounded),
          label: const Text('Save Budget'),
        ),
      ],
    );
  }
}

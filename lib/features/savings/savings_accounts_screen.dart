import 'package:flutter/material.dart';

import '../../models/savings_entry.dart';
import '../../models/savings_goal.dart';
import '../../services/database_service.dart';
import '../../services/notification_service.dart';

class SavingsAccountsScreen extends StatefulWidget {
  const SavingsAccountsScreen({super.key});

  @override
  State<SavingsAccountsScreen> createState() => _SavingsAccountsScreenState();
}

class _SavingsAccountsScreenState extends State<SavingsAccountsScreen> {
  final DatabaseService _database = DatabaseService.instance;

  List<SavingsEntry> _entries = [];
  List<SavingsGoal> _goals = [];

  double _cashAvailable = 0;
  double _onlineAvailable = 0;

  bool _isLoading = true;
  String? _loadError;

  double get _cashSavings => _entries
      .where((entry) => entry.paymentMode == 'Cash')
      .fold(0.0, (sum, entry) => sum + entry.amount);

  double get _onlineSavings => _entries
      .where((entry) => entry.paymentMode == 'Online')
      .fold(0.0, (sum, entry) => sum + entry.amount);

  double get _totalSavings => _cashSavings + _onlineSavings;

  String _money(double amount) => '₹ ${amount.toStringAsFixed(2)}';

  String _dateLabel(DateTime date) => '${date.day}/${date.month}/${date.year}';

  String _entryTypeLabel(String type) {
    switch (type) {
      case 'existing':
        return 'Existing savings';
      case 'transfer':
        return 'Transfer from available balance';
      case 'rollover':
        return 'Month-end rollover';
      default:
        return 'Savings entry';
    }
  }

  IconData _entryTypeIcon(String type) {
    switch (type) {
      case 'existing':
        return Icons.savings_outlined;
      case 'transfer':
        return Icons.swap_horiz_rounded;
      case 'rollover':
        return Icons.event_repeat_rounded;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

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

      final entries = await _database.getSavingsEntries();
      final goals = await _database.getSavingsGoals();

      final now = DateTime.now();

      final cashAvailable = await _database.getMonthlyAvailableBalance(
        paymentMode: 'Cash',
        month: now.month,
        year: now.year,
      );

      final onlineAvailable = await _database.getMonthlyAvailableBalance(
        paymentMode: 'Online',
        month: now.month,
        year: now.year,
      );

      if (!mounted) return;

      setState(() {
        _entries = entries;
        _goals = goals;
        _cashAvailable = cashAvailable;
        _onlineAvailable = onlineAvailable;
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      debugPrint('Failed to load savings: $error');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadError = 'Could not load savings. Please try again.';
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Map<int, SavingsGoal> _goalSnapshot() {
    return {
      for (final goal in _goals)
        if (goal.id != null) goal.id!: goal,
    };
  }

  Future<void> _notifyNewlyCompletedGoals(Map<int, SavingsGoal> before) async {
    final afterGoals = await _database.getSavingsGoals();

    for (final goal in afterGoals) {
      final id = goal.id;
      if (id == null) continue;

      final previous = before[id];
      if (previous == null) continue;

      final wasComplete = previous.savedAmount >= previous.targetAmount;
      final isComplete = goal.savedAmount >= goal.targetAmount;

      if (!wasComplete && isComplete) {
        await NotificationService.instance.showGoalCompleted(
          goalId: id,
          goalTitle: goal.title,
        );
      }
    }
  }

  bool _canManageEntry(SavingsEntry entry) {
    if (entry.entryType == 'rollover') return false;

    // Once the month is closed, transfer records are historical.
    if (entry.entryType == 'transfer') {
      final now = DateTime.now();

      if (entry.month != now.month || entry.year != now.year) {
        return false;
      }
    }

    return true;
  }

  Future<void> _openEntryDialog({SavingsEntry? existing}) async {
    // final now = DateTime.now();

    final entry = await showDialog<SavingsEntry>(
      context: context,
      builder: (_) => _SavingsEntryDialog(
        goals: _goals,
        cashAvailable: _cashAvailable,
        onlineAvailable: _onlineAvailable,
        existing: existing,
      ),
    );

    if (entry == null || !mounted) return;

    try {
      final before = _goalSnapshot();

      if (existing == null) {
        await _database.addSavingsEntry(
          amount: entry.amount,
          paymentMode: entry.paymentMode,
          entryType: entry.entryType,
          month: entry.month,
          year: entry.year,
          note: entry.note,
          goalId: entry.goalId,
        );
      } else {
        await _database.updateSavingsEntry(entry);
      }

      await _notifyNewlyCompletedGoals(before);
      await _loadData();

      _showMessage(
        existing == null
            ? 'Savings added successfully.'
            : 'Savings entry updated.',
      );
    } catch (error) {
      debugPrint('Saving entry operation failed: $error');
      _showMessage(_friendlyError(error));
    }
  }

  Future<void> _deleteEntry(SavingsEntry entry) async {
    if (entry.id == null) {
      _showMessage('Could not identify this savings entry.');
      return;
    }

    if (!_canManageEntry(entry)) {
      _showMessage('Closed-month rollover and transfer records are protected.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete savings entry?'),
        content: Text(
          entry.entryType == 'transfer'
              ? 'Deleting this transfer will remove its linked '
                    'Transactions record and restore the amount to '
                    'the current available balance. Any linked goal '
                    'progress will also be adjusted.'
              : 'This will remove the savings amount and adjust '
                    'the linked goal if one is selected. '
                    'Your available Cash/Online balance will not change.',
        ),
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
      final before = _goalSnapshot();

      await _database.deleteSavingsEntry(entry.id!);

      await _notifyNewlyCompletedGoals(before);
      await _loadData();

      _showMessage('Savings entry deleted.');
    } catch (error) {
      debugPrint('Deleting savings entry failed: $error');
      _showMessage(_friendlyError(error));
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();

    if (message.contains('Insufficient')) {
      return message.replaceFirst('Bad state: ', '');
    }

    if (message.contains('closed month') ||
        message.contains('already closed') ||
        message.contains('rollover records')) {
      return message.replaceFirst('Bad state: ', '');
    }

    if (error is ArgumentError) {
      return error.message?.toString() ?? 'Invalid savings details.';
    }

    return 'Could not complete this savings operation.';
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
              Icon(Icons.error_outline_rounded, size: 42, color: colors.error),
              const SizedBox(height: 12),
              Text(_loadError!, textAlign: TextAlign.center),
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
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          Text(
            'Keep your saved money organised.',
            style: TextStyle(
              color: colors.onSurface.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),

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
                const Row(
                  children: [
                    Icon(Icons.savings_rounded, color: Color(0xFFD0F6E8)),
                    SizedBox(width: 9),
                    Text(
                      'TOTAL SAVINGS',
                      style: TextStyle(
                        color: Color(0xFFD0F6E8),
                        letterSpacing: 1.2,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _money(_totalSavings),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _SavingsAccountCard(
                        title: 'Cash Savings',
                        amount: _money(_cashSavings),
                        icon: Icons.payments_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SavingsAccountCard(
                        title: 'Online Savings',
                        amount: _money(_onlineSavings),
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          FilledButton.icon(
            onPressed: () => _openEntryDialog(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Savings'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Savings Activity',
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Edit or delete manual entries. Transfer records also '
            'stay connected to Transactions and the selected goal.',
            style: TextStyle(
              color: colors.onSurface.withValues(alpha: 0.65),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),

          if (_entries.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.savings_outlined,
                      color: colors.primary,
                      size: 36,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No savings recorded yet',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Add existing savings, transfer available money, '
                      'or wait for month-end rollover.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.65),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._entries.map((entry) {
              final canManage = _canManageEntry(entry);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: colors.primary.withValues(alpha: 0.12),
                    child: Icon(
                      _entryTypeIcon(entry.entryType),
                      color: colors.primary,
                      size: 21,
                    ),
                  ),
                  title: Text(
                    entry.note.isEmpty
                        ? _entryTypeLabel(entry.entryType)
                        : entry.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      '${_entryTypeLabel(entry.entryType)} • '
                      '${entry.paymentMode} • '
                      '${_dateLabel(entry.createdAt)}'
                      '${entry.goalId != null ? ' • Goal linked' : ''}',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.65),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  trailing: SizedBox(
                    width: 132,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '+${_money(entry.amount)}',
                              style: TextStyle(
                                color: colors.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        if (canManage)
                          PopupMenuButton<String>(
                            tooltip: 'Savings entry options',
                            onSelected: (value) {
                              if (value == 'edit') {
                                _openEntryDialog(existing: entry);
                              } else if (value == 'delete') {
                                _deleteEntry(entry);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 19),
                                    SizedBox(width: 10),
                                    Text('Edit'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline_rounded,
                                      size: 19,
                                    ),
                                    SizedBox(width: 10),
                                    Text('Delete'),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.lock_outline_rounded,
                              size: 17,
                              color: colors.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),

          const SizedBox(height: 12),

          Text(
            'Existing savings never change available balance. '
            'Transfers and month-end rollovers have linked transaction '
            'records. Closed-month rollover entries are read-only.',
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
}

class _SavingsAccountCard extends StatelessWidget {
  final String title;
  final String amount;
  final IconData icon;

  const _SavingsAccountCard({
    required this.title,
    required this.amount,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
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
          Icon(icon, color: const Color(0xFFD0F6E8), size: 20),
          const SizedBox(height: 9),
          Text(
            title,
            style: const TextStyle(color: Color(0xFFD0F6E8), fontSize: 11),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavingsEntryDialog extends StatefulWidget {
  final List<SavingsGoal> goals;
  final double cashAvailable;
  final double onlineAvailable;
  final SavingsEntry? existing;

  const _SavingsEntryDialog({
    required this.goals,
    required this.cashAvailable,
    required this.onlineAvailable,
    this.existing,
  });

  @override
  State<_SavingsEntryDialog> createState() => _SavingsEntryDialogState();
}

class _SavingsEntryDialogState extends State<_SavingsEntryDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _amountController;
  late final TextEditingController _noteController;

  late String _entryType;
  late String _paymentMode;
  late int? _goalId;

  bool get _isEditing => widget.existing != null;

  bool get _allowTransfer {
    if (!_isEditing) return true;

    final old = widget.existing!;
    final now = DateTime.now();

    return old.month == now.month && old.year == now.year;
  }

  double get _selectedAvailable {
    var available = _paymentMode == 'Cash'
        ? widget.cashAvailable
        : widget.onlineAvailable;

    final old = widget.existing;

    // When editing a transfer, add its original amount back to
    // the displayed available amount if the payment mode is unchanged.
    if (old != null &&
        old.entryType == 'transfer' &&
        old.paymentMode == _paymentMode) {
      available += old.amount;
    }

    return available;
  }

  @override
  void initState() {
    super.initState();

    final old = widget.existing;
    final now = DateTime.now();

    _entryType = old?.entryType ?? 'existing';
    _paymentMode = old?.paymentMode ?? 'Cash';
    _goalId = old?.goalId;

    _amountController = TextEditingController(
      text: old == null ? '' : old.amount.toStringAsFixed(2),
    );

    _noteController = TextEditingController(text: old?.note ?? '');

    // A previously linked goal may have since been deleted.
    if (_goalId != null && !widget.goals.any((goal) => goal.id == _goalId)) {
      _goalId = null;
    }

    if (old == null) {
      _entryType = 'existing';
    }

    // Avoid unused local warnings while documenting the selected month.
    assert(now.month >= 1 && now.month <= 12);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final old = widget.existing;
    final now = DateTime.now();

    final month = _entryType == 'transfer'
        ? now.month
        : old?.month ?? now.month;

    final year = _entryType == 'transfer' ? now.year : old?.year ?? now.year;

    Navigator.of(context).pop(
      SavingsEntry(
        id: old?.id,
        transactionId: old?.transactionId,
        goalId: _goalId,
        amount: double.parse(_amountController.text.trim()),
        paymentMode: _paymentMode,
        entryType: _entryType,
        month: month,
        year: year,
        note: _noteController.text.trim(),
        createdAt: old?.createdAt ?? now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // final old = widget.existing;

    final remainingItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: 'existing',
        child: Text('Add existing savings'),
      ),
    ];

    if (_allowTransfer) {
      remainingItems.add(
        const DropdownMenuItem(
          value: 'transfer',
          child: Text('Transfer from available balance'),
        ),
      );
    }

    if (!remainingItems.any((item) => item.value == _entryType)) {
      _entryType = 'existing';
    }

    final goalItems = <DropdownMenuItem<int>>[
      const DropdownMenuItem<int>(value: 0, child: Text('No goal')),
      ...widget.goals
          .where((goal) => goal.id != null)
          .map(
            (goal) => DropdownMenuItem<int>(
              value: goal.id!,
              child: Text(goal.title, overflow: TextOverflow.ellipsis),
            ),
          ),
    ];

    return AlertDialog(
      title: Text(_isEditing ? 'Edit Savings' : 'Add Savings'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _entryType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Savings action',
                    prefixIcon: Icon(Icons.swap_horiz_rounded),
                  ),
                  items: remainingItems,
                  onChanged: (value) {
                    if (value == null) return;

                    setState(() {
                      _entryType = value;
                    });
                  },
                ),

                const SizedBox(height: 14),

                DropdownButtonFormField<String>(
                  initialValue: _paymentMode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Savings account',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'Online', child: Text('Online')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;

                    setState(() {
                      _paymentMode = value;
                    });
                  },
                ),

                if (_entryType == 'transfer') ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Available $_paymentMode balance: '
                      '${'₹ ${_selectedAvailable.toStringAsFixed(2)}'}',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                DropdownButtonFormField<int>(
                  initialValue: _goalId ?? 0,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Link to a goal (optional)',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  items: goalItems,
                  onChanged: (value) {
                    setState(() {
                      _goalId = value == null || value == 0 ? null : value;
                    });
                  },
                ),

                const SizedBox(height: 14),

                TextFormField(
                  controller: _amountController,
                  autofocus: !_isEditing,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    hintText: 'e.g. 2000',
                    prefixIcon: Icon(Icons.currency_rupee_rounded),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(value?.trim() ?? '');

                    if (amount == null || !amount.isFinite || amount <= 0) {
                      return 'Enter an amount greater than zero';
                    }

                    if (_entryType == 'transfer' &&
                        amount > _selectedAvailable + 0.000001) {
                      return 'Amount exceeds available balance';
                    }

                    if (_entryType == 'transfer' && _selectedAvailable <= 0) {
                      return 'No available balance to transfer';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 14),

                TextFormField(
                  controller: _noteController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'e.g. Emergency fund',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  _entryType == 'transfer'
                      ? 'A transfer reduces available balance, creates a '
                            'Transactions record and contributes to the '
                            'selected goal.'
                      : 'Existing savings do not reduce available balance. '
                            'Selecting a goal adds this amount to its progress.',
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.65),
                    fontSize: 11,
                    height: 1.5,
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
          icon: const Icon(Icons.check_rounded),
          label: Text(_isEditing ? 'Save Changes' : 'Save Savings'),
        ),
      ],
    );
  }
}

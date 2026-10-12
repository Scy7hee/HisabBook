import 'package:flutter/material.dart';

import '../../models/savings_goal.dart';
import '../../services/database_service.dart';
import '../../services/notification_service.dart';

class SavingsGoalsScreen extends StatefulWidget {
  const SavingsGoalsScreen({super.key});

  @override
  State<SavingsGoalsScreen> createState() => _SavingsGoalsScreenState();
}

class _SavingsGoalsScreenState extends State<SavingsGoalsScreen> {
  final DatabaseService _database = DatabaseService.instance;

  List<SavingsGoal> _goals = [];

  bool _isLoading = true;
  String? _loadError;

  double get _totalTarget =>
      _goals.fold(0.0, (sum, goal) => sum + goal.targetAmount);

  double get _totalSaved =>
      _goals.fold(0.0, (sum, goal) => sum + goal.savedAmount);

  double get _remaining => _goals.fold(
    0.0,
    (sum, goal) =>
        sum +
        (goal.targetAmount - goal.savedAmount)
            .clamp(0.0, double.infinity)
            .toDouble(),
  );

  String _money(double amount) => '₹ ${amount.toStringAsFixed(2)}';

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

  @override
  void initState() {
    super.initState();
    _loadGoals();
  }

  Future<void> _loadGoals({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      await _database.initialize();
      final goals = await _database.getSavingsGoals();

      if (!mounted) return;

      setState(() {
        _goals = goals;
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      debugPrint('Failed to load goals: $error');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadError = 'Could not load savings goals.';
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
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

  Map<int, SavingsGoal> _goalSnapshot() {
    return {
      for (final goal in _goals)
        if (goal.id != null) goal.id!: goal,
    };
  }

  Future<void> _createGoal() async {
    final result = await showDialog<SavingsGoal>(
      context: context,
      builder: (_) => const _SavingsGoalEditorDialog(),
    );

    if (result == null || !mounted) return;

    try {
      await _database.insertSavingsGoal(result);
      await _loadGoals();
      _showMessage('Savings goal created.');
    } catch (error) {
      debugPrint('Create goal failed: $error');
      _showMessage('Could not create the goal.');
    }
  }

  Future<void> _editGoal(SavingsGoal goal) async {
    final before = _goalSnapshot();

    final result = await showDialog<SavingsGoal>(
      context: context,
      builder: (_) => _SavingsGoalEditorDialog(existing: goal),
    );

    if (result == null || !mounted) return;

    try {
      await _database.updateSavingsGoal(result);
      await _notifyNewlyCompletedGoals(before);
      await _loadGoals();

      _showMessage('Savings goal updated.');
    } catch (error) {
      debugPrint('Edit goal failed: $error');
      _showMessage('Could not update the goal.');
    }
  }

  Future<void> _addSavings(SavingsGoal goal) async {
    if (goal.id == null) {
      _showMessage('Could not identify this goal.');
      return;
    }

    try {
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

      final result = await showDialog<_GoalContribution>(
        context: context,
        builder: (_) => _GoalContributionDialog(
          goal: goal,
          cashAvailable: cashAvailable,
          onlineAvailable: onlineAvailable,
        ),
      );

      if (result == null || !mounted) return;

      final before = _goalSnapshot();

      await _database.addSavingsEntry(
        amount: result.amount,
        paymentMode: result.paymentMode,
        entryType: result.entryType,
        month: now.month,
        year: now.year,
        note: result.note.isEmpty
            ? 'Contribution to ${goal.title}'
            : result.note,
        goalId: goal.id,
      );

      await _notifyNewlyCompletedGoals(before);
      await _loadGoals();

      _showMessage('${_money(result.amount)} added to ${goal.title}.');
    } catch (error) {
      debugPrint('Goal contribution failed: $error');
      _showMessage(_friendlyError(error));
    }
  }

  Future<void> _deleteGoal(SavingsGoal goal) async {
    if (goal.id == null) {
      _showMessage('Could not identify this goal.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete savings goal?'),
        content: Text(
          'Delete "${goal.title}"? Existing savings entries will remain '
          'in Savings Activity, but they will no longer be linked to '
          'this goal.',
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
      await _database.deleteSavingsGoal(goal.id!);
      await _loadGoals();

      _showMessage('Goal deleted. Saved money was preserved.');
    } catch (error) {
      debugPrint('Delete goal failed: $error');
      _showMessage('Could not delete the goal.');
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();

    if (message.contains('Insufficient')) {
      return message.replaceFirst('Bad state: ', '');
    }

    if (error is ArgumentError) {
      return error.message?.toString() ?? 'Invalid savings details.';
    }

    return 'Could not update this goal. Please try again.';
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
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _loadGoals(showLoading: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGoals,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          Text(
            'Save a little today for something bigger tomorrow.',
            style: TextStyle(
              color: colors.onSurface.withValues(alpha: 0.7),
              fontSize: 13,
              height: 1.4,
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
                      'TOTAL SAVINGS GOALS',
                      style: TextStyle(
                        color: Color(0xFFD0F6E8),
                        letterSpacing: 1.1,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _money(_totalSaved),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'saved towards ${_money(_totalTarget)} in goals',
                  style: const TextStyle(
                    color: Color(0xFFD0F6E8),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: _totalTarget <= 0
                        ? 0
                        : (_totalSaved / _totalTarget)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                    minHeight: 9,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.flag_outlined,
                      size: 17,
                      color: Color(0xFFD0F6E8),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${_goals.length} '
                        '${_goals.length == 1 ? 'goal' : 'goals'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      '${_money(_remaining)} to go',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: Text(
                  'Your Goals',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _createGoal,
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('New Goal'),
              ),
            ],
          ),

          const SizedBox(height: 14),

          if (_goals.isEmpty)
            _EmptyGoalsState(onCreateGoal: _createGoal)
          else
            ..._goals.map(
              (goal) => _SavingsGoalCard(
                goal: goal,
                money: _money,
                formatDate: _formatDate,
                onAddSavings: () => _addSavings(goal),
                onEdit: () => _editGoal(goal),
                onDelete: () => _deleteGoal(goal),
              ),
            ),

          const SizedBox(height: 12),

          Text(
            'Contributions from this screen are also recorded in '
            'Savings Activity. If a goal is selected during a savings '
            'entry, both the ledger and this progress update together.',
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

class _SavingsGoalCard extends StatelessWidget {
  final SavingsGoal goal;
  final String Function(double) money;
  final String Function(DateTime) formatDate;
  final VoidCallback onAddSavings;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SavingsGoalCard({
    required this.goal,
    required this.money,
    required this.formatDate,
    required this.onAddSavings,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final ratio = goal.savedAmount / goal.targetAmount;
    final progress = ratio.clamp(0.0, 1.0).toDouble();
    final isComplete = goal.savedAmount >= goal.targetAmount;

    final remaining = (goal.targetAmount - goal.savedAmount)
        .clamp(0.0, double.infinity)
        .toDouble();

    final isOverdue =
        !isComplete &&
        goal.targetDate != null &&
        DateTime(
          goal.targetDate!.year,
          goal.targetDate!.month,
          goal.targetDate!.day,
        ).isBefore(
          DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          ),
        );

    final progressColor = isComplete
        ? colors.primary
        : isOverdue
        ? colors.error
        : Colors.teal;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: progressColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isComplete
                        ? Icons.check_circle_outline_rounded
                        : Icons.savings_outlined,
                    color: progressColor,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (goal.targetDate != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Target date: ${formatDate(goal.targetDate!)}',
                            style: TextStyle(
                              color: colors.onSurface.withValues(alpha: 0.65),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Goal options',
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 19),
                          SizedBox(width: 10),
                          Text('Edit goal'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 19),
                          SizedBox(width: 10),
                          Text('Delete goal'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        money(goal.savedAmount),
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'of ${money(goal.targetAmount)} saved',
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
                  '${(ratio * 100).round()}%',
                  style: TextStyle(
                    color: progressColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 9,
                backgroundColor: colors.onSurface.withValues(alpha: 0.08),
                color: progressColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isComplete
                  ? 'Goal completed! Great work.'
                  : isOverdue
                  ? 'Target date passed • ${money(remaining)} remaining'
                  : '${money(remaining)} left to reach your goal',
              style: TextStyle(
                color: progressColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAddSavings,
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('Add Savings'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyGoalsState extends StatelessWidget {
  final VoidCallback onCreateGoal;

  const _EmptyGoalsState({required this.onCreateGoal});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              height: 64,
              width: 64,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.savings_rounded,
                color: colors.primary,
                size: 31,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Every big dream starts small',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a goal for a phone, trip, laptop or emergency '
              'fund, then track your progress over time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.65),
                height: 1.5,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCreateGoal,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create Your First Goal'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavingsGoalEditorDialog extends StatefulWidget {
  final SavingsGoal? existing;

  const _SavingsGoalEditorDialog({this.existing});

  @override
  State<_SavingsGoalEditorDialog> createState() =>
      _SavingsGoalEditorDialogState();
}

class _SavingsGoalEditorDialogState extends State<_SavingsGoalEditorDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _targetController;

  DateTime? _targetDate;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(
      text: widget.existing?.title ?? '',
    );

    _targetController = TextEditingController(
      text: widget.existing == null
          ? ''
          : widget.existing!.targetAmount.toStringAsFixed(2),
    );

    _targetDate = widget.existing?.targetDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select target date',
    );

    if (picked != null && mounted) {
      setState(() {
        _targetDate = picked;
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final target = double.parse(_targetController.text.trim());
    final existing = widget.existing;

    Navigator.of(context).pop(
      SavingsGoal(
        id: existing?.id,
        title: _titleController.text.trim(),
        targetAmount: target,
        // Keep progress when the goal details or target are edited.
        savedAmount: existing?.savedAmount ?? 0,
        targetDate: _targetDate,
        createdAt: existing?.createdAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(_isEditing ? 'Edit Savings Goal' : 'Create Savings Goal'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Goal name',
                    hintText: 'e.g. Buy a new laptop',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a goal name';
                    }
                    if (value.trim().length > 60) {
                      return 'Keep the name under 60 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _targetController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Target amount',
                    hintText: 'e.g. 25000',
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
                const SizedBox(height: 15),
                OutlinedButton.icon(
                  onPressed: _pickTargetDate,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(
                    _targetDate == null
                        ? 'Add target date (optional)'
                        : 'Target: ${_targetDate!.day}/'
                              '${_targetDate!.month}/'
                              '${_targetDate!.year}',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (_targetDate != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _targetDate = null;
                        });
                      },
                      child: const Text('Remove target date'),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Saved progress is retained when you change the target.',
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
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
          label: Text(_isEditing ? 'Save Changes' : 'Create Goal'),
        ),
      ],
    );
  }
}

class _GoalContribution {
  final double amount;
  final String paymentMode;
  final String entryType;
  final String note;

  const _GoalContribution({
    required this.amount,
    required this.paymentMode,
    required this.entryType,
    required this.note,
  });
}

class _GoalContributionDialog extends StatefulWidget {
  final SavingsGoal goal;
  final double cashAvailable;
  final double onlineAvailable;

  const _GoalContributionDialog({
    required this.goal,
    required this.cashAvailable,
    required this.onlineAvailable,
  });

  @override
  State<_GoalContributionDialog> createState() =>
      _GoalContributionDialogState();
}

class _GoalContributionDialogState extends State<_GoalContributionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  String _entryType = 'existing';
  String _paymentMode = 'Cash';

  double get _available =>
      _paymentMode == 'Cash' ? widget.cashAvailable : widget.onlineAvailable;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      _GoalContribution(
        amount: double.parse(_amountController.text.trim()),
        paymentMode: _paymentMode,
        entryType: _entryType,
        note: _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Add to Goal'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.goal.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_money(widget.goal.savedAmount)} of '
                  '${_money(widget.goal.targetAmount)} saved',
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: _entryType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Savings action',
                    prefixIcon: Icon(Icons.swap_horiz_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'existing',
                      child: Text('Add existing savings'),
                    ),
                    DropdownMenuItem(
                      value: 'transfer',
                      child: Text('Transfer from available balance'),
                    ),
                  ],
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
                    labelText: 'Payment mode',
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
                  Text(
                    'Available $_paymentMode balance: '
                    '${_money(_available)}',
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                TextFormField(
                  controller: _amountController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount to add',
                    hintText: 'e.g. 500',
                    prefixIcon: Icon(Icons.currency_rupee_rounded),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(value?.trim() ?? '');

                    if (amount == null || !amount.isFinite || amount <= 0) {
                      return 'Enter an amount greater than zero';
                    }

                    if (_entryType == 'transfer' &&
                        amount > _available + 0.000001) {
                      return 'Amount exceeds available balance';
                    }

                    if (_entryType == 'transfer' && _available <= 0) {
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
                    hintText: 'e.g. Monthly contribution',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  _entryType == 'transfer'
                      ? 'This adds to the goal, reduces the selected '
                            'available balance and creates a Transactions '
                            'record.'
                      : 'This adds to the goal and savings ledger without '
                            'changing available balance.',
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
          label: const Text('Add Contribution'),
        ),
      ],
    );
  }

  String _money(double amount) => '₹ ${amount.toStringAsFixed(2)}';
}

import 'package:flutter/material.dart';

import '../../models/udhaar_entry.dart';
import '../../models/udhaar_person.dart';
import '../../services/database_service.dart';

class UdhaarScreen extends StatefulWidget {
  const UdhaarScreen({super.key});

  @override
  State<UdhaarScreen> createState() => _UdhaarScreenState();
}

class _UdhaarScreenState extends State<UdhaarScreen> {
  final DatabaseService _database = DatabaseService.instance;
  List<UdhaarPerson> _people = [];
  bool _isLoading = true;
  String? _loadError;
  int _filter = 0;

  double get _totalReceivable =>
      _people.fold(0, (sum, person) => sum + person.receivableBalance);

  double get _totalPayable =>
      _people.fold(0, (sum, person) => sum + person.payableBalance);

  String _money(double value) => '₹${value.toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  Future<void> _loadPeople({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      await _database.initialize();
      final people = await _database.getUdhaarPeople();
      if (!mounted) {
        return;
      }
      setState(() {
        _people = people;
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      debugPrint('Could not load Udhaar people: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load Udhaar. Please try again.';
      });
    }
  }

  Future<void> _addPerson() async {
    final result = await showDialog<_PersonFormResult>(
      context: context,
      builder: (_) => const _PersonDialog(),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      await _database.insertUdhaarPerson(name: result.name, note: result.note);
      await _loadPeople();
      _showMessage('${result.name} added to Udhaar.');
    } catch (error) {
      _showMessage(_friendlyError(error));
    }
  }

  Future<void> _openPerson(UdhaarPerson person) async {
    if (person.id == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UdhaarPersonScreen(personId: person.id!),
      ),
    );
    if (mounted) {
      await _loadPeople();
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '');
    if (error is ArgumentError || error is StateError) {
      return message;
    }
    return 'Something went wrong. Please try again.';
  }

  List<UdhaarPerson> get _filteredPeople {
    switch (_filter) {
      case 1:
        return _people
            .where((person) => person.receivableBalance > 0.000001)
            .toList();
      case 2:
        return _people
            .where((person) => person.payableBalance > 0.000001)
            .toList();
      default:
        return _people;
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
              Icon(Icons.error_outline_rounded, size: 42, color: colors.error),
              const SizedBox(height: 12),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _loadPeople(showLoading: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final people = _filteredPeople;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPerson,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add person'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadPeople,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
          children: [
            Text(
              'Every person, every rupee, one clear history.',
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
                  colors: [Color(0xFF173E53), Color(0xFF176D67)],
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
                      Icon(Icons.account_balance_rounded, color: Colors.white),
                      SizedBox(width: 9),
                      Text(
                        'UDHAAR OVERVIEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _OverviewAmount(
                          label: 'Total lena hai',
                          amount: _money(_totalReceivable),
                          helper: 'Expected back',
                          icon: Icons.south_west_rounded,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _OverviewAmount(
                          label: 'Total dena hai',
                          amount: _money(_totalPayable),
                          helper: 'You owe',
                          icon: Icons.north_east_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${_people.length} ${_people.length == 1 ? 'person' : 'people'} in your ledger',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'People',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _addPerson,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _filterChip('All', 0),
                _filterChip('Lena hai', 1),
                _filterChip('Dena hai', 2),
              ],
            ),
            const SizedBox(height: 12),
            if (people.isEmpty)
              _EmptyPeopleCard(
                hasPeople: _people.isNotEmpty,
                filter: _filter,
                onAdd: _addPerson,
              )
            else
              ...people.map(
                (person) => _PersonCard(
                  person: person,
                  money: _money,
                  onTap: () => _openPerson(person),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Wallet entries appear in Transactions. Savings-based entries change Savings only, never the Dashboard wallet balance. Edit or delete linked entries from this Udhaar ledger.',
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.55),
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String title, int value) {
    return ChoiceChip(
      label: Text(title),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }
}

class UdhaarPersonScreen extends StatefulWidget {
  final int personId;

  const UdhaarPersonScreen({super.key, required this.personId});

  @override
  State<UdhaarPersonScreen> createState() => _UdhaarPersonScreenState();
}

class _UdhaarPersonScreenState extends State<UdhaarPersonScreen> {
  final DatabaseService _database = DatabaseService.instance;
  UdhaarPerson? _person;
  List<UdhaarEntry> _entries = [];
  bool _isLoading = true;
  String? _loadError;

  String _money(double value) => '₹${value.toStringAsFixed(2)}';
  String _dateLabel(DateTime date) => '${date.day}/${date.month}/${date.year}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      await _database.initialize();
      final person = await _database.getUdhaarPerson(widget.personId);
      final entries = await _database.getUdhaarEntries(widget.personId);
      if (!mounted) {
        return;
      }
      setState(() {
        _person = person;
        _entries = entries;
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      debugPrint('Could not load Udhaar details: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load this person’s history.';
      });
    }
  }

  Future<void> _editPerson() async {
    final person = _person;
    if (person == null || person.id == null) {
      return;
    }
    final result = await showDialog<_PersonFormResult>(
      context: context,
      builder: (_) => _PersonDialog(existing: person),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      await _database.updateUdhaarPerson(
        id: person.id!,
        name: result.name,
        note: result.note,
      );
      await _load();
      if (mounted) {
        _showMessage('Person details updated.');
      }
    } catch (error) {
      _showMessage(_friendlyError(error));
    }
  }

  Future<void> _addOrEditEntry({UdhaarEntry? existing}) async {
    final person = _person;
    if (person == null || person.id == null) {
      return;
    }
    final result = await showDialog<UdhaarEntry>(
      context: context,
      builder: (_) => _UdhaarEntryDialog(person: person, existing: existing),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      if (existing == null) {
        await _database.addUdhaarEntry(
          personId: result.personId,
          entryType: result.entryType,
          accountType: result.accountType,
          paymentMode: result.paymentMode,
          amount: result.amount,
          date: result.date,
          purpose: result.purpose,
          note: result.note,
        );
      } else {
        await _database.updateUdhaarEntry(result);
      }
      await _load();
      if (mounted) {
        _showMessage(
          existing == null ? 'Udhaar entry added.' : 'Udhaar entry updated.',
        );
      }
    } catch (error) {
      _showMessage(_friendlyError(error));
    }
  }

  Future<void> _deleteEntry(UdhaarEntry entry) async {
    if (entry.id == null) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this history entry?'),
        content: const Text(
          'The linked Wallet transaction or Savings movement will also be removed. The person’s outstanding total will be recalculated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete entry'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }
    try {
      await _database.deleteUdhaarEntry(entry.id!);
      await _load();
      if (mounted) {
        _showMessage('Entry deleted.');
      }
    } catch (error) {
      _showMessage(_friendlyError(error));
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '');
    if (error is ArgumentError || error is StateError) {
      return message;
    }
    return 'Something went wrong. Please try again.';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final person = _person;
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Udhaar details')),
        body: Center(child: CircularProgressIndicator(color: colors.primary)),
      );
    }
    if (_loadError != null || person == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Udhaar details')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError ?? 'This person could not be found.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _load(showLoading: true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(person.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit person details',
            onPressed: _editPerson,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditEntry(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add entry'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
          children: [
            if (person.note.isNotEmpty) ...[
              Text(
                person.note,
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PERSON SUMMARY',
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.6),
                      fontSize: 11,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCell(
                          label: 'Total diya',
                          amount: _money(person.totalLent),
                        ),
                      ),
                      Expanded(
                        child: _SummaryCell(
                          label: 'Wapas mila',
                          amount: _money(person.totalCollected),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCell(
                          label: 'Lena baaki',
                          amount: _money(person.receivableBalance),
                          highlight: true,
                        ),
                      ),
                      Expanded(
                        child: _SummaryCell(
                          label: 'Dena baaki',
                          amount: _money(person.payableBalance),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 26),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCell(
                          label: 'Total liya',
                          amount: _money(person.totalBorrowed),
                        ),
                      ),
                      Expanded(
                        child: _SummaryCell(
                          label: 'Wapas kiya',
                          amount: _money(person.totalRepaid),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Complete history',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${_entries.length} entries',
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_entries.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 38,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No history yet',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Add an Udhaar given, Udhaar taken, or repayment entry.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.65),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._entries.map(
                (entry) => _UdhaarHistoryCard(
                  entry: entry,
                  money: _money,
                  dateLabel: _dateLabel,
                  onEdit: () => _addOrEditEntry(existing: entry),
                  onDelete: () => _deleteEntry(entry),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Repayments cannot exceed the outstanding amount. Changes to a Wallet entry are also synchronised with Transactions. Savings movements are updated here so they cannot be double-counted.',
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.55),
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewAmount extends StatelessWidget {
  final String label;
  final String amount;
  final String helper;
  final IconData icon;

  const _OverviewAmount({
    required this.label,
    required this.amount,
    required this.helper,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 18),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            amount,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          helper,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _PersonCard extends StatelessWidget {
  final UdhaarPerson person;
  final String Function(double) money;
  final VoidCallback onTap;

  const _PersonCard({
    required this.person,
    required this.money,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final receivable = person.receivableBalance;
    final payable = person.payableBalance;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        onTap: onTap,
        leading: CircleAvatar(
          radius: 23,
          backgroundColor: colors.primary.withValues(alpha: 0.12),
          child: Text(
            person.name.trim().isEmpty
                ? '?'
                : person.name.trim()[0].toUpperCase(),
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: Text(
          person.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Wrap(
            spacing: 8,
            runSpacing: 5,
            children: [
              if (receivable > 0.000001)
                _BalanceTag(
                  label: 'Lena ${money(receivable)}',
                  color: Colors.green,
                ),
              if (payable > 0.000001)
                _BalanceTag(
                  label: 'Dena ${money(payable)}',
                  color: colors.error,
                ),
              if (receivable <= 0.000001 && payable <= 0.000001)
                const _BalanceTag(label: 'Settled', color: Colors.blueGrey),
            ],
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: colors.onSurface.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _BalanceTag extends StatelessWidget {
  final String label;
  final Color color;

  const _BalanceTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyPeopleCard extends StatelessWidget {
  final bool hasPeople;
  final int filter;
  final VoidCallback onAdd;

  const _EmptyPeopleCard({
    required this.hasPeople,
    required this.filter,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.people_alt_outlined, color: colors.primary, size: 42),
            const SizedBox(height: 12),
            Text(
              hasPeople
                  ? (filter == 1 ? 'No money to collect' : 'No payments due')
                  : 'Start your Udhaar ledger',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              hasPeople
                  ? 'Nothing matches this filter right now.'
                  : 'Add a person to record money you lend or borrow, with the reason and full repayment history.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.65),
                fontSize: 12,
                height: 1.5,
              ),
            ),
            if (!hasPeople) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add first person'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String label;
  final String amount;
  final bool highlight;

  const _SummaryCell({
    required this.label,
    required this.amount,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.onSurface.withValues(alpha: 0.65),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          amount,
          style: TextStyle(
            color: highlight ? Colors.green : colors.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _UdhaarHistoryCard extends StatelessWidget {
  final UdhaarEntry entry;
  final String Function(double) money;
  final String Function(DateTime) dateLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _UdhaarHistoryCard({
    required this.entry,
    required this.money,
    required this.dateLabel,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final incoming = entry.isIncomingWalletFlow;
    final movementIcon = incoming
        ? Icons.south_west_rounded
        : Icons.north_east_rounded;
    final movementColor = incoming ? Colors.green : colors.error;
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 5, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: movementColor.withValues(alpha: 0.10),
              child: Icon(movementIcon, color: movementColor, size: 18),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.typeLabel,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (entry.purpose.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        entry.purpose,
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.78),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      '${dateLabel(entry.date)} • ${entry.accountLabel} • ${entry.paymentMode}',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.58),
                        fontSize: 10,
                      ),
                    ),
                    if (entry.note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.note,
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.62),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(height: 3),
                Text(
                  money(entry.amount),
                  style: TextStyle(
                    color: movementColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    }
                    if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit entry')),
                    PopupMenuItem(value: 'delete', child: Text('Delete entry')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonFormResult {
  final String name;
  final String note;
  const _PersonFormResult(this.name, this.note);
}

class _PersonDialog extends StatefulWidget {
  final UdhaarPerson? existing;
  const _PersonDialog({this.existing});

  @override
  State<_PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends State<_PersonDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _noteController = TextEditingController(text: widget.existing?.note ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add person' : 'Edit person'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter a name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }
            Navigator.of(context).pop(
              _PersonFormResult(
                _nameController.text.trim(),
                _noteController.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _UdhaarEntryDialog extends StatefulWidget {
  final UdhaarPerson person;
  final UdhaarEntry? existing;

  const _UdhaarEntryDialog({required this.person, this.existing});

  @override
  State<_UdhaarEntryDialog> createState() => _UdhaarEntryDialogState();
}

class _UdhaarEntryDialogState extends State<_UdhaarEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _purposeController;
  late final TextEditingController _noteController;
  late String _entryType;
  late String _accountType;
  late String _paymentMode;
  late DateTime _date;

  bool get _editing => widget.existing != null;

  double get _repaymentLimit {
    var available = _entryType == 'lent_repayment'
        ? widget.person.receivableBalance
        : _entryType == 'borrowed_repayment'
        ? widget.person.payableBalance
        : double.infinity;
    final old = widget.existing;
    if (old != null && old.entryType == _entryType) available += old.amount;
    return available;
  }

  @override
  void initState() {
    super.initState();
    final old = widget.existing;
    _entryType = old?.entryType ?? 'lent';
    _accountType = old?.accountType ?? 'wallet';
    _paymentMode = old?.paymentMode ?? 'Cash';
    _date = old?.date ?? DateTime.now();
    _amountController = TextEditingController(
      text: old == null ? '' : old.amount.toStringAsFixed(2),
    );
    _purposeController = TextEditingController(text: old?.purpose ?? '');
    _noteController = TextEditingController(text: old?.note ?? '');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _purposeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String get _accountActionLabel {
    if (_entryType == 'lent' || _entryType == 'borrowed_repayment') {
      return 'Money leaves';
    }
    return 'Money enters';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_editing ? 'Edit Udhaar entry' : 'Add Udhaar entry'),
      content: SizedBox(
        width: 460,
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
                    labelText: 'What happened?',
                    prefixIcon: Icon(Icons.swap_horiz_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'lent',
                      child: Text('I gave Udhaar'),
                    ),
                    DropdownMenuItem(
                      value: 'borrowed',
                      child: Text('I took Udhaar'),
                    ),
                    DropdownMenuItem(
                      value: 'lent_repayment',
                      child: Text('I got money back'),
                    ),
                    DropdownMenuItem(
                      value: 'borrowed_repayment',
                      child: Text('I repaid them'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _entryType = value ?? 'lent'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _accountType,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Account affected • $_accountActionLabel',
                    prefixIcon: const Icon(
                      Icons.account_balance_wallet_outlined,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'wallet',
                      child: Text('Current balance / Wallet'),
                    ),
                    DropdownMenuItem(
                      value: 'savings',
                      child: Text('Savings account'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _accountType = value ?? 'wallet'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Payment mode',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'Online', child: Text('Online')),
                  ],
                  onChanged: (value) =>
                      setState(() => _paymentMode = value ?? 'Cash'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  autofocus: !_editing,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixIcon: Icon(Icons.currency_rupee_rounded),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(value?.trim() ?? '');
                    if (amount == null || !amount.isFinite || amount <= 0) {
                      return 'Enter an amount greater than zero';
                    }
                    if (_entryType.endsWith('repayment') &&
                        amount > _repaymentLimit + 0.000001) {
                      return 'Repayment exceeds outstanding ${_repaymentLimit.isFinite ? _repaymentLimit.toStringAsFixed(2) : ''}';
                    }
                    return null;
                  },
                ),
                if (_entryType.endsWith('repayment')) ...[
                  const SizedBox(height: 7),
                  Text(
                    'Maximum repayment now: ${_repaymentLimit.isFinite ? _repaymentLimit.toStringAsFixed(2) : 'not applicable'}',
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.65),
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null && mounted) {
                      setState(
                        () => _date = DateTime(
                          picked.year,
                          picked.month,
                          picked.day,
                          _date.hour,
                          _date.minute,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(
                    'Date: ${_date.day}/${_date.month}/${_date.year}',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _purposeController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Purpose / Kis cheez ke liye?',
                    hintText: 'e.g. College fees, emergency',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Enter the reason or purpose'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Extra note (optional)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                Text(
                  _accountType == 'wallet'
                      ? 'This entry will be linked to Transactions and affect the current balance.'
                      : 'This entry will change Savings only. Dashboard available balance will not change.',
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.65),
                    fontSize: 11,
                    height: 1.4,
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
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }
            final now = DateTime.now();
            final old = widget.existing;
            Navigator.of(context).pop(
              UdhaarEntry(
                id: old?.id,
                personId: widget.person.id!,
                entryType: _entryType,
                accountType: _accountType,
                paymentMode: _paymentMode,
                amount: double.parse(_amountController.text.trim()),
                date: _date,
                purpose: _purposeController.text.trim(),
                note: _noteController.text.trim(),
                transactionId: old?.transactionId,
                savingsEntryId: old?.savingsEntryId,
                createdAt: old?.createdAt ?? now,
              ),
            );
          },
          icon: const Icon(Icons.check_rounded),
          label: Text(_editing ? 'Save changes' : 'Save entry'),
        ),
      ],
    );
  }
}

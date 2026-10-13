import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/database_service.dart';
import '../../services/notification_service.dart';
import '../budgets/budgets_reports_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../savings/savings_hub_screen.dart';
import '../transactions/transactions_screen.dart';
import '../udhaar/udhaar_screen.dart';

class AppShell extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const AppShell({super.key, required this.onToggleTheme});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _refreshVersion = 0;
  Timer? _monthTimer;
  static const List<_MenuItem> _items = [
    _MenuItem('Dashboard', Icons.space_dashboard_rounded),
    _MenuItem('Transactions', Icons.receipt_long_rounded),
    _MenuItem('Budgets & Reports', Icons.pie_chart_rounded),
    _MenuItem('Savings & Goals', Icons.savings_rounded),
    _MenuItem('Udhaar', Icons.people_alt_rounded),
    _MenuItem('Split Expenses', Icons.call_split_rounded),
    _MenuItem('Settings', Icons.settings_rounded),
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialiseAppServices());
    _scheduleNextMonthCheck();
  }

  Future<void> _initialiseAppServices() async {
    try {
      await DatabaseService.instance.initialize();
    } catch (error) {
      debugPrint('Initial database check failed: $error');
    }
    try {
      await NotificationService.instance.initializeAndScheduleDailyReminder();
    } catch (error) {
      debugPrint('Notification setup failed: $error');
    }
  }

  @override
  void dispose() {
    _monthTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkRollover(refreshPage: true));
      _scheduleNextMonthCheck();
    }
  }

  Future<void> _checkRollover({required bool refreshPage}) async {
    try {
      await DatabaseService.instance.initialize();
      if (!mounted || !refreshPage) return;
      setState(() {
        _refreshVersion++;
      });
    } catch (error) {
      debugPrint('Month-end rollover check failed: $error');
    }
  }

  void _scheduleNextMonthCheck() {
    _monthTimer?.cancel();
    final now = DateTime.now();
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);
    final delay = nextMonthStart.difference(now) + const Duration(seconds: 1);
    _monthTimer = Timer(delay, () async {
      await _checkRollover(refreshPage: true);
      if (mounted) {
        _scheduleNextMonthCheck();
      }
    });
  }

  void _selectPage(int index) {
    setState(() {
      _selectedIndex = index;
    });
    Navigator.of(context).pop();
  }

  void _openPage(int index) {
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          _items[_selectedIndex].title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Open menu',
            icon: const Icon(Icons.menu_rounded, size: 28),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        actions: [
          IconButton(
            tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
            onPressed: widget.onToggleTheme,
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: colors.primary,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 17,
              backgroundColor: colors.primary.withValues(alpha: 0.12),
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: colors.primary,
                size: 19,
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        width: 292,
        backgroundColor: colors.surface,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 16, 22),
                child: Row(
                  children: [
                    Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: colors.primary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HisabBook',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your money, made clear',
                            style: TextStyle(
                              color: colors.onSurface.withValues(alpha: 0.65),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(height: 1),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final isSelected = index == _selectedIndex;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        selected: isSelected,
                        selectedTileColor: colors.primary.withValues(
                          alpha: 0.12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                        leading: Icon(
                          item.icon,
                          color: isSelected
                              ? colors.primary
                              : colors.onSurface.withValues(alpha: 0.65),
                        ),
                        title: Text(
                          item.title,
                          style: TextStyle(
                            color: isSelected
                                ? colors.primary
                                : colors.onSurface,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.chevron_right_rounded,
                                color: colors.primary,
                              )
                            : null,
                        onTap: () => _selectPage(index),
                      ),
                    );
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 18),
                child: Text(
                  'PERSONAL FINANCE • BETA',
                  style: TextStyle(
                    color: Color(0xFF718096),
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _selectedIndex == 0
          ? DashboardScreen(
              key: ValueKey('dashboard-$_refreshVersion'),
              onSeeAllTransactions: () => _openPage(1),
            )
          : _selectedIndex == 1
          ? TransactionsScreen(key: ValueKey('transactions-$_refreshVersion'))
          : _selectedIndex == 2
          ? BudgetsReportsScreen(key: ValueKey('budgets-$_refreshVersion'))
          : _selectedIndex == 3
          ? SavingsHubScreen(key: ValueKey('savings-$_refreshVersion'))
          : _selectedIndex == 4
          ? UdhaarScreen(key: ValueKey('udhaar-$_refreshVersion'))
          : _PlaceholderScreen(
              title: _items[_selectedIndex].title,
              icon: _items[_selectedIndex].icon,
            ),
    );
  }
}

class _MenuItem {
  final String title;
  final IconData icon;
  const _MenuItem(this.title, this.icon);
}

class _PlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  const _PlaceholderScreen({required this.title, required this.icon});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 42, color: colors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This section is coming soon. '
              'We will build it step by step.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.65),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

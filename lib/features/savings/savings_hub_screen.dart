import 'package:flutter/material.dart';

import 'savings_accounts_screen.dart';
import 'savings_goals_screen.dart';

class SavingsHubScreen extends StatelessWidget {
  const SavingsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: colors.surface,
            child: TabBar(
              tabs: const [
                Tab(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  text: 'Savings Account',
                ),
                Tab(icon: Icon(Icons.flag_outlined), text: 'Goals'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [SavingsAccountsScreen(), SavingsGoalsScreen()],
            ),
          ),
        ],
      ),
    );
  }
}

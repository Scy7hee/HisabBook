import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import '../models/monthly_budget.dart';
import '../models/savings_entry.dart';
import '../models/savings_goal.dart';
import '../models/transaction.dart';
import '../models/udhaar_entry.dart';
import '../models/udhaar_person.dart';

class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();
  Database? _database;
  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final directory = await getDatabasesPath();
    final path = join(directory, 'hisab_book.db');
    return openDatabase(
      path,
      version: 7,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> initialize() async {
    final db = await database;
    await _backfillLegacySavingsTransactions(db);
    await _ensureMonthEndSavingsRollover(db);
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        isIncome INTEGER NOT NULL DEFAULT 0,
        paymentMode TEXT NOT NULL DEFAULT 'Cash',
        isUdhaar INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE
      )
    ''');
    await _createBudgetsTable(db);
    await _createSavingsGoalsTable(db);
    await _createSavingsEntriesTable(db, withLinks: true);
    await _createMonthlyClosuresTable(db);
    await _createUdhaarTables(db);
    final categoryBatch = db.batch();
    for (final category in ['Food', 'Travel', 'Shopping', 'Bills', 'Other']) {
      categoryBatch.insert('categories', {'name': category});
    }
    await categoryBatch.commit(noResult: true);
    // Seed sample transactions only for a fresh installation.
    final now = DateTime.now();
    final transactionBatch = db.batch();
    transactionBatch.insert('transactions', {
      'title': 'Food & Snacks',
      'category': 'Food',
      'amount': 150.0,
      'date': now.toIso8601String(),
      'isIncome': 0,
      'paymentMode': 'Cash',
    });
    transactionBatch.insert('transactions', {
      'title': 'Money from Home',
      'category': 'Income',
      'amount': 2000.0,
      'date': now.toIso8601String(),
      'isIncome': 1,
      'paymentMode': 'Cash',
    });
    transactionBatch.insert('transactions', {
      'title': 'Travel',
      'category': 'Travel',
      'amount': 80.0,
      'date': now.subtract(const Duration(days: 1)).toIso8601String(),
      'isIncome': 0,
      'paymentMode': 'Cash',
    });
    transactionBatch.insert('transactions', {
      'title': 'Previous Income',
      'category': 'Income',
      'amount': 13000.0,
      'date': now.subtract(const Duration(days: 3)).toIso8601String(),
      'isIncome': 1,
      'paymentMode': 'Online',
    });
    transactionBatch.insert('transactions', {
      'title': 'Other Expenses',
      'category': 'Other',
      'amount': 2270.0,
      'date': now.subtract(const Duration(days: 2)).toIso8601String(),
      'isIncome': 0,
      'paymentMode': 'Online',
    });
    await transactionBatch.commit(noResult: true);
  }

  Future<void> _createBudgetsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL COLLATE NOCASE,
        month INTEGER NOT NULL,
        year INTEGER NOT NULL,
        amount REAL NOT NULL CHECK (amount > 0),
        UNIQUE (category, month, year)
      )
    ''');
  }

  Future<void> _createSavingsGoalsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE savings_goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        targetAmount REAL NOT NULL CHECK (targetAmount > 0),
        savedAmount REAL NOT NULL DEFAULT 0 CHECK (savedAmount >= 0),
        targetDate TEXT,
        createdAt TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createSavingsEntriesTable(
    DatabaseExecutor db, {
    required bool withLinks,
  }) async {
    final linkColumns = withLinks
        ? '''
          transactionId INTEGER,
          goalId INTEGER,
        '''
        : '';
    await db.execute('''
      CREATE TABLE savings_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        $linkColumns
        amount REAL NOT NULL CHECK (amount > 0),
        paymentMode TEXT NOT NULL CHECK (
          paymentMode IN ('Cash', 'Online')
        ),
        entryType TEXT NOT NULL CHECK (
          entryType IN ('existing', 'transfer', 'rollover')
        ),
        movementType TEXT NOT NULL DEFAULT 'deposit',
        month INTEGER NOT NULL,
        year INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_savings_entries_month
      ON savings_entries (year, month, paymentMode, entryType)
    ''');
  }

  Future<void> _createUdhaarTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE udhaar_people (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE udhaar_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        personId INTEGER NOT NULL,
        entryType TEXT NOT NULL CHECK (entryType IN (
          'lent', 'borrowed', 'lent_repayment', 'borrowed_repayment'
        )),
        accountType TEXT NOT NULL CHECK (accountType IN ('wallet', 'savings')),
        paymentMode TEXT NOT NULL CHECK (paymentMode IN ('Cash', 'Online')),
        amount REAL NOT NULL CHECK (amount > 0),
        date TEXT NOT NULL,
        purpose TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        transactionId INTEGER,
        savingsEntryId INTEGER,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_udhaar_entries_person_date
      ON udhaar_entries (personId, date, id)
    ''');
  }

  Future<void> _createMonthlyClosuresTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE monthly_closures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        month INTEGER NOT NULL,
        year INTEGER NOT NULL,
        cashAmount REAL NOT NULL DEFAULT 0,
        onlineAmount REAL NOT NULL DEFAULT 0,
        closedAt TEXT NOT NULL,
        UNIQUE (year, month)
      )
    ''');
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE transactions
        ADD COLUMN paymentMode TEXT NOT NULL DEFAULT 'Cash'
      ''');
    }
    if (oldVersion < 3) {
      await _createBudgetsTable(db);
    }
    if (oldVersion < 4) {
      await _createSavingsGoalsTable(db);
    }
    if (oldVersion < 5) {
      await _createSavingsEntriesTable(db, withLinks: false);
      await _createMonthlyClosuresTable(db);
    }
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE savings_entries ADD COLUMN transactionId INTEGER',
      );
      await db.execute('ALTER TABLE savings_entries ADD COLUMN goalId INTEGER');
    }
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN isUdhaar INTEGER NOT NULL DEFAULT 0',
      );
      // v5+ databases already have savings_entries. Databases upgraded from
      // earlier versions get the latest savings_entries table above.
      if (oldVersion >= 5) {
        await db.execute(
          "ALTER TABLE savings_entries ADD COLUMN movementType TEXT NOT NULL DEFAULT 'deposit'",
        );
      }
      await _createUdhaarTables(db);
    }
  }

  // Link savings entries created before v6 to Transactions.
  // Each row is backfilled once because the transactionId is saved.
  Future<void> _backfillLegacySavingsTransactions(Database db) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'savings_entries',
        where: '''
          transactionId IS NULL
          AND entryType IN ('transfer', 'rollover')
        ''',
        orderBy: 'id ASC',
      );
      for (final row in rows) {
        final entry = SavingsEntry.fromMap(row);
        final DateTime transactionDate;
        if (entry.entryType == 'rollover') {
          transactionDate = DateTime(
            entry.year,
            entry.month + 1,
            0,
            23,
            59,
            59,
          );
        } else {
          transactionDate = entry.createdAt;
        }
        final transactionId = await txn.insert('transactions', {
          'title': entry.note.isEmpty
              ? (entry.entryType == 'rollover'
                    ? '${_monthName(entry.month)} ${entry.year} savings rollover'
                    : 'Transfer to Savings')
              : entry.note,
          'category': 'Savings',
          'amount': entry.amount,
          'date': transactionDate.toIso8601String(),
          'isIncome': 0,
          'paymentMode': entry.paymentMode,
        });
        await txn.update(
          'savings_entries',
          {'transactionId': transactionId},
          where: 'id = ?',
          whereArgs: [entry.id],
        );
      }
    });
  }

  // ============================================================
  // TRANSACTIONS
  // ============================================================
  Transaction _transactionFromMap(Map<String, Object?> row) {
    return Transaction(
      id: row['id'] as int,
      title: row['title'] as String,
      category: row['category'] as String,
      amount: (row['amount'] as num).toDouble(),
      date: DateTime.parse(row['date'] as String),
      isIncome: (row['isIncome'] as int) == 1,
      paymentMode: row['paymentMode'] as String? ?? 'Cash',
      isUdhaar: (row['isUdhaar'] as int? ?? 0) == 1,
    );
  }

  Map<String, Object?> _transactionToMap(Transaction transaction) {
    return {
      'title': transaction.title,
      'category': transaction.category,
      'amount': transaction.amount,
      'date': transaction.date.toIso8601String(),
      'isIncome': transaction.isIncome ? 1 : 0,
      'paymentMode': transaction.paymentMode,
      'isUdhaar': transaction.isUdhaar ? 1 : 0,
    };
  }

  Future<List<Transaction>> getTransactions() async {
    final db = await database;
    final rows = await db.query('transactions', orderBy: 'date DESC, id DESC');
    return rows.map(_transactionFromMap).toList();
  }

  Future<int> insertTransaction(Transaction transaction) async {
    final db = await database;
    return db.insert('transactions', _transactionToMap(transaction));
  }

  Future<int> updateTransaction(Transaction transaction) async {
    if (transaction.id == null) {
      throw ArgumentError('Cannot update a transaction without a database ID.');
    }
    if (!transaction.amount.isFinite || transaction.amount <= 0) {
      throw ArgumentError('Transaction amount must be greater than zero.');
    }
    final db = await database;
    return db.transaction((txn) async {
      final udhaarRows = await txn.query(
        'udhaar_entries',
        columns: ['id'],
        where: 'transactionId = ?',
        whereArgs: [transaction.id],
        limit: 1,
      );
      if (udhaarRows.isNotEmpty) {
        throw StateError(
          'Udhaar transactions must be edited from the Udhaar section.',
        );
      }
      final linkedRows = await txn.query(
        'savings_entries',
        where: 'transactionId = ?',
        whereArgs: [transaction.id],
        limit: 1,
      );
      if (linkedRows.isEmpty) {
        return txn.update(
          'transactions',
          _transactionToMap(transaction),
          where: 'id = ?',
          whereArgs: [transaction.id],
        );
      }
      final entry = SavingsEntry.fromMap(linkedRows.first);
      await _ensureTransferEntryEditable(txn, entry);
      if (transaction.date.year != entry.year ||
          transaction.date.month != entry.month) {
        throw StateError(
          'A linked savings transfer must stay in its original month.',
        );
      }
      var available = await _getMonthlyAvailableBalance(
        txn,
        paymentMode: transaction.paymentMode,
        month: entry.month,
        year: entry.year,
      );
      if (entry.paymentMode == transaction.paymentMode) {
        available += entry.amount;
      }
      if (transaction.amount > available + 0.000001) {
        throw StateError(
          'Insufficient ${transaction.paymentMode} available balance.',
        );
      }
      final syncedTransaction = Transaction(
        id: transaction.id,
        title: transaction.title,
        category: 'Savings',
        amount: transaction.amount,
        date: transaction.date,
        isIncome: false,
        paymentMode: transaction.paymentMode,
      );
      final affected = await txn.update(
        'transactions',
        _transactionToMap(syncedTransaction),
        where: 'id = ?',
        whereArgs: [transaction.id],
      );
      await txn.update(
        'savings_entries',
        {
          'amount': transaction.amount,
          'paymentMode': transaction.paymentMode,
          'note': transaction.title,
        },
        where: 'id = ?',
        whereArgs: [entry.id],
      );
      await _adjustGoalContribution(
        txn,
        oldGoalId: entry.goalId,
        oldAmount: entry.amount,
        newGoalId: entry.goalId,
        newAmount: transaction.amount,
      );
      return affected;
    });
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      final udhaarRows = await txn.query(
        'udhaar_entries',
        columns: ['id'],
        where: 'transactionId = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (udhaarRows.isNotEmpty) {
        throw StateError(
          'Udhaar transactions must be deleted from the Udhaar section.',
        );
      }
      final linkedRows = await txn.query(
        'savings_entries',
        where: 'transactionId = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (linkedRows.isNotEmpty) {
        final entry = SavingsEntry.fromMap(linkedRows.first);
        await _ensureTransferEntryEditable(txn, entry);
        await _adjustGoalContribution(
          txn,
          oldGoalId: entry.goalId,
          oldAmount: entry.amount,
          newGoalId: null,
          newAmount: 0,
        );
        await txn.delete(
          'savings_entries',
          where: 'id = ?',
          whereArgs: [entry.id],
        );
      }
      return txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ============================================================
  // CATEGORIES
  // ============================================================
  Future<List<String>> getCategories() async {
    final db = await database;
    final rows = await db.query('categories', orderBy: 'id ASC');
    return rows.map((row) => row['name'] as String).toList();
  }

  Future<void> addCategory(String name) async {
    final cleanedName = name.trim();
    if (cleanedName.isEmpty || cleanedName.toLowerCase() == 'income') {
      return;
    }
    final db = await database;
    await db.insert('categories', {
      'name': cleanedName,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<bool> deleteCategory(String name) async {
    final db = await database;
    final matchingTransactions = await db.query(
      'transactions',
      columns: ['id'],
      where: 'LOWER(category) = LOWER(?)',
      whereArgs: [name.trim()],
      limit: 1,
    );
    if (matchingTransactions.isNotEmpty) {
      return false;
    }
    await db.delete('categories', where: 'name = ?', whereArgs: [name.trim()]);
    return true;
  }

  // ============================================================
  // MONTHLY BUDGETS
  // ============================================================
  Future<List<MonthlyBudget>> getMonthlyBudgets({
    required int month,
    required int year,
  }) async {
    final db = await database;
    final rows = await db.query(
      'budgets',
      where: 'month = ? AND year = ?',
      whereArgs: [month, year],
      orderBy: 'category COLLATE NOCASE ASC',
    );
    return rows.map(MonthlyBudget.fromMap).toList();
  }

  Future<int> saveMonthlyBudget(MonthlyBudget budget) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'budgets',
        columns: ['id'],
        where: '''
          LOWER(category) = LOWER(?)
          AND month = ?
          AND year = ?
        ''',
        whereArgs: [budget.category.trim(), budget.month, budget.year],
        limit: 1,
      );
      final values = budget.toMap();
      values['category'] = budget.category.trim();
      if (rows.isNotEmpty) {
        final id = rows.first['id'] as int;
        return txn.update('budgets', values, where: 'id = ?', whereArgs: [id]);
      }
      return txn.insert('budgets', values);
    });
  }

  Future<int> deleteMonthlyBudget(int id) async {
    final db = await database;
    return db.delete('budgets', where: 'id = ?', whereArgs: [id]);
  }

  // ============================================================
  // SAVINGS GOALS
  // ============================================================
  Future<List<SavingsGoal>> getSavingsGoals() async {
    final db = await database;
    final rows = await db.query(
      'savings_goals',
      orderBy: '''
        CASE WHEN targetDate IS NULL THEN 1 ELSE 0 END,
        targetDate ASC,
        id DESC
      ''',
    );
    return rows.map(SavingsGoal.fromMap).toList();
  }

  Future<int> insertSavingsGoal(SavingsGoal goal) async {
    if (!goal.targetAmount.isFinite || goal.targetAmount <= 0) {
      throw ArgumentError('Target amount must be greater than zero.');
    }
    final db = await database;
    return db.insert('savings_goals', goal.toMap());
  }

  Future<int> updateSavingsGoal(SavingsGoal goal) async {
    if (goal.id == null) {
      throw ArgumentError(
        'Cannot update a savings goal without a database ID.',
      );
    }
    if (!goal.targetAmount.isFinite || goal.targetAmount <= 0) {
      throw ArgumentError('Target amount must be greater than zero.');
    }
    if (!goal.savedAmount.isFinite || goal.savedAmount < 0) {
      throw ArgumentError('Saved amount cannot be negative.');
    }
    final db = await database;
    return db.update(
      'savings_goals',
      goal.toMap(),
      where: 'id = ?',
      whereArgs: [goal.id],
    );
  }

  // Retained for compatibility with older callers.
  // New contribution flows should use addSavingsEntry instead.
  Future<int> addToSavingsGoal({
    required int id,
    required double amount,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Savings contribution must be greater than zero.');
    }
    final db = await database;
    return db.rawUpdate(
      '''
      UPDATE savings_goals
      SET savedAmount = savedAmount + ?
      WHERE id = ?
      ''',
      [amount, id],
    );
  }

  Future<int> deleteSavingsGoal(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.update(
        'savings_entries',
        {'goalId': null},
        where: 'goalId = ?',
        whereArgs: [id],
      );
      return txn.delete('savings_goals', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ============================================================
  // SAVINGS LEDGER
  // ============================================================
  Future<List<SavingsEntry>> getSavingsEntries() async {
    final db = await database;
    final rows = await db.query(
      'savings_entries',
      orderBy: 'createdAt DESC, id DESC',
    );
    return rows.map(SavingsEntry.fromMap).toList();
  }

  Future<int> addSavingsEntry({
    required double amount,
    required String paymentMode,
    required String entryType,
    required int month,
    required int year,
    String note = '',
    int? goalId,
  }) async {
    _validateSavingsEntry(
      amount: amount,
      paymentMode: paymentMode,
      entryType: entryType,
    );
    if (entryType == 'rollover') {
      throw ArgumentError(
        'Month-end rollover entries are created automatically.',
      );
    }
    final now = DateTime.now();
    if (entryType == 'transfer' && (month != now.month || year != now.year)) {
      throw StateError(
        'Transfers can only be made from the currently open month.',
      );
    }
    final db = await database;
    return db.transaction((txn) async {
      if (goalId != null) {
        final goalRows = await txn.query(
          'savings_goals',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [goalId],
          limit: 1,
        );
        if (goalRows.isEmpty) {
          throw StateError('The selected savings goal no longer exists.');
        }
      }
      int? transactionId;
      if (entryType == 'transfer') {
        if (await _isMonthClosed(txn, month, year)) {
          throw StateError('This month is already closed.');
        }
        final available = await _getMonthlyAvailableBalance(
          txn,
          paymentMode: paymentMode,
          month: month,
          year: year,
        );
        if (amount > available + 0.000001) {
          throw StateError(
            'Insufficient $paymentMode available balance. '
            'Available: ₹${available.toStringAsFixed(2)}',
          );
        }
        transactionId = await txn.insert('transactions', {
          'title': note.trim().isEmpty ? 'Transfer to Savings' : note.trim(),
          'category': 'Savings',
          'amount': amount,
          'date': now.toIso8601String(),
          'isIncome': 0,
          'paymentMode': paymentMode,
        });
      }
      final entryId = await txn.insert('savings_entries', {
        'transactionId': transactionId,
        'goalId': goalId,
        'amount': amount,
        'paymentMode': paymentMode,
        'entryType': entryType,
        'month': month,
        'year': year,
        'note': note.trim(),
        'createdAt': now.toIso8601String(),
      });
      if (goalId != null) {
        await txn.rawUpdate(
          '''
          UPDATE savings_goals
          SET savedAmount = savedAmount + ?
          WHERE id = ?
          ''',
          [amount, goalId],
        );
      }
      return entryId;
    });
  }

  Future<void> updateSavingsEntry(SavingsEntry entry) async {
    if (entry.id == null) {
      throw ArgumentError(
        'Cannot update a savings entry without a database ID.',
      );
    }
    if (entry.isUdhaarMovement) {
      throw StateError(
        'Udhaar-linked savings movements must be managed from the Udhaar section.',
      );
    }
    _validateSavingsEntry(
      amount: entry.amount,
      paymentMode: entry.paymentMode,
      entryType: entry.entryType,
    );
    if (entry.entryType == 'rollover') {
      throw StateError(
        'Month-end rollover records are protected from editing.',
      );
    }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'savings_entries',
        where: 'id = ?',
        whereArgs: [entry.id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('This savings entry no longer exists.');
      }
      final old = SavingsEntry.fromMap(rows.first);
      if (old.isUdhaarMovement) {
        throw StateError(
          'Udhaar-linked savings movements must be managed from the Udhaar section.',
        );
      }
      if (old.entryType == 'rollover') {
        throw StateError(
          'Month-end rollover records are protected from editing.',
        );
      }
      if (old.entryType == 'transfer') {
        await _ensureTransferEntryEditable(txn, old);
      }
      if (entry.entryType == 'transfer') {
        final now = DateTime.now();
        if (entry.month != now.month || entry.year != now.year) {
          throw StateError(
            'Transfers can only be edited in the currently open month.',
          );
        }
        if (await _isMonthClosed(txn, entry.month, entry.year)) {
          throw StateError('This month is already closed.');
        }
        var available = await _getMonthlyAvailableBalance(
          txn,
          paymentMode: entry.paymentMode,
          month: entry.month,
          year: entry.year,
        );
        if (old.entryType == 'transfer' &&
            old.paymentMode == entry.paymentMode &&
            old.month == entry.month &&
            old.year == entry.year) {
          available += old.amount;
        }
        if (entry.amount > available + 0.000001) {
          throw StateError(
            'Insufficient ${entry.paymentMode} available balance. '
            'Available for this edit: ₹${available.toStringAsFixed(2)}',
          );
        }
      }
      int? updatedTransactionId = old.transactionId;
      if (old.entryType == 'transfer' && entry.entryType == 'existing') {
        if (old.transactionId != null) {
          await txn.delete(
            'transactions',
            where: 'id = ?',
            whereArgs: [old.transactionId],
          );
        }
        updatedTransactionId = null;
      } else if (old.entryType == 'existing' && entry.entryType == 'transfer') {
        updatedTransactionId = await txn.insert('transactions', {
          'title': entry.note.trim().isEmpty
              ? 'Transfer to Savings'
              : entry.note.trim(),
          'category': 'Savings',
          'amount': entry.amount,
          'date': DateTime.now().toIso8601String(),
          'isIncome': 0,
          'paymentMode': entry.paymentMode,
        });
      } else if (old.entryType == 'transfer' && entry.entryType == 'transfer') {
        if (old.transactionId == null) {
          throw StateError('The linked savings transaction is missing.');
        }
        await txn.update(
          'transactions',
          {
            'title': entry.note.trim().isEmpty
                ? 'Transfer to Savings'
                : entry.note.trim(),
            'category': 'Savings',
            'amount': entry.amount,
            'date': old.createdAt.toIso8601String(),
            'isIncome': 0,
            'paymentMode': entry.paymentMode,
          },
          where: 'id = ?',
          whereArgs: [old.transactionId],
        );
      }
      await _adjustGoalContribution(
        txn,
        oldGoalId: old.goalId,
        oldAmount: old.amount,
        newGoalId: entry.goalId,
        newAmount: entry.amount,
      );
      await txn.update(
        'savings_entries',
        {
          'transactionId': updatedTransactionId,
          'goalId': entry.goalId,
          'amount': entry.amount,
          'paymentMode': entry.paymentMode,
          'entryType': entry.entryType,
          'month': entry.month,
          'year': entry.year,
          'note': entry.note.trim(),
        },
        where: 'id = ?',
        whereArgs: [entry.id],
      );
    });
  }

  Future<void> deleteSavingsEntry(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'savings_entries',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return;
      }
      final entry = SavingsEntry.fromMap(rows.first);
      if (entry.isUdhaarMovement) {
        throw StateError(
          'Udhaar-linked savings movements must be managed from the Udhaar section.',
        );
      }
      if (entry.entryType == 'rollover') {
        throw StateError(
          'Month-end rollover records are protected from deletion.',
        );
      }
      if (entry.entryType == 'transfer') {
        await _ensureTransferEntryEditable(txn, entry);
      }
      await _adjustGoalContribution(
        txn,
        oldGoalId: entry.goalId,
        oldAmount: entry.amount,
        newGoalId: null,
        newAmount: 0,
      );
      if (entry.transactionId != null) {
        await txn.delete(
          'transactions',
          where: 'id = ?',
          whereArgs: [entry.transactionId],
        );
      }
      await txn.delete('savings_entries', where: 'id = ?', whereArgs: [id]);
    });
  }

  void _validateSavingsEntry({
    required double amount,
    required String paymentMode,
    required String entryType,
  }) {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Savings amount must be greater than zero.');
    }
    if (paymentMode != 'Cash' && paymentMode != 'Online') {
      throw ArgumentError('Payment mode must be Cash or Online.');
    }
    if (!['existing', 'transfer', 'rollover'].contains(entryType)) {
      throw ArgumentError('Invalid savings entry type.');
    }
  }

  Future<void> _ensureTransferEntryEditable(
    DatabaseExecutor executor,
    SavingsEntry entry,
  ) async {
    if (entry.entryType == 'rollover') {
      throw StateError('Month-end rollover records are protected.');
    }
    final now = DateTime.now();
    if (entry.month != now.month || entry.year != now.year) {
      throw StateError(
        'This transfer belongs to a closed month and cannot be edited '
        'or deleted. Existing savings entries can still be managed.',
      );
    }
    if (await _isMonthClosed(executor, entry.month, entry.year)) {
      throw StateError('This month is already closed.');
    }
  }

  Future<bool> _isMonthClosed(
    DatabaseExecutor executor,
    int month,
    int year,
  ) async {
    final rows = await executor.query(
      'monthly_closures',
      columns: ['id'],
      where: 'month = ? AND year = ?',
      whereArgs: [month, year],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _adjustGoalContribution(
    DatabaseExecutor executor, {
    required int? oldGoalId,
    required double oldAmount,
    required int? newGoalId,
    required double newAmount,
  }) async {
    if (oldGoalId != null && oldGoalId == newGoalId) {
      final delta = newAmount - oldAmount;
      if (delta.abs() > 0.000001) {
        await executor.rawUpdate(
          '''
          UPDATE savings_goals
          SET savedAmount = MAX(0, savedAmount + ?)
          WHERE id = ?
          ''',
          [delta, oldGoalId],
        );
      }
      return;
    }
    if (oldGoalId != null && oldAmount > 0) {
      await executor.rawUpdate(
        '''
        UPDATE savings_goals
        SET savedAmount = MAX(0, savedAmount - ?)
        WHERE id = ?
        ''',
        [oldAmount, oldGoalId],
      );
    }
    if (newGoalId != null && newAmount > 0) {
      final goalRows = await executor.query(
        'savings_goals',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [newGoalId],
        limit: 1,
      );
      if (goalRows.isEmpty) {
        throw StateError('The selected savings goal no longer exists.');
      }
      await executor.rawUpdate(
        '''
        UPDATE savings_goals
        SET savedAmount = savedAmount + ?
        WHERE id = ?
        ''',
        [newAmount, newGoalId],
      );
    }
  }

  // ============================================================
  // UDHAAR: PEOPLE, LEDGER, AND LINKED WALLET/SAVINGS MOVEMENTS
  // ============================================================
  Future<List<UdhaarPerson>> getUdhaarPeople() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        p.id,
        p.name,
        p.note,
        p.createdAt,
        COALESCE(SUM(CASE WHEN e.entryType = 'lent' THEN e.amount ELSE 0 END), 0) AS totalLent,
        COALESCE(SUM(CASE WHEN e.entryType = 'lent_repayment' THEN e.amount ELSE 0 END), 0) AS totalCollected,
        COALESCE(SUM(CASE WHEN e.entryType = 'borrowed' THEN e.amount ELSE 0 END), 0) AS totalBorrowed,
        COALESCE(SUM(CASE WHEN e.entryType = 'borrowed_repayment' THEN e.amount ELSE 0 END), 0) AS totalRepaid
      FROM udhaar_people p
      LEFT JOIN udhaar_entries e ON e.personId = p.id
      GROUP BY p.id
      ORDER BY p.name COLLATE NOCASE ASC
    ''');
    return rows.map(UdhaarPerson.fromMap).toList();
  }

  Future<UdhaarPerson?> getUdhaarPerson(int id) async {
    final people = await getUdhaarPeople();
    for (final person in people) {
      if (person.id == id) {
        return person;
      }
    }
    return null;
  }

  Future<int> insertUdhaarPerson({
    required String name,
    String note = '',
  }) async {
    final cleanedName = name.trim();
    if (cleanedName.isEmpty) {
      throw ArgumentError('Person name cannot be empty.');
    }
    final db = await database;
    return db.insert('udhaar_people', {
      'name': cleanedName,
      'note': note.trim(),
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<int> updateUdhaarPerson({
    required int id,
    required String name,
    String note = '',
  }) async {
    final cleanedName = name.trim();
    if (cleanedName.isEmpty) {
      throw ArgumentError('Person name cannot be empty.');
    }
    final db = await database;
    return db.transaction((txn) async {
      final changed = await txn.update(
        'udhaar_people',
        {'name': cleanedName, 'note': note.trim()},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed == 0) {
        throw StateError('This person no longer exists.');
      }

      final linkedEntries = await txn.query(
        'udhaar_entries',
        where: 'personId = ?',
        whereArgs: [id],
      );
      for (final row in linkedEntries) {
        final entry = UdhaarEntry.fromMap(row);
        if (entry.transactionId != null) {
          await txn.update(
            'transactions',
            _udhaarWalletTransactionValues(
              personName: cleanedName,
              entryType: entry.entryType,
              paymentMode: entry.paymentMode,
              amount: entry.amount,
              date: entry.date,
              purpose: entry.purpose,
              note: entry.note,
            ),
            where: 'id = ?',
            whereArgs: [entry.transactionId],
          );
        }
        if (entry.savingsEntryId != null) {
          await txn.update(
            'savings_entries',
            _udhaarSavingsMovementValues(
              personName: cleanedName,
              entryType: entry.entryType,
              paymentMode: entry.paymentMode,
              amount: entry.amount,
              date: entry.date,
              purpose: entry.purpose,
              note: entry.note,
            ),
            where: 'id = ?',
            whereArgs: [entry.savingsEntryId],
          );
        }
      }
      return changed;
    });
  }

  Future<List<UdhaarEntry>> getUdhaarEntries(int personId) async {
    final db = await database;
    final rows = await db.query(
      'udhaar_entries',
      where: 'personId = ?',
      whereArgs: [personId],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(UdhaarEntry.fromMap).toList();
  }

  Future<int> addUdhaarEntry({
    required int personId,
    required String entryType,
    required String accountType,
    required String paymentMode,
    required double amount,
    required DateTime date,
    String purpose = '',
    String note = '',
  }) async {
    _validateUdhaarEntry(
      entryType: entryType,
      accountType: accountType,
      paymentMode: paymentMode,
      amount: amount,
    );
    final db = await database;
    return db.transaction((txn) async {
      final personRows = await txn.query(
        'udhaar_people',
        where: 'id = ?',
        whereArgs: [personId],
        limit: 1,
      );
      if (personRows.isEmpty) {
        throw StateError('This person no longer exists.');
      }
      final personName = personRows.first['name'] as String;
      await _validateUdhaarMovement(
        txn,
        accountType: accountType,
        paymentMode: paymentMode,
        entryType: entryType,
        amount: amount,
        date: date,
      );
      final now = DateTime.now();
      int? transactionId;
      int? savingsEntryId;
      if (accountType == 'wallet') {
        transactionId = await _insertUdhaarWalletTransaction(
          txn,
          personName: personName,
          entryType: entryType,
          paymentMode: paymentMode,
          amount: amount,
          date: date,
          purpose: purpose,
          note: note,
        );
      } else {
        savingsEntryId = await _insertUdhaarSavingsMovement(
          txn,
          personName: personName,
          entryType: entryType,
          paymentMode: paymentMode,
          amount: amount,
          date: date,
          purpose: purpose,
          note: note,
        );
      }
      final entryId = await txn.insert('udhaar_entries', {
        'personId': personId,
        'entryType': entryType,
        'accountType': accountType,
        'paymentMode': paymentMode,
        'amount': amount,
        'date': date.toIso8601String(),
        'purpose': purpose.trim(),
        'note': note.trim(),
        'transactionId': transactionId,
        'savingsEntryId': savingsEntryId,
        'createdAt': now.toIso8601String(),
      });
      await _assertUdhaarHistoryValid(txn, personId);
      return entryId;
    });
  }

  Future<void> updateUdhaarEntry(UdhaarEntry entry) async {
    if (entry.id == null) {
      throw ArgumentError(
        'Cannot update an Udhaar entry without a database ID.',
      );
    }
    _validateUdhaarEntry(
      entryType: entry.entryType,
      accountType: entry.accountType,
      paymentMode: entry.paymentMode,
      amount: entry.amount,
    );
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'udhaar_entries',
        where: 'id = ?',
        whereArgs: [entry.id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('This Udhaar entry no longer exists.');
      }
      final old = UdhaarEntry.fromMap(rows.first);
      final newPersonRows = await txn.query(
        'udhaar_people',
        where: 'id = ?',
        whereArgs: [entry.personId],
        limit: 1,
      );
      if (newPersonRows.isEmpty) {
        throw StateError('This person no longer exists.');
      }
      final newName = newPersonRows.first['name'] as String;
      await _validateUdhaarMovement(
        txn,
        accountType: entry.accountType,
        paymentMode: entry.paymentMode,
        entryType: entry.entryType,
        amount: entry.amount,
        date: entry.date,
        existingEntry: old,
      );
      int? transactionId = old.transactionId;
      int? savingsEntryId = old.savingsEntryId;
      if (entry.accountType == 'wallet') {
        if (savingsEntryId != null) {
          await txn.delete(
            'savings_entries',
            where: 'id = ?',
            whereArgs: [savingsEntryId],
          );
          savingsEntryId = null;
        }
        if (transactionId != null) {
          await txn.update(
            'transactions',
            _udhaarWalletTransactionValues(
              personName: newName,
              entryType: entry.entryType,
              paymentMode: entry.paymentMode,
              amount: entry.amount,
              date: entry.date,
              purpose: entry.purpose,
              note: entry.note,
            ),
            where: 'id = ?',
            whereArgs: [transactionId],
          );
        } else {
          transactionId = await _insertUdhaarWalletTransaction(
            txn,
            personName: newName,
            entryType: entry.entryType,
            paymentMode: entry.paymentMode,
            amount: entry.amount,
            date: entry.date,
            purpose: entry.purpose,
            note: entry.note,
          );
        }
      } else {
        if (transactionId != null) {
          await txn.delete(
            'transactions',
            where: 'id = ?',
            whereArgs: [transactionId],
          );
          transactionId = null;
        }
        if (savingsEntryId != null) {
          await txn.update(
            'savings_entries',
            _udhaarSavingsMovementValues(
              personName: newName,
              entryType: entry.entryType,
              paymentMode: entry.paymentMode,
              amount: entry.amount,
              date: entry.date,
              purpose: entry.purpose,
              note: entry.note,
            ),
            where: 'id = ?',
            whereArgs: [savingsEntryId],
          );
        } else {
          savingsEntryId = await _insertUdhaarSavingsMovement(
            txn,
            personName: newName,
            entryType: entry.entryType,
            paymentMode: entry.paymentMode,
            amount: entry.amount,
            date: entry.date,
            purpose: entry.purpose,
            note: entry.note,
          );
        }
      }
      await txn.update(
        'udhaar_entries',
        {
          'personId': entry.personId,
          'entryType': entry.entryType,
          'accountType': entry.accountType,
          'paymentMode': entry.paymentMode,
          'amount': entry.amount,
          'date': entry.date.toIso8601String(),
          'purpose': entry.purpose.trim(),
          'note': entry.note.trim(),
          'transactionId': transactionId,
          'savingsEntryId': savingsEntryId,
        },
        where: 'id = ?',
        whereArgs: [entry.id],
      );
      await _assertUdhaarHistoryValid(txn, entry.personId);
      if (entry.personId != old.personId) {
        await _assertUdhaarHistoryValid(txn, old.personId);
      }
    });
  }

  Future<void> deleteUdhaarEntry(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'udhaar_entries',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return;
      }
      final entry = UdhaarEntry.fromMap(rows.first);
      if (entry.accountType == 'wallet' &&
          await _isMonthClosed(txn, entry.date.month, entry.date.year)) {
        throw StateError(
          'This Wallet entry belongs to a closed month and cannot be edited or deleted.',
        );
      }
      if (entry.transactionId != null) {
        await txn.delete(
          'transactions',
          where: 'id = ?',
          whereArgs: [entry.transactionId],
        );
      }
      if (entry.savingsEntryId != null) {
        await txn.delete(
          'savings_entries',
          where: 'id = ?',
          whereArgs: [entry.savingsEntryId],
        );
      }
      await txn.delete('udhaar_entries', where: 'id = ?', whereArgs: [id]);
      await _assertUdhaarHistoryValid(txn, entry.personId);
    });
  }

  Future<void> _validateUdhaarMovement(
    DatabaseExecutor txn, {
    required String accountType,
    required String paymentMode,
    required String entryType,
    required double amount,
    required DateTime date,
    UdhaarEntry? existingEntry,
  }) async {
    if (existingEntry != null &&
        existingEntry.accountType == 'wallet' &&
        await _isMonthClosed(
          txn,
          existingEntry.date.month,
          existingEntry.date.year,
        )) {
      throw StateError(
        'This Wallet entry belongs to a closed month and cannot be edited.',
      );
    }

    if (accountType == 'wallet') {
      if (await _isMonthClosed(txn, date.month, date.year)) {
        throw StateError(
          'Wallet Udhaar entries cannot be added to a closed month. Choose an open-month date or use Savings.',
        );
      }

      final isOutgoing =
          entryType == 'lent' || entryType == 'borrowed_repayment';
      if (isOutgoing) {
        var available = await _getMonthlyAvailableBalance(
          txn,
          paymentMode: paymentMode,
          month: date.month,
          year: date.year,
        );

        final old = existingEntry;
        if (old != null &&
            old.accountType == 'wallet' &&
            old.paymentMode == paymentMode &&
            old.date.year == date.year &&
            old.date.month == date.month) {
          final oldEffect = old.isIncomingWalletFlow ? old.amount : -old.amount;
          available -= oldEffect;
        }

        if (amount > available + 0.000001) {
          throw StateError(
            'Insufficient $paymentMode wallet balance. Available: ₹${available.toStringAsFixed(2)}',
          );
        }
      }
      return;
    }

    final isSavingsOutflow =
        entryType == 'lent' || entryType == 'borrowed_repayment';
    if (!isSavingsOutflow) {
      return;
    }

    var availableSavings = await _getSavingsAccountBalance(txn, paymentMode);
    final old = existingEntry;
    if (old != null &&
        old.accountType == 'savings' &&
        old.paymentMode == paymentMode &&
        old.savingsEntryId != null) {
      final oldRows = await txn.query(
        'savings_entries',
        columns: ['amount', 'movementType'],
        where: 'id = ?',
        whereArgs: [old.savingsEntryId],
        limit: 1,
      );
      if (oldRows.isNotEmpty) {
        final oldAmount = (oldRows.first['amount'] as num).toDouble();
        final oldMovementType =
            oldRows.first['movementType'] as String? ?? 'deposit';
        final oldSigned =
            (oldMovementType == 'loan_given' ||
                oldMovementType == 'loan_repaid')
            ? -oldAmount
            : oldAmount;
        availableSavings -= oldSigned;
      }
    }

    if (amount > availableSavings + 0.000001) {
      throw StateError(
        'Insufficient $paymentMode savings balance. Available: ₹${availableSavings.toStringAsFixed(2)}',
      );
    }
  }

  Future<double> _getSavingsAccountBalance(
    DatabaseExecutor txn,
    String paymentMode,
  ) async {
    final rows = await txn.rawQuery(
      '''
      SELECT COALESCE(SUM(
        CASE
          WHEN movementType IN ('loan_given', 'loan_repaid') THEN -amount
          ELSE amount
        END
      ), 0) AS balance
      FROM savings_entries
      WHERE paymentMode = ?
    ''',
      [paymentMode],
    );
    return (rows.first['balance'] as num).toDouble();
  }

  void _validateUdhaarEntry({
    required String entryType,
    required String accountType,
    required String paymentMode,
    required double amount,
  }) {
    const entryTypes = [
      'lent',
      'borrowed',
      'lent_repayment',
      'borrowed_repayment',
    ];
    if (!entryTypes.contains(entryType)) {
      throw ArgumentError('Invalid Udhaar entry type.');
    }
    if (accountType != 'wallet' && accountType != 'savings') {
      throw ArgumentError('Account must be Wallet or Savings.');
    }
    if (paymentMode != 'Cash' && paymentMode != 'Online') {
      throw ArgumentError('Payment mode must be Cash or Online.');
    }
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Udhaar amount must be greater than zero.');
    }
  }

  Future<int> _insertUdhaarWalletTransaction(
    DatabaseExecutor txn, {
    required String personName,
    required String entryType,
    required String paymentMode,
    required double amount,
    required DateTime date,
    required String purpose,
    required String note,
  }) async {
    return txn.insert(
      'transactions',
      _udhaarWalletTransactionValues(
        personName: personName,
        entryType: entryType,
        paymentMode: paymentMode,
        amount: amount,
        date: date,
        purpose: purpose,
        note: note,
      ),
    );
  }

  Map<String, Object?> _udhaarWalletTransactionValues({
    required String personName,
    required String entryType,
    required String paymentMode,
    required double amount,
    required DateTime date,
    required String purpose,
    required String note,
  }) {
    final incoming = entryType == 'borrowed' || entryType == 'lent_repayment';
    final title = _udhaarTitle(entryType);
    final details = [personName, if (purpose.trim().isNotEmpty) purpose.trim()];
    final memo = note.trim();
    return {
      'title':
          '$title — ${details.join(' · ')}${memo.isEmpty ? '' : ' ($memo)'}',
      'category': 'Udhaar',
      'amount': amount,
      'date': date.toIso8601String(),
      'isIncome': incoming ? 1 : 0,
      'paymentMode': paymentMode,
      'isUdhaar': 1,
    };
  }

  Future<int> _insertUdhaarSavingsMovement(
    DatabaseExecutor txn, {
    required String personName,
    required String entryType,
    required String paymentMode,
    required double amount,
    required DateTime date,
    required String purpose,
    required String note,
  }) async {
    return txn.insert(
      'savings_entries',
      _udhaarSavingsMovementValues(
        personName: personName,
        entryType: entryType,
        paymentMode: paymentMode,
        amount: amount,
        date: date,
        purpose: purpose,
        note: note,
      ),
    );
  }

  Map<String, Object?> _udhaarSavingsMovementValues({
    required String personName,
    required String entryType,
    required String paymentMode,
    required double amount,
    required DateTime date,
    required String purpose,
    required String note,
  }) {
    final movementType = switch (entryType) {
      'lent' => 'loan_given',
      'borrowed' => 'loan_received',
      'lent_repayment' => 'loan_collected',
      'borrowed_repayment' => 'loan_repaid',
      _ => 'deposit',
    };
    final label = _udhaarTitle(entryType);
    final details = [personName, if (purpose.trim().isNotEmpty) purpose.trim()];
    final memo = note.trim();
    return {
      'transactionId': null,
      'goalId': null,
      'amount': amount,
      'paymentMode': paymentMode,
      'entryType': 'existing',
      'movementType': movementType,
      'month': date.month,
      'year': date.year,
      'note':
          '$label — ${details.join(' · ')}${memo.isEmpty ? '' : ' ($memo)'}',
      'createdAt': date.toIso8601String(),
    };
  }

  String _udhaarTitle(String entryType) {
    switch (entryType) {
      case 'lent':
        return 'Udhaar diya';
      case 'borrowed':
        return 'Udhaar liya';
      case 'lent_repayment':
        return 'Udhaar wapas mila';
      case 'borrowed_repayment':
        return 'Udhaar wapas kiya';
      default:
        return 'Udhaar entry';
    }
  }

  Future<void> _assertUdhaarHistoryValid(
    DatabaseExecutor txn,
    int personId,
  ) async {
    final rows = await txn.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN entryType = 'lent' THEN amount ELSE 0 END), 0) AS lent,
        COALESCE(SUM(CASE WHEN entryType = 'lent_repayment' THEN amount ELSE 0 END), 0) AS collected,
        COALESCE(SUM(CASE WHEN entryType = 'borrowed' THEN amount ELSE 0 END), 0) AS borrowed,
        COALESCE(SUM(CASE WHEN entryType = 'borrowed_repayment' THEN amount ELSE 0 END), 0) AS repaid
      FROM udhaar_entries WHERE personId = ?
    ''',
      [personId],
    );
    final row = rows.first;
    final lent = (row['lent'] as num).toDouble();
    final collected = (row['collected'] as num).toDouble();
    final borrowed = (row['borrowed'] as num).toDouble();
    final repaid = (row['repaid'] as num).toDouble();
    if (collected > lent + 0.000001) {
      throw StateError(
        'This change would make the received repayment exceed the total Udhaar given.',
      );
    }
    if (repaid > borrowed + 0.000001) {
      throw StateError(
        'This change would make the repayment exceed the total Udhaar taken.',
      );
    }
  }

  Future<double> getMonthlyAvailableBalance({
    required String paymentMode,
    required int month,
    required int year,
  }) async {
    final db = await database;
    return _getMonthlyAvailableBalance(
      db,
      paymentMode: paymentMode,
      month: month,
      year: year,
    );
  }

  Future<double> _getMonthlyAvailableBalance(
    DatabaseExecutor executor, {
    required String paymentMode,
    required int month,
    required int year,
  }) async {
    final yearText = year.toString().padLeft(4, '0');
    final monthText = month.toString().padLeft(2, '0');
    // Savings-category transactions are excluded here because their
    // matching transfer or rollover is deducted from the ledger below.
    final transactionRows = await executor.rawQuery(
      '''
      SELECT COALESCE(
        SUM(CASE WHEN isIncome = 1 THEN amount ELSE -amount END),
        0
      ) AS available
      FROM transactions
      WHERE substr(date, 1, 4) = ?
        AND substr(date, 6, 2) = ?
        AND paymentMode = ?
        AND LOWER(category) != 'savings'
      ''',
      [yearText, monthText, paymentMode],
    );
    final savingsRows = await executor.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS deducted
      FROM savings_entries
      WHERE year = ?
        AND month = ?
        AND paymentMode = ?
        AND entryType IN ('transfer', 'rollover')
      ''',
      [year, month, paymentMode],
    );
    final transactionNet = (transactionRows.first['available'] as num)
        .toDouble();
    final savingsDeducted = (savingsRows.first['deducted'] as num).toDouble();
    return transactionNet - savingsDeducted;
  }

  // ============================================================
  // MONTH-END ROLLOVER
  // ============================================================
  Future<void> _ensureMonthEndSavingsRollover(Database db) async {
    final now = DateTime.now();
    final target = DateTime(
      now.year,
      now.month,
      1,
    ).subtract(const Duration(days: 1));
    final rows = await db.query(
      'monthly_closures',
      orderBy: 'year DESC, month DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      await _closeMonthIfNeeded(db, month: target.month, year: target.year);
      return;
    }
    final latestRow = rows.first;
    final latest = DateTime(
      latestRow['year'] as int,
      latestRow['month'] as int,
    );
    if (!latest.isBefore(target)) {
      return;
    }
    var monthToClose = DateTime(latest.year, latest.month + 1);
    var safetyCounter = 0;
    while (!monthToClose.isAfter(target) && safetyCounter < 120) {
      await _closeMonthIfNeeded(
        db,
        month: monthToClose.month,
        year: monthToClose.year,
      );
      monthToClose = DateTime(monthToClose.year, monthToClose.month + 1);
      safetyCounter++;
    }
  }

  Future<bool> _closeMonthIfNeeded(
    Database db, {
    required int month,
    required int year,
  }) async {
    return db.transaction((txn) async {
      final existing = await txn.query(
        'monthly_closures',
        columns: ['id'],
        where: 'month = ? AND year = ?',
        whereArgs: [month, year],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return false;
      }
      final cashAvailable = await _getMonthlyAvailableBalance(
        txn,
        paymentMode: 'Cash',
        month: month,
        year: year,
      );
      final onlineAvailable = await _getMonthlyAvailableBalance(
        txn,
        paymentMode: 'Online',
        month: month,
        year: year,
      );
      final cashRollover = cashAvailable > 0 ? cashAvailable : 0.0;
      final onlineRollover = onlineAvailable > 0 ? onlineAvailable : 0.0;
      final closedAt = DateTime.now();
      final monthLabel = '${_monthName(month)} $year';
      final monthEnd = DateTime(year, month + 1, 0, 23, 59, 59);
      if (cashRollover > 0) {
        final transactionId = await txn.insert('transactions', {
          'title': '$monthLabel Cash savings rollover',
          'category': 'Savings',
          'amount': cashRollover,
          'date': monthEnd.toIso8601String(),
          'isIncome': 0,
          'paymentMode': 'Cash',
        });
        await txn.insert('savings_entries', {
          'transactionId': transactionId,
          'goalId': null,
          'amount': cashRollover,
          'paymentMode': 'Cash',
          'entryType': 'rollover',
          'month': month,
          'year': year,
          'note': '$monthLabel Cash month-end rollover',
          'createdAt': closedAt.toIso8601String(),
        });
      }
      if (onlineRollover > 0) {
        final transactionId = await txn.insert('transactions', {
          'title': '$monthLabel Online savings rollover',
          'category': 'Savings',
          'amount': onlineRollover,
          'date': monthEnd.toIso8601String(),
          'isIncome': 0,
          'paymentMode': 'Online',
        });
        await txn.insert('savings_entries', {
          'transactionId': transactionId,
          'goalId': null,
          'amount': onlineRollover,
          'paymentMode': 'Online',
          'entryType': 'rollover',
          'month': month,
          'year': year,
          'note': '$monthLabel Online month-end rollover',
          'createdAt': closedAt.toIso8601String(),
        });
      }
      await txn.insert('monthly_closures', {
        'month': month,
        'year': year,
        'cashAmount': cashRollover,
        'onlineAmount': onlineRollover,
        'closedAt': closedAt.toIso8601String(),
      });
      return true;
    });
  }

  String _monthName(int month) {
    const names = [
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
    return names[month - 1];
  }
}

class SavingsEntry {
  final int? id;
  final int? transactionId;
  final int? goalId;
  final double amount;
  final String paymentMode;
  final String entryType;
  final String movementType;
  final int month;
  final int year;
  final String note;
  final DateTime createdAt;

  const SavingsEntry({
    this.id,
    this.transactionId,
    this.goalId,
    required this.amount,
    required this.paymentMode,
    required this.entryType,
    this.movementType = 'deposit',
    required this.month,
    required this.year,
    this.note = '',
    required this.createdAt,
  });

  factory SavingsEntry.fromMap(Map<String, Object?> map) {
    return SavingsEntry(
      id: map['id'] as int?,
      transactionId: map['transactionId'] as int?,
      goalId: map['goalId'] as int?,
      amount: (map['amount'] as num).toDouble(),
      paymentMode: map['paymentMode'] as String? ?? 'Cash',
      entryType: map['entryType'] as String? ?? 'existing',
      movementType: map['movementType'] as String? ?? 'deposit',
      month: map['month'] as int,
      year: map['year'] as int,
      note: map['note'] as String? ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'transactionId': transactionId,
      'goalId': goalId,
      'amount': amount,
      'paymentMode': paymentMode,
      'entryType': entryType,
      'movementType': movementType,
      'month': month,
      'year': year,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  bool get reducesSavings =>
      movementType == 'loan_given' || movementType == 'loan_repaid';

  bool get isUdhaarMovement =>
      movementType == 'loan_given' ||
      movementType == 'loan_received' ||
      movementType == 'loan_collected' ||
      movementType == 'loan_repaid';

  double get signedAmount => reducesSavings ? -amount : amount;
}

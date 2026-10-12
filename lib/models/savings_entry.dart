class SavingsEntry {
  final int? id;
  final int? transactionId;
  final int? goalId;
  final double amount;
  final String paymentMode;
  final String entryType;
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
    required this.month,
    required this.year,
    required this.note,
    required this.createdAt,
  });

  factory SavingsEntry.fromMap(Map<String, Object?> map) {
    return SavingsEntry(
      id: map['id'] as int?,
      transactionId: map['transactionId'] as int?,
      goalId: map['goalId'] as int?,
      amount: (map['amount'] as num).toDouble(),
      paymentMode: map['paymentMode'] as String,
      entryType: map['entryType'] as String,
      month: map['month'] as int,
      year: map['year'] as int,
      note: map['note'] as String? ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'transactionId': transactionId,
      'goalId': goalId,
      'amount': amount,
      'paymentMode': paymentMode,
      'entryType': entryType,
      'month': month,
      'year': year,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

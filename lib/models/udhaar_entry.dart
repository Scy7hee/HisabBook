class UdhaarEntry {
  final int? id;
  final int personId;
  final String entryType;
  final String accountType;
  final String paymentMode;
  final double amount;
  final DateTime date;
  final String purpose;
  final String note;
  final int? transactionId;
  final int? savingsEntryId;
  final DateTime createdAt;

  const UdhaarEntry({
    this.id,
    required this.personId,
    required this.entryType,
    required this.accountType,
    required this.paymentMode,
    required this.amount,
    required this.date,
    this.purpose = '',
    this.note = '',
    this.transactionId,
    this.savingsEntryId,
    required this.createdAt,
  });

  factory UdhaarEntry.fromMap(Map<String, Object?> map) {
    return UdhaarEntry(
      id: map['id'] as int?,
      personId: map['personId'] as int,
      entryType: map['entryType'] as String,
      accountType: map['accountType'] as String,
      paymentMode: map['paymentMode'] as String? ?? 'Cash',
      amount: (map['amount'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
      purpose: map['purpose'] as String? ?? '',
      note: map['note'] as String? ?? '',
      transactionId: map['transactionId'] as int?,
      savingsEntryId: map['savingsEntryId'] as int?,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  bool get increasesReceivable => entryType == 'lent';
  bool get reducesReceivable => entryType == 'lent_repayment';
  bool get increasesPayable => entryType == 'borrowed';
  bool get reducesPayable => entryType == 'borrowed_repayment';

  bool get isIncomingWalletFlow =>
      entryType == 'borrowed' || entryType == 'lent_repayment';

  bool get isOutgoingWalletFlow =>
      entryType == 'lent' || entryType == 'borrowed_repayment';

  String get typeLabel {
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

  String get accountLabel => accountType == 'savings' ? 'Savings' : 'Wallet';
}

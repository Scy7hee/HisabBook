class Transaction {
  final int? id;
  final String title;
  final String category;
  final double amount;
  final DateTime date;
  final bool isIncome;
  final String paymentMode;
  final bool isUdhaar;

  const Transaction({
    this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.date,
    this.isIncome = false,
    this.paymentMode = 'Cash',
    this.isUdhaar = false,
  });
}

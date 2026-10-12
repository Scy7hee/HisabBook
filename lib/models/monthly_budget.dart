class MonthlyBudget {
  final int? id;
  final String category;
  final int month;
  final int year;
  final double limitAmount;

  const MonthlyBudget({
    this.id,
    required this.category,
    required this.month,
    required this.year,
    required this.limitAmount,
  });

  factory MonthlyBudget.fromMap(Map<String, Object?> map) {
    return MonthlyBudget(
      id: map['id'] as int?,
      category: map['category'] as String,
      month: map['month'] as int,
      year: map['year'] as int,
      limitAmount: (map['amount'] as num).toDouble(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'category': category,
      'month': month,
      'year': year,
      'amount': limitAmount,
    };
  }
}
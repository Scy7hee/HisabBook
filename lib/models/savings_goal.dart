class SavingsGoal {
  final int? id;
  final String title;
  final double targetAmount;
  final double savedAmount;
  final DateTime? targetDate;
  final DateTime createdAt;

  const SavingsGoal({
    this.id,
    required this.title,
    required this.targetAmount,
    this.savedAmount = 0,
    this.targetDate,
    required this.createdAt,
  });

  factory SavingsGoal.fromMap(Map<String, Object?> map) {
    return SavingsGoal(
      id: map['id'] as int?,
      title: map['title'] as String,
      targetAmount: (map['targetAmount'] as num).toDouble(),
      savedAmount: (map['savedAmount'] as num).toDouble(),
      targetDate: map['targetDate'] == null
          ? null
          : DateTime.parse(map['targetDate'] as String),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'title': title,
      'targetAmount': targetAmount,
      'savedAmount': savedAmount,
      'targetDate': targetDate?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

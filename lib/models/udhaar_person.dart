class UdhaarPerson {
  final int? id;
  final String name;
  final String note;
  final DateTime createdAt;
  final double totalLent;
  final double totalCollected;
  final double totalBorrowed;
  final double totalRepaid;

  const UdhaarPerson({
    this.id,
    required this.name,
    this.note = '',
    required this.createdAt,
    this.totalLent = 0,
    this.totalCollected = 0,
    this.totalBorrowed = 0,
    this.totalRepaid = 0,
  });

  double get receivableBalance => totalLent - totalCollected;
  double get payableBalance => totalBorrowed - totalRepaid;

  factory UdhaarPerson.fromMap(Map<String, Object?> map) {
    return UdhaarPerson(
      id: map['id'] as int?,
      name: map['name'] as String,
      note: map['note'] as String? ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
      totalLent: (map['totalLent'] as num?)?.toDouble() ?? 0,
      totalCollected: (map['totalCollected'] as num?)?.toDouble() ?? 0,
      totalBorrowed: (map['totalBorrowed'] as num?)?.toDouble() ?? 0,
      totalRepaid: (map['totalRepaid'] as num?)?.toDouble() ?? 0,
    );
  }

  UdhaarPerson withBalances({
    required double totalLent,
    required double totalCollected,
    required double totalBorrowed,
    required double totalRepaid,
  }) {
    return UdhaarPerson(
      id: id,
      name: name,
      note: note,
      createdAt: createdAt,
      totalLent: totalLent,
      totalCollected: totalCollected,
      totalBorrowed: totalBorrowed,
      totalRepaid: totalRepaid,
    );
  }
}

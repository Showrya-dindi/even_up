class Expense {
  final String id;
  final String description;
  final double amount;
  final String paidBy;
  final DateTime createdAt;
  final String splitType;
  final List<Map<String, dynamic>> splitWith;
  final String? groupId;

  Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.paidBy,
    required this.createdAt,
    required this.splitType,
    this.splitWith = const [],
    this.groupId,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: _safeString(json['id']),
      description: _safeString(json['description'], defaultValue: 'No description'),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      paidBy: _safeString(json['paidBy'], defaultValue: 'Unknown'),
      createdAt: json['createdAt'] != null 
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      splitType: _safeString(json['splitType'], defaultValue: 'Equally'),
      splitWith: (json['splitWith'] as List?)?.map((m) => Map<String, dynamic>.from(m as Map)).toList() ?? [],
      groupId: _safeString(json['groupId']),
    );
  }

  static String _safeString(dynamic value, {String defaultValue = ''}) {
    if (value is String) return value;
    if (value == null) return defaultValue;
    try {
      final String s = '$value';
      if (s == 'undefined' || s == 'null') return defaultValue;
      return s;
    } catch (_) {
      return defaultValue;
    }
  }

  double getShareOf(String userId) {
    if (splitType == 'Equally') {
      if (splitWith.any((m) => m['userId'] == userId)) {
        return amount / (splitWith.isEmpty ? 1 : splitWith.length);
      }
      return 0.0;
    } else {
      final member = splitWith.firstWhere(
        (m) => m['userId'] == userId,
        orElse: () => <String, dynamic>{},
      );
      return (member['amount'] as num?)?.toDouble() ?? 0.0;
    }
  }

  bool isUserInvolved(String userId) {
    return paidBy == userId || splitWith.any((m) => m['userId'] == userId);
  }
}

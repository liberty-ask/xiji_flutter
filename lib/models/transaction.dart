enum TransactionType {
  income, // 0 - 收入
  expense; // 1 - 支出

  // 转换为int: INCOME=0, EXPENSE=1
  int toInt() {
    return this == TransactionType.income ? 0 : 1;
  }

  // 从int转换为枚举
  static TransactionType fromInt(int value) {
    return value == 0 ? TransactionType.income : TransactionType.expense;
  }

  // 兼容旧代码：从字符串转换（用于向后兼容）
  static TransactionType fromString(String value) {
    if (value == '0' || value == 'INCOME') {
      return TransactionType.income;
    } else if (value == '1' || value == 'EXPENSE') {
      return TransactionType.expense;
    }
    // 默认值
    return TransactionType.expense;
  }

  // 兼容旧代码：转换为字符串（用于向后兼容）
  @override
  String toString() {
    return toInt().toString();
  }
}

class Transaction {
  final String id;
  final TransactionType type;
  final String category;
  final double amount;
  final DateTime date;
  final String userId;
  final String? description;
  final String? counterparty;

  Transaction({
    required this.id,
    required this.type,
    required this.category,
    required this.amount,
    required this.date,
    required this.userId,
    this.description,
    this.counterparty,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    // 处理type字段，可能是int或String
    TransactionType transactionType;
    final typeValue = json['type'];
    if (typeValue is int) {
      transactionType = TransactionType.fromInt(typeValue);
    } else if (typeValue is String) {
      // 兼容字符串格式
      transactionType = TransactionType.fromString(typeValue);
    } else {
      // 默认值
      transactionType = TransactionType.expense;
    }

    return Transaction(
      id: (json['id'] as String?) ?? '',
      type: transactionType,
      category: (json['category'] as String?) ?? '',
      amount: ((json['amount'] as num?) ?? 0).toDouble(),
      date: DateTime.parse(json['date'] as String? ?? DateTime.now().toIso8601String()),
      userId: (json['userId'] as String?) ?? '',
      description: json['description'] as String?,
      counterparty: json['counterparty'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.toInt(),
        'category': category,
        'amount': amount,
        'date': date.toIso8601String().split('T')[0],
        'userId': userId,
        'description': description,
        'counterparty': counterparty,
      };
}


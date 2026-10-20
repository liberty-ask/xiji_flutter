enum TransactionType {
  income, // 0 - 收入
  expense, // 1 - 支出
  neutral; // 2 - 不计收支（账单导入的转账/理财等流水）

  // 转换为int: INCOME=0, EXPENSE=1, NEUTRAL=2
  int toInt() {
    if (this == TransactionType.income) return 0;
    if (this == TransactionType.expense) return 1;
    return 2;
  }

  // 从int转换为枚举
  static TransactionType fromInt(int value) {
    if (value == 0) return TransactionType.income;
    if (value == 1) return TransactionType.expense;
    return TransactionType.neutral;
  }

  // 兼容旧代码：从字符串转换（用于向后兼容）
  static TransactionType fromString(String value) {
    if (value == '0' || value == 'INCOME') {
      return TransactionType.income;
    } else if (value == '1' || value == 'EXPENSE') {
      return TransactionType.expense;
    } else if (value == '2') {
      return TransactionType.neutral;
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
  final String? icon;
  final double amount;
  final DateTime date;
  final String userId;
  final String? description;
  final String? counterparty;

  Transaction({
    required this.id,
    required this.type,
    required this.category,
    this.icon,
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
      icon: json['icon'] as String?,
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
        'icon': icon,
        'amount': amount,
        'date': date.toIso8601String().split('T')[0],
        'userId': userId,
        'description': description,
        'counterparty': counterparty,
      };
}


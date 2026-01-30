class BillImportResult {
  final int totalCount;
  final int successCount;
  final int skipCount;
  final int failCount;
  final List<int> transactionIds;
  final List<BillImportError> errors;

  BillImportResult({
    required this.totalCount,
    required this.successCount,
    required this.skipCount,
    required this.failCount,
    required this.transactionIds,
    required this.errors,
  });

  factory BillImportResult.fromJson(Map<String, dynamic> json) => BillImportResult(
        totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
        successCount: (json['successCount'] as num?)?.toInt() ?? 0,
        skipCount: (json['skipCount'] as num?)?.toInt() ?? 0,
        failCount: (json['failCount'] as num?)?.toInt() ?? 0,
        transactionIds: (json['transactionIds'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            [],
        errors: (json['errors'] as List<dynamic>?)
                ?.map((e) => BillImportError.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class BillImportError {
  final int? row;
  final String reason;
  final String? rawData;

  BillImportError({
    this.row,
    required this.reason,
    this.rawData,
  });

  factory BillImportError.fromJson(Map<String, dynamic> json) => BillImportError(
        row: (json['row'] as num?)?.toInt(),
        reason: json['reason'] as String? ?? '',
        rawData: json['rawData'] as String?,
      );
}



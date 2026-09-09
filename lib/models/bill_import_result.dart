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
}

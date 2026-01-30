class BillUploadResult {
  final String platform;
  final int totalCount;
  final int successCount;
  final int errorCount;
  final List<BillPreviewItem> preview;
  final List<BillParseError> errors;
  final BillMetadata? metadata;

  BillUploadResult({
    required this.platform,
    required this.totalCount,
    required this.successCount,
    required this.errorCount,
    required this.preview,
    required this.errors,
    this.metadata,
  });

  factory BillUploadResult.fromJson(Map<String, dynamic> json) => BillUploadResult(
        platform: json['platform'] as String,
        totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
        successCount: (json['successCount'] as num?)?.toInt() ?? 0,
        errorCount: (json['errorCount'] as num?)?.toInt() ?? 0,
        preview: (json['preview'] as List<dynamic>?)
                ?.map((e) => BillPreviewItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        errors: (json['errors'] as List<dynamic>?)
                ?.map((e) => BillParseError.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        metadata: json['metadata'] != null
            ? BillMetadata.fromJson(json['metadata'] as Map<String, dynamic>)
            : null,
      );
}

class BillPreviewItem {
  final String tradeNo;
  final String date;
  final int type;
  final double amount;
  final String? category;
  final String? description;
  final String? payMethod;
  final String? counterparty;
  final String? status;

  BillPreviewItem({
    required this.tradeNo,
    required this.date,
    required this.type,
    required this.amount,
    this.category,
    this.description,
    this.payMethod,
    this.counterparty,
    this.status,
  });

  factory BillPreviewItem.fromJson(Map<String, dynamic> json) => BillPreviewItem(
        tradeNo: json['tradeNo'] as String? ?? '',
        date: json['date'] as String? ?? '',
        type: (json['type'] as num?)?.toInt() ?? 1,
        amount: ((json['amount'] as num?) ?? 0).toDouble(),
        category: json['category'] as String?,
        description: json['description'] as String?,
        payMethod: json['payMethod'] as String?,
        counterparty: json['counterparty'] as String?,
        status: json['status'] as String?,
      );
}

class BillParseError {
  final int row;
  final String reason;
  final String? rawData;

  BillParseError({
    required this.row,
    required this.reason,
    this.rawData,
  });

  factory BillParseError.fromJson(Map<String, dynamic> json) => BillParseError(
        row: (json['row'] as num?)?.toInt() ?? 0,
        reason: json['reason'] as String? ?? '',
        rawData: json['rawData'] as String?,
      );
}

class BillMetadata {
  final String? billUploadId;
  final BillDateRange? dateRange;
  final double? totalAmount;

  BillMetadata({
    this.billUploadId,
    this.dateRange,
    this.totalAmount,
  });

  factory BillMetadata.fromJson(Map<String, dynamic> json) => BillMetadata(
        billUploadId: json['billUploadId'] as String?,
        dateRange: json['dateRange'] != null
            ? BillDateRange.fromJson(json['dateRange'] as Map<String, dynamic>)
            : null,
        totalAmount: (json['totalAmount'] as num?)?.toDouble(),
      );
}

class BillDateRange {
  final String start;
  final String end;

  BillDateRange({
    required this.start,
    required this.end,
  });

  factory BillDateRange.fromJson(Map<String, dynamic> json) => BillDateRange(
        start: json['start'] as String? ?? '',
        end: json['end'] as String? ?? '',
      );
}



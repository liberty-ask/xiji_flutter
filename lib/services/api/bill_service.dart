import 'api_client.dart';
import '../../models/bill_platform.dart';
import '../../models/bill_upload_result.dart';
import '../../models/bill_import_result.dart';
import '../../models/bill_task_status.dart';

class BillService {
  // 单例实例
  static BillService? _instance;
  
  final ApiClient _api = ApiClient();
  
  // 私有构造函数
  BillService._internal();
  
  // 获取单例实例
  factory BillService() {
    _instance ??= BillService._internal();
    return _instance!;
  }

  // 获取支持的平台列表
  Future<List<BillPlatform>> getSupportedPlatforms() async {
    final result = await _api.get<List<dynamic>>('/v2/mobile/bills/platforms');
    
    return result
        .map((json) => BillPlatform.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // 上传并解析账单文件 - 异步版本
  Future<BillTaskResponse> uploadAndParseBillAsync({
    required dynamic file,
    String? platform,
  }) async {
    final extraFields = <String, dynamic>{};
    if (platform != null && platform.isNotEmpty) {
      extraFields['platform'] = platform;
    }

    final result = await _api.uploadFileWithParams<Map<String, dynamic>>(
      '/v2/mobile/bills/upload',
      file,
      extraFields: extraFields.isNotEmpty ? extraFields : null,
    );

    return BillTaskResponse.fromJson(result);
  }

  // 上传并解析账单文件（使用 bytes）- 异步版本
  Future<BillTaskResponse> uploadAndParseBillWithBytesAsync({
    required List<int> bytes,
    required String fileName,
    String? platform,
  }) async {
    final extraFields = <String, dynamic>{};
    if (platform != null && platform.isNotEmpty) {
      extraFields['platform'] = platform;
    }

    final result = await _api.uploadFileWithParams<Map<String, dynamic>>(
      '/v2/mobile/bills/upload',
      null, // file 参数为 null，使用 bytes
      fileBytes: bytes,
      fileName: fileName,
      extraFields: extraFields.isNotEmpty ? extraFields : null,
    );

    return BillTaskResponse.fromJson(result);
  }

  // 上传并解析账单文件 - 旧版本（兼容）
  Future<BillUploadResult> uploadAndParseBill({
    required dynamic file,
    String? platform,
  }) async {
    final extraFields = <String, dynamic>{};
    if (platform != null && platform.isNotEmpty) {
      extraFields['platform'] = platform;
    }

    final result = await _api.uploadFileWithParams<Map<String, dynamic>>(
      '/v2/mobile/bills/upload',
      file,
      extraFields: extraFields.isNotEmpty ? extraFields : null,
    );

    return BillUploadResult.fromJson(result);
  }

  // 上传并解析账单文件（使用 bytes）- 旧版本（兼容）
  Future<BillUploadResult> uploadAndParseBillWithBytes({
    required List<int> bytes,
    required String fileName,
    String? platform,
  }) async {
    final extraFields = <String, dynamic>{};
    if (platform != null && platform.isNotEmpty) {
      extraFields['platform'] = platform;
    }

    final result = await _api.uploadFileWithParams<Map<String, dynamic>>(
      '/v2/mobile/bills/upload',
      null, // file 参数为 null，使用 bytes
      fileBytes: bytes,
      fileName: fileName,
      extraFields: extraFields.isNotEmpty ? extraFields : null,
    );

    return BillUploadResult.fromJson(result);
  }

  // 导入交易记录 - 异步版本
  Future<BillTaskResponse> importTransactionsAsync({
    required String billUploadId,
    bool skipDuplicates = true,
    bool autoMatchCategory = true,
  }) async {
    final data = {
      'billUploadId': billUploadId,
      'skipDuplicates': skipDuplicates,
      'autoMatchCategory': autoMatchCategory,
    };

    final result = await _api.post<Map<String, dynamic>>(
      '/v2/mobile/bills/import',
      data: data,
    );

    return BillTaskResponse.fromJson(result);
  }

  // 导入交易记录 - 旧版本（兼容）
  Future<BillImportResult> importTransactions({
    required String billUploadId,
    bool skipDuplicates = true,
    bool autoMatchCategory = true,
  }) async {
    final data = {
      'billUploadId': billUploadId,
      'skipDuplicates': skipDuplicates,
      'autoMatchCategory': autoMatchCategory,
    };

    final result = await _api.post<Map<String, dynamic>>(
      '/v2/mobile/bills/import',
      data: data,
    );

    return BillImportResult.fromJson(result);
  }

  // 获取任务状态
  Future<BillTaskFullStatus> getTaskStatus({required String taskId}) async {
    final result = await _api.get<Map<String, dynamic>>(
      '/v2/mobile/bills/task/status/$taskId',
    );

    return BillTaskFullStatus.fromJson(result);
  }

  // 获取任务列表
  Future<List<BillTaskStatus>> getTaskList() async {
    final result = await _api.get<List<dynamic>>('/v2/mobile/bills/task/list');
    
    return result
        .map((json) => BillTaskStatus.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}


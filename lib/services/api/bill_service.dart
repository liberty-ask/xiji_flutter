import 'api_client.dart';
import '../../models/bill_platform.dart';
import '../../models/bill_task_status.dart';

class BillService {
  static BillService? _instance;

  final ApiClient _api = ApiClient();

  BillService._internal();

  factory BillService() {
    _instance ??= BillService._internal();
    return _instance!;
  }

  Future<List<BillPlatform>> getSupportedPlatforms() async {
    final result = await _api.get<List<dynamic>>('/v2/mobile/bills/platforms');
    return result
        .map((json) => BillPlatform.fromJson(json as Map<String, dynamic>))
        .toList();
  }

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
      null,
      fileBytes: bytes,
      fileName: fileName,
      extraFields: extraFields.isNotEmpty ? extraFields : null,
    );

    return BillTaskResponse.fromJson(result);
  }

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

  Future<BillTaskFullStatus> getTaskStatus({required String taskId}) async {
    final result = await _api.get<Map<String, dynamic>>(
      '/v2/mobile/bills/task/status/$taskId',
    );

    return BillTaskFullStatus.fromJson(result);
  }
}

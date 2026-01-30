import 'bill_upload_result.dart';

class BillTaskFullStatus {
  final BillTaskStatus task;
  final BillUploadResult? parseResult;

  BillTaskFullStatus({
    required this.task,
    this.parseResult,
  });

  factory BillTaskFullStatus.fromJson(Map<String, dynamic> json) {
    final taskJson = json['task'] as Map<String, dynamic>? ?? {};
    final parseResultJson = json['parseResult'] as Map<String, dynamic>?;
    
    return BillTaskFullStatus(
      task: BillTaskStatus.fromJson(taskJson),
      parseResult: parseResultJson != null ? BillUploadResult.fromJson(parseResultJson) : null,
    );
  }
}

class BillTaskStatus {
  final String id;
  final String userId;
  final String familyId;
  final String? billUploadId;
  final String? originalFileName;
  final int? fileSize;
  final String? ossFilePath;
  final String? fileUrl;
  final int taskType;
  final int status;
  final int progress;
  final int totalCount;
  final int successCount;
  final int failCount;
  final String? errorMessage;
  final String? platform;
  final String? startTime;
  final String? endTime;
  final dynamic createdBy;
  final String? createdAt;
  final dynamic updatedBy;
  final String? updatedAt;
  final int deleted;

  BillTaskStatus({
    required this.id,
    required this.userId,
    required this.familyId,
    this.billUploadId,
    this.originalFileName,
    this.fileSize,
    this.ossFilePath,
    this.fileUrl,
    required this.taskType,
    required this.status,
    required this.progress,
    required this.totalCount,
    required this.successCount,
    required this.failCount,
    this.errorMessage,
    this.platform,
    this.startTime,
    this.endTime,
    this.createdBy,
    this.createdAt,
    this.updatedBy,
    this.updatedAt,
    required this.deleted,
  });

  factory BillTaskStatus.fromJson(Map<String, dynamic> json) => BillTaskStatus(
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        familyId: json['familyId'] as String? ?? '',
        billUploadId: json['billUploadId'] as String?,
        originalFileName: json['originalFileName'] as String?,
        fileSize: (json['fileSize'] as num?)?.toInt(),
        ossFilePath: json['ossFilePath'] as String?,
        fileUrl: json['fileUrl'] as String?,
        taskType: (json['taskType'] as num?)?.toInt() ?? 1,
        status: (json['status'] as num?)?.toInt() ?? 0,
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
        successCount: (json['successCount'] as num?)?.toInt() ?? 0,
        failCount: (json['failCount'] as num?)?.toInt() ?? 0,
        errorMessage: json['errorMessage'] as String?,
        platform: json['platform'] as String? ?? '',
        startTime: json['startTime'] as String?,
        endTime: json['endTime'] as String?,
        createdBy: json['createdBy'],
        createdAt: json['createdAt'] as String? ?? '',
        updatedBy: json['updatedBy'],
        updatedAt: json['updatedAt'] as String?,
        deleted: (json['deleted'] as num?)?.toInt() ?? 0,
      );
}

class BillTaskResponse {
  final String taskId;
  final String message;

  BillTaskResponse({
    required this.taskId,
    required this.message,
  });

  factory BillTaskResponse.fromJson(Map<String, dynamic> json) {
    // 确保taskId是字符串类型，处理后端返回的数字类型
    final dynamic taskIdValue = json['taskId'];
    String taskIdStr;
    if (taskIdValue is int || taskIdValue is double) {
      taskIdStr = taskIdValue.toString();
    } else {
      taskIdStr = taskIdValue as String? ?? '';
    }
    
    return BillTaskResponse(
      taskId: taskIdStr,
      message: json['message'] as String? ?? '',
    );
  }
}

enum TaskStatus {
  pending(0, '待处理'),
  processing(1, '处理中'),
  success(2, '成功'),
  failed(3, '失败');

  final int value;
  final String label;

  const TaskStatus(this.value, this.label);

  static TaskStatus fromValue(int value) {
    return TaskStatus.values.firstWhere((status) => status.value == value, orElse: () => TaskStatus.pending);
  }
}

enum TaskType {
  uploadParse(1, '上传解析'),
  import(2, '导入');

  final int value;
  final String label;

  const TaskType(this.value, this.label);

  static TaskType fromValue(int value) {
    return TaskType.values.firstWhere((type) => type.value == value, orElse: () => TaskType.uploadParse);
  }
}
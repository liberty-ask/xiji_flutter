import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../utils/constants.dart';

class ApiClient {
  // 单例实例
  static ApiClient? _instance;
  
  late Dio _dio;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  
  // 根据环境自动切换 baseUrl
  static String get baseUrl {
    if (kDebugMode) {
      // 测试环境
      return 'http://127.0.0.1:8089/api';
    } else {
      // 正式环境
      return 'https://finance.com/api';
    }
  }

  // 私有构造函数
  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: AppConstants.connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: AppConstants.receiveTimeoutSeconds),
      headers: {
        'Content-Type': 'application/json',
      },
    ));

    // 请求拦截器：添加 Token
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
        return handler.next(error);
      },
    ));
  }
  
  // 获取单例实例
  factory ApiClient() {
    _instance ??= ApiClient._internal();
    return _instance!;
  }

  Future<String?> _getToken() async {
    return await _storage.read(key: AppConstants.tokenKey);
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      final response = await _dio.get(path, queryParameters: queryParameters);
      return _handleResponse<T>(response);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<T> post<T>(String path, {dynamic data}) async {
    try {
      final response = await _dio.post(path, data: data);
      return _handleResponse<T>(response);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<T> put<T>(String path, {dynamic data}) async {
    try {
      final response = await _dio.put(path, data: data);
      return _handleResponse<T>(response);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> delete(String path) async {
    try {
      await _dio.delete(path);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // 上传文件（支持XFile和File）
  Future<String> uploadFile(String path, dynamic file) async {
    try {
      MultipartFile multipartFile;
      
      if (file is File) {
        // 移动平台：使用File对象
        final fileName = file.path.split('/').last;
        multipartFile = await MultipartFile.fromFile(
          file.path,
          filename: fileName,
        );
      } else if (file is XFile) {
        // Web/移动平台：使用XFile对象
        final bytes = await file.readAsBytes();
        final fileName = file.name.split('/').last;
        multipartFile = MultipartFile.fromBytes(
          bytes,
          filename: fileName,
        );
      } else {
        throw Exception('不支持的文件类型');
      }

      final formData = FormData.fromMap({
        'file': multipartFile,
      });

      final response = await _dio.post(path, data: formData);
      final data = _handleResponse<dynamic>(response);
      // 返回的data是文件链接（字符串）
      if (data is String) {
        return data;
      }
      // 如果后端返回的是对象，可能需要从data字段中获取
      throw Exception('上传文件失败：返回格式错误');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // 上传文件（支持额外表单参数）
  Future<T> uploadFileWithParams<T>(
    String path,
    dynamic file, {
    Map<String, dynamic>? extraFields,
    String? fileName,
    List<int>? fileBytes,
  }) async {
    try {
      MultipartFile multipartFile;
      
      // 如果提供了 bytes 和 fileName，优先使用（适用于 Web 平台）
      if (fileBytes != null && fileName != null) {
        multipartFile = MultipartFile.fromBytes(
          fileBytes,
          filename: fileName,
        );
      } else if (file is File) {
        // 移动平台：使用File对象
        final name = fileName ?? file.path.split('/').last;
        multipartFile = await MultipartFile.fromFile(
          file.path,
          filename: name,
        );
      } else if (file is XFile) {
        // Web/移动平台：使用XFile对象
        final bytes = await file.readAsBytes();
        final name = fileName ?? file.name.split('/').last;
        multipartFile = MultipartFile.fromBytes(
          bytes,
          filename: name,
        );
      } else {
        throw Exception('不支持的文件类型：需要提供 file、fileBytes+fileName 或 file 对象');
      }

      final formDataMap = <String, dynamic>{
        'file': multipartFile,
      };
      
      // 添加额外的表单字段
      if (extraFields != null) {
        formDataMap.addAll(extraFields);
      }

      final formData = FormData.fromMap(formDataMap);
      final response = await _dio.post(path, data: formData);
      return _handleResponse<T>(response);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  T _handleResponse<T>(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      // 处理统一响应格式 {code, message, data}
      final code = data['code'];
      if (code != null && code is int && code != 200) {
        // 如果 code 存在且不是 200，抛出异常，携带错误消息
        final message = data['message'];
        if (message != null && message is String) {
          throw Exception(message);
        }
        throw Exception('Request failed');
      }
      // code 为 200 或不存在 code 字段，返回 data
      if (data.containsKey('data')) {
        final dataValue = data['data'];
        // 如果 dataValue 为 null，且 T 是 Map 类型，返回空 Map 或整个响应对象
        if (dataValue == null) {
          // 对于添加操作，data 为 null 表示成功，返回包含 message 的 Map
          if (data.containsKey('message')) {
            return {'success': true, 'message': data['message']} as T;
          }
          return {} as T;
        }
        return dataValue as T;
      }
      // 如果没有 data 字段，返回整个响应
      return data as T;
    }
    return data as T;
  }

  Exception _handleError(DioException error) {
    // 处理不同类型的DioException
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return Exception('Timeout');
      case DioExceptionType.badResponse:
        if (error.response != null) {
          final data = error.response?.data;
          if (data is Map<String, dynamic>) {
            // 优先使用响应中的 message
            final message = data['message'];
            if (message != null && message is String) {
              return Exception(message);
            }
          }
          final statusCode = error.response?.statusCode;
          if (statusCode != null) {
            if (statusCode == 401) {
              return Exception('Unauthorized');
            } else if (statusCode == 403) {
              return Exception('Forbidden');
            } else if (statusCode == 404) {
              return Exception('Not Found');
            } else if (statusCode >= 500) {
              return Exception('Server Error');
            }
          }
        }
        return Exception('Request failed');
      case DioExceptionType.cancel:
        return Exception('Canceled');
      case DioExceptionType.connectionError:
        return Exception('Connection error');
      case DioExceptionType.badCertificate:
        return Exception('Certificate error');
      case DioExceptionType.unknown:
        // 检查是否是Socket异常
        if (error.error != null) {
          final errorStr = error.error.toString().toLowerCase();
          if (errorStr.contains('socket') || errorStr.contains('network')) {
            return Exception('Network error');
          }
        }
        return Exception(error.message ?? 'Unknown error');
    }
  }

  // Token 管理方法
  Future<void> setToken(String token) async {
    await _storage.write(key: AppConstants.tokenKey, value: token);
  }

  Future<void> removeToken() async {
    await _storage.delete(key: AppConstants.tokenKey);
  }
}

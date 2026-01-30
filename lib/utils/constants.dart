class AppConstants {
  // API 配置
  static const String apiBaseUrl = 'http://127.0.0.1:8089/api';
  
  // 存储 Key
  static const String tokenKey = 'token';
  static const String themeKey = 'theme_mode';
  
  // 分页
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;
  
  // 日期格式
  static const String dateFormat = 'yyyy-MM-dd';
  static const String timeFormat = 'HH:mm';
  static const String dateTimeFormat = 'yyyy-MM-dd HH:mm';
  
  // 网络请求超时时间（秒）
  static const int connectTimeoutSeconds = 30;
  static const int receiveTimeoutSeconds = 30;
  
  // SnackBar 显示时长（秒）
  static const int snackBarSuccessDurationSeconds = 2;
  static const int snackBarErrorDurationSeconds = 3;
  static const int snackBarInfoDurationSeconds = 2;
  static const int snackBarWarningDurationSeconds = 2;
  
  // 通用延迟时间（秒）
  static const int commonDelaySeconds = 1;
  
  // 日期选择器范围
  static const int datePickerFirstYear = 2020;
}


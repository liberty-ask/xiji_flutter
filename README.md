# 玺记（Xiji）- 家庭记账本

## 📋 项目介绍

玺记是一款面向家庭的记账应用，用 Flutter 开发，支持 iOS、Android 和 Web。一家人可以共同记账、导入微信/支付宝账单、查看统计和预算，把日常收支记清楚。

### 🌟 项目特点

- **纯 AI 开发**：本项目是全程由 AI 开发的项目，没有人员写过任何一行代码
- **开发工具**：使用 Cursor 和 Trae IDE 进行开发
- **跨平台支持**：一次开发，多端运行（iOS、Android、Web）
- **智能功能**：支持语音记账、家庭协作、统计分析等
- **开源项目**：采用 MIT 许可证，欢迎贡献

### 🔗 相关仓库

- **后端仓库**：[玺记 Spring Boot 后端](https://github.com/liberty-ask/xiji.git)

## 📱 功能特性

- ✅ **用户认证**：登录、注册、忘记密码
- ✅ **交易管理**：添加、查看、明细查询
- ✅ **统计分析**：收入/支出统计、图表展示
- ✅ **日历视图**：按日期查看交易记录
- ✅ **家庭管理**：成员管理、审核、邀请
- ✅ **预算管理**：设置和跟踪月度预算
- ✅ **主题设置**：多种主题颜色选择
- ✅ **数据导入**：支持微信/支付宝/京东账单导入
- ✅ **语音记账**：通过语音识别自动生成记账记录
- ✅ **二维码**：支持二维码邀请和扫码

## 🏗️ 系统架构

### 整体架构

```
┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
│                 │        │                 │        │                 │
│  Flutter 前端   │◄───────►│ Spring Boot 后端│◄───────►│ MySQL 数据库    │
│                 │        │                 │        │                 │
└─────────────────┘        └─────────────────┘        └─────────────────┘
```

### 前端架构

- **Flutter 框架**：跨平台移动应用开发
- **状态管理**：Provider
- **路由导航**：GoRouter
- **网络请求**：Dio
- **本地存储**：SharedPreferences + Flutter Secure Storage
- **UI 组件**：自定义组件 + Flutter 内置组件
- **数据模型**：Dart 类
- **工具库**：通用工具函数

## 🛠️ 技术栈

### 前端技术栈

| 技术 | 版本 | 用途 |
|------|------|------|
| Flutter | 3.0+ | 跨平台移动应用框架 |
| Dart | 3.0+ | 开发语言 |
| Provider | ^6.1.1 | 状态管理 |
| GoRouter | ^13.0.0 | 路由管理 |
| Dio | ^5.4.0 | 网络请求 |
| SharedPreferences | ^2.2.2 | 本地存储 |
| Flutter Secure Storage | ^9.0.0 | 安全存储 |
| Intl | ^0.20.2 | 国际化 |
| JSON Annotation | ^4.8.1 | JSON 序列化 |
| FL Chart | ^0.65.0 | 图表展示 |
| URL Launcher | ^6.2.2 | 打开链接 |
| Package Info Plus | ^9.0.0 | 获取应用信息 |
| Image Picker | ^1.0.7 | 图片选择 |
| File Picker | ^8.1.2 | 文件选择 |
| Speech to Text | ^7.3.0 | 语音识别 |
| Permission Handler | ^11.0.0 | 权限管理 |
| QR Flutter | ^4.1.0 | 生成二维码 |
| Mobile Scanner | ^5.2.3 | 扫描二维码 |

### 后端技术栈

| 技术 | 版本 | 用途 |
|------|------|------|
| Spring Boot | 3.4.4 | 应用框架 |
| MySQL | 8.0.26 | 关系型数据库 |
| MyBatis + MyBatis Plus | 3.5.7 | ORM 框架 |
| Redis | 7.0+ | 缓存、会话管理 |
| JWT | 0.12.5 | 身份认证 |
| AOP | Spring AOP | 权限控制、日志记录 |
| HikariCP | 5.1.0 | 数据库连接池 |
| Alibaba Cloud OSS | 3.17.4 | 文件存储 |
| 智谱 AI SDK | 0.3.0 | 智能识别、语音处理 |
| OpenJDK | 21 | Java 运行环境 |

## 📁 项目结构

```
lib/
├── main.dart                 # 应用入口
├── config/                   # 配置文件
│   ├── theme.dart           # 主题配置
│   └── routes.dart          # 路由配置
├── models/                   # 数据模型
│   ├── user.dart            # 用户模型
│   ├── transaction.dart     # 交易模型
│   ├── category.dart        # 分类模型
│   ├── family_member.dart   # 家庭成员模型
│   └── application.dart     # 应用模型
├── services/api/             # API 服务
│   ├── api_client.dart      # HTTP 客户端
│   ├── auth_service.dart    # 认证服务
│   ├── transaction_service.dart # 交易服务
│   ├── family_service.dart  # 家庭服务
│   ├── category_service.dart # 分类服务
│   ├── statistics_service.dart # 统计服务
│   ├── calendar_service.dart # 日历服务
│   └── budget_service.dart  # 预算服务
├── providers/                # 状态管理
│   ├── auth_provider.dart   # 认证状态
│   ├── theme_provider.dart  # 主题状态
│   ├── home_provider.dart   # 首页状态
│   ├── transaction_provider.dart # 交易状态
│   └── category_provider.dart # 分类状态
├── screens/                  # 页面
│   ├── auth/                # 认证页面
│   ├── home/                # 首页相关
│   ├── transaction/         # 交易相关
│   ├── statistics/          # 统计相关
│   ├── calendar/            # 日历相关
│   ├── profile/             # 个人中心
│   ├── family/              # 家庭管理
│   ├── budget/              # 预算管理
│   ├── settings/            # 设置
│   └── import/              # 导入
├── widgets/                  # 组件
│   ├── common/              # 通用组件
│   └── custom/              # 自定义组件
└── utils/                    # 工具
    ├── constants.dart       # 常量定义
    ├── theme_helper.dart    # 主题工具
    └── error_helper.dart    # 错误处理
```

## 🚀 快速开始

### 环境要求

- Flutter SDK 3.0+
- Dart SDK 3.0+
- Android Studio / VS Code
- Android SDK (Android 开发)
- Xcode (iOS 开发，仅 macOS)

### 安装依赖

```bash
# 克隆仓库
git clone https://gitee.com/duyuanyua/xiji_flutter.git
cd xiji_flutter

# 安装依赖
flutter pub get
```

### 配置 API 地址

在 `lib/services/api/api_client.dart` 中配置 API 基础地址：

```dart
static const String baseUrl = 'https://your-api-domain.com/api';
```

### 运行项目

```bash
# 运行在默认设备
flutter run

# 运行在指定设备
flutter run -d <device-id>

# 查看可用设备
flutter devices

# 运行 Web 版本
flutter run -d chrome
```

### 构建应用

```bash
# Android APK
flutter build apk

# Android App Bundle (推荐用于 Google Play)
flutter build appbundle

# iOS (需要 macOS)
flutter build ios

# Web
flutter build web
```

## 🔧 配置说明

### 主题配置

在 `lib/config/theme.dart` 中配置应用主题。

### 语言配置

在 `lib/l10n/` 目录中配置多语言支持。

### 权限配置

在 `AndroidManifest.xml` 和 `Info.plist` 中配置必要的权限。

## 📦 依赖包详情

| 依赖包 | 版本 | 用途 |
|--------|------|------|
| flutter | sdk | 核心框架 |
| flutter_localizations | sdk | 本地化支持 |
| cupertino_icons | ^1.0.6 | iOS 风格图标 |
| provider | ^6.1.1 | 状态管理 |
| go_router | ^13.0.0 | 路由导航 |
| dio | ^5.4.0 | HTTP 请求 |
| shared_preferences | ^2.2.2 | 本地存储 |
| flutter_secure_storage | ^9.0.0 | 安全存储 |
| intl | ^0.20.2 | 国际化 |
| json_annotation | ^4.8.1 | JSON 序列化 |
| fl_chart | ^0.65.0 | 图表展示 |
| url_launcher | ^6.2.2 | 打开链接 |
| package_info_plus | ^9.0.0 | 获取应用信息 |
| image_picker | ^1.0.7 | 图片选择 |
| file_picker | ^8.1.2 | 文件选择 |
| speech_to_text | ^7.3.0 | 语音识别 |
| permission_handler | ^11.0.0 | 权限管理 |
| qr_flutter | ^4.1.0 | 生成二维码 |
| mobile_scanner | ^5.2.3 | 扫描二维码 |

## 🧪 测试

```bash
# 运行测试
flutter test

# 运行测试并生成覆盖率报告
flutter test --coverage
```

## 📄 许可证

本项目采用 MIT 许可证。详情请见 [LICENSE](LICENSE) 文件。

## 👥 贡献

欢迎提交 Issue 和 Pull Request 来贡献代码。

## 📞 联系方式

如有问题，请通过以下方式联系：

- **QQ**：1014434012
- **邮箱**：1014434012@qq.com

---

**玺记** - 一家人，一本账

import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

/// 路由保护：检查用户是否已认证
bool authGuard(BuildContext context, GoRouterState state) {
  final authProvider = Provider.of<AuthProvider>(context, listen: false);
  
  if (!authProvider.isAuthenticated) {
    // 未认证，重定向到登录页
    return false;
  }
  
  return true;
}

/// 路由保护：检查用户角色权限
bool roleGuard(BuildContext context, GoRouterState state, List<int> allowedRoles) {
  final authProvider = Provider.of<AuthProvider>(context, listen: false);
  
  if (!authProvider.isAuthenticated) {
    return false;
  }
  
  final user = authProvider.user;
  if (user?.role == null) {
    return false;
  }
  
  final userRole = user!.role!;
  return allowedRoles.contains(userRole);
}


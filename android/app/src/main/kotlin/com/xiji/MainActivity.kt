package com.xiji

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.xiji/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialRoute" -> {
                    val route = intent.getStringExtra("route")
                    result.success(route)
                }
                "navigateToRoute" -> {
                    val route = call.arguments as? String
                    if (route != null) {
                        // 路由导航已在 Flutter 端处理
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "checkWidgetRegistered" -> {
                    val isRegistered = checkWidgetRegistered(this)
                    result.success(isRegistered)
                }
                "getWidgetInfo" -> {
                    val info = getWidgetInfo(this)
                    result.success(info)
                }
                "openWidgetSettings" -> {
                    openWidgetSettings(this)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun checkWidgetRegistered(context: Context): Boolean {
        try {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, VoiceTransactionWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            // 检查 Widget 是否已注册（即使没有实例，只要 Provider 存在就认为已注册）
            return try {
                appWidgetManager.getAppWidgetInfo(appWidgetIds.firstOrNull() ?: 0) != null
            } catch (e: Exception) {
                // 如果无法获取信息，至少检查 Provider 是否存在
                true
            }
        } catch (e: Exception) {
            return false
        }
    }
    
    private fun getWidgetInfo(context: Context): Map<String, Any> {
        val info = mutableMapOf<String, Any>()
        try {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, VoiceTransactionWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            
            info["isRegistered"] = true
            info["widgetCount"] = appWidgetIds.size
            info["componentName"] = componentName.flattenToString()
            // 检查是否支持 Pin Widget（Android 8.0+）
            info["isPinSupported"] = try {
                android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O && 
                appWidgetManager.isRequestPinAppWidgetSupported
            } catch (e: Exception) {
                false
            }
        } catch (e: Exception) {
            info["isRegistered"] = false
            info["error"] = e.message ?: "Unknown error"
        }
        return info
    }
    
    private fun openWidgetSettings(context: Context) {
        try {
            // 尝试打开应用信息页面（更通用的方式）
            val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = android.net.Uri.parse("package:${context.packageName}")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (e: Exception) {
            // 如果无法打开设置，尝试打开应用列表
            try {
                val intent = Intent(android.provider.Settings.ACTION_APPLICATION_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
            } catch (e2: Exception) {
                // 忽略错误
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val route = intent?.getStringExtra("route")
        if (route != null) {
            // 通过 MethodChannel 传递路由信息到 Flutter
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("navigateToRoute", route)
            }
        }
    }
}





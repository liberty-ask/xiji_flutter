package com.xiji

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
                "updateFinanceWidget" -> {
                    // 接收收支数据，写入原生SharedPreferences后刷新财务汇总小部件
                    // (不使用Flutter shared_preferences，其2.4+后端为DataStore，原生Widget无法读取)
                    val args = call.arguments as? Map<*, *>
                    val income = (args?.get("income") as? Number)?.toFloat() ?: 0.0f
                    val expense = (args?.get("expense") as? Number)?.toFloat() ?: 0.0f
                    applicationContext.getSharedPreferences("FinanceWidget", Context.MODE_PRIVATE)
                        .edit()
                        .putFloat("income", income)
                        .putFloat("expense", expense)
                        .apply()
                    FinanceSummaryWidgetProvider.updateAllWidgets(applicationContext)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
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
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("navigateToRoute", route)
            }
        }
    }
}

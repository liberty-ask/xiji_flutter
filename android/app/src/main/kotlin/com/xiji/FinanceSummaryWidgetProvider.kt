package com.xiji

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.widget.RemoteViews
import com.xiji.R
import java.util.Calendar

class FinanceSummaryWidgetProvider : AppWidgetProvider() {

    companion object {
        /**
         * 更新所有 Widget 实例
         */
        fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, FinanceSummaryWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)

            if (appWidgetIds.isNotEmpty()) {
                val provider = FinanceSummaryWidgetProvider()
                provider.onUpdate(context, appWidgetManager, appWidgetIds)
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        // 处理整卡点击事件，跳转到首页
        if (intent.action == "com.xiji.FINANCE_SUMMARY_HOME_ACTION") {
            // 打开应用并导航到首页
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            launchIntent?.putExtra("route", "/home")
            context.startActivity(launchIntent)
        }
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        // 构建 Widget 视图
        val views = RemoteViews(context.packageName, R.layout.finance_summary_widget)

        // 检查登录状态 - 实际项目中应从 SharedPreferences 或其他存储中获取
        val isLoggedIn = checkLoginStatus(context)

        // 从原生 SharedPreferences 中读取收支数据（由 Flutter 侧通过 MethodChannel 写入）
        val sharedPreferences = context.getSharedPreferences("FinanceWidget", Context.MODE_PRIVATE)

        // 根据登录状态设置数据
        var incomeValue = 0.0f
        var expenseValue = 0.0f

        if (isLoggedIn) {
            incomeValue = sharedPreferences.getFloat("income", 0.0f)
            expenseValue = sharedPreferences.getFloat("expense", 0.0f)
        }

        // 顶部标签：本月支出 · N月
        val month = Calendar.getInstance().get(Calendar.MONTH) + 1
        views.setTextViewText(R.id.widget_title, "本月支出 · ${month}月")

        // 主数字：本月支出（千分位，保留两位小数）
        views.setTextViewText(R.id.expense_text, "¥${String.format("%,.2f", expenseValue)}")

        // 脚注：收入（千分位）
        views.setTextViewText(R.id.income_text, "收入 ¥${String.format("%,.2f", incomeValue)}")

        // 脚注：结余 = 收入 - 支出（正数带 +，负数带 -，零无符号）
        val balanceValue = incomeValue - expenseValue
        val balanceText = when {
            balanceValue > 0 -> "+¥${String.format("%,.2f", balanceValue)}"
            balanceValue < 0 -> "-¥${String.format("%,.2f", -balanceValue)}"
            else -> "¥0.00"
        }
        views.setTextViewText(R.id.balance_text, "结余 $balanceText")

        // 设置整卡点击事件（挂载根布局，跳转到首页）
        val homeIntent = Intent(context, FinanceSummaryWidgetProvider::class.java)
        homeIntent.action = "com.xiji.FINANCE_SUMMARY_HOME_ACTION"
        homeIntent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        val homePendingIntent = android.app.PendingIntent.getBroadcast(
            context,
            2, // 请求码
            homeIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_root, homePendingIntent)

        // 更新 Widget
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    /**
     * 检查用户登录状态
     * 实际项目中应从SharedPreferences或其他存储中获取
     */
    private fun checkLoginStatus(context: Context): Boolean {
        // 简化处理，返回true表示已登录
        // 实际项目中应检查是否存在有效的登录凭证
        return true
    }
}

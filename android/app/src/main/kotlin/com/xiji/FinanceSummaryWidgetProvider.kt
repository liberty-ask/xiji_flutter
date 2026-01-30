package com.xiji

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.widget.RemoteViews
import com.xiji.R

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
        
        // 处理语音记账按钮点击事件
        if (intent.action == "com.xiji.FINANCE_SUMMARY_VOICE_ACTION") {
            // 打开应用并导航到语音记账页面
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            launchIntent?.putExtra("route", "/voice-transaction")
            context.startActivity(launchIntent)
        } 
        // 处理收支数据区域点击事件，跳转到首页
        else if (intent.action == "com.xiji.FINANCE_SUMMARY_HOME_ACTION") {
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
        
        // 设置标题
        views.setTextViewText(R.id.widget_title, "本月财务汇总")
        
        // 检查登录状态 - 实际项目中应从 SharedPreferences 或其他存储中获取
        val isLoggedIn = checkLoginStatus(context)
        
        // 从 SharedPreferences 中读取收支数据
        val sharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        
        // 根据登录状态设置数据
        val income: String
        val expense: String
        
        if (isLoggedIn) {
            // 从SharedPreferences读取数据，键名格式为flutter.widget_income和flutter.widget_expense
            val incomeValue = sharedPreferences.getFloat("flutter.widget_income", 0.0f)
            val expenseValue = sharedPreferences.getFloat("flutter.widget_expense", 0.0f)
            
            // 格式化金额，保留两位小数
            income = "¥${String.format("%.2f", incomeValue)}"
            expense = "¥${String.format("%.2f", expenseValue)}"
        } else {
            // 未登录状态显示0
            income = "¥0.00"
            expense = "¥0.00"
        }
        
        // 设置收支数据
        views.setTextViewText(R.id.income_text, income)
        views.setTextViewText(R.id.expense_text, expense)

        // 设置语音记账按钮点击事件
        val voiceIntent = Intent(context, FinanceSummaryWidgetProvider::class.java)
        voiceIntent.action = "com.xiji.FINANCE_SUMMARY_VOICE_ACTION"
        voiceIntent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        val voicePendingIntent = android.app.PendingIntent.getBroadcast(
            context,
            1, // 使用不同的请求码避免冲突
            voiceIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        
        // 设置首页点击事件
        val homeIntent = Intent(context, FinanceSummaryWidgetProvider::class.java)
        homeIntent.action = "com.xiji.FINANCE_SUMMARY_HOME_ACTION"
        homeIntent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        val homePendingIntent = android.app.PendingIntent.getBroadcast(
            context,
            2, // 使用不同的请求码避免冲突
            homeIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        
        // 设置语音记账按钮可点击（左侧）
        views.setOnClickPendingIntent(R.id.voice_button, voicePendingIntent)
        
        // 设置右侧收支数据区域可点击，跳转到首页
        views.setOnClickPendingIntent(R.id.widget_title, homePendingIntent)
        views.setOnClickPendingIntent(R.id.income_text, homePendingIntent)
        views.setOnClickPendingIntent(R.id.expense_text, homePendingIntent)

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
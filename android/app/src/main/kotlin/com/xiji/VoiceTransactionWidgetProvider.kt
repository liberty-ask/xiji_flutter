package com.xiji

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.widget.RemoteViews
import com.xiji.R

class VoiceTransactionWidgetProvider : AppWidgetProvider() {
    
    companion object {
        /**
         * 更新所有 Widget 实例
         */
        fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, VoiceTransactionWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            
            if (appWidgetIds.isNotEmpty()) {
                val provider = VoiceTransactionWidgetProvider()
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
        
        // 处理 Widget 点击事件
        if (intent.action == "com.xiji.VOICE_TRANSACTION_ACTION") {
            // 打开应用并导航到语音记账页面
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            launchIntent?.putExtra("route", "/voice-transaction")
            context.startActivity(launchIntent)
        }
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        // 构建 Widget 视图
        val views = RemoteViews(context.packageName, R.layout.voice_transaction_widget)
        views.setTextViewText(R.id.widget_title, context.getString(R.string.voice_transaction_widget_title))
        views.setTextViewText(R.id.widget_subtitle, context.getString(R.string.voice_transaction_widget_subtitle))

        // 设置点击事件
        val intent = Intent(context, VoiceTransactionWidgetProvider::class.java)
        intent.action = "com.xiji.VOICE_TRANSACTION_ACTION"
        intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        val pendingIntent = android.app.PendingIntent.getBroadcast(
            context,
            0,
            intent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        
        // 设置整个 Widget 可点击
        views.setOnClickPendingIntent(R.id.widget_icon, pendingIntent)
        views.setOnClickPendingIntent(R.id.widget_title, pendingIntent)
        views.setOnClickPendingIntent(R.id.widget_subtitle, pendingIntent)

        // 更新 Widget
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}

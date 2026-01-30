package com.xiji

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle

/**
 * Widget 配置 Activity
 * 当用户长按应用图标添加 Widget 时，会显示此 Activity
 * 实际上我们不需要配置，直接添加 Widget 即可
 */
class VoiceTransactionWidgetConfigureActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 获取 Widget ID
        val intent = intent
        val extras = intent.extras
        if (extras != null) {
            appWidgetId = extras.getInt(
                AppWidgetManager.EXTRA_APPWIDGET_ID,
                AppWidgetManager.INVALID_APPWIDGET_ID
            )
        }

        // 如果 Widget ID 无效，直接结束
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        // 直接创建 Widget，不需要额外配置
        val appWidgetManager = AppWidgetManager.getInstance(this)
        val widgetProvider = VoiceTransactionWidgetProvider()
        widgetProvider.onUpdate(this, appWidgetManager, intArrayOf(appWidgetId))

        // 返回结果
        val resultValue = Intent()
        resultValue.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        setResult(RESULT_OK, resultValue)
        finish()
    }
}


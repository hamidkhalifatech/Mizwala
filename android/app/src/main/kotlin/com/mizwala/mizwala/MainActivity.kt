package com.mizwala.mizwala

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.mizwala.mizwala/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "updateWidget") {
                try {
                    val intent = Intent(this, MizwalaWidgetProvider::class.java).apply {
                        action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                        val ids = AppWidgetManager.getInstance(applicationContext).getAppWidgetIds(
                            ComponentName(applicationContext, MizwalaWidgetProvider::class.java)
                        )
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    }
                    sendBroadcast(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("UPDATE_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}

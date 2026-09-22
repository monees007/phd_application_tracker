package com.example.phd_tracker

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Two jobs:
 *   1. capture ACTION_SEND text intents and hand them to Dart on request
 *   2. accept a deadline snapshot from Dart, store it, and redraw the widget
 *
 * No plugins for either: both are a single channel plus a few lifecycle hooks,
 * and a dependency here would be more version surface than it is worth.
 */
class MainActivity : FlutterActivity() {

    private val shareChannel = "app.phdtracker/share"
    private val widgetChannel = "app.phdtracker/widget"

    private var pendingSharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Returns the buffered text and clears it, so one share is
                    // never imported twice.
                    "consumePendingShare" -> {
                        val text = pendingSharedText
                        pendingSharedText = null
                        result.success(text)
                    }
                    "moveToBack" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWidget" -> {
                        val json = call.arguments as? String
                        if (json == null) {
                            result.error("BAD_ARGS", "Expected a JSON string", null)
                        } else {
                            DeadlineWidgetProvider.saveSnapshot(this, json)
                            DeadlineWidgetProvider.redrawAll(this)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        capture(intent)
    }

    // If the Kotlin compiler objects to the nullability here, change the
    // parameter to `Intent?` — the platform annotation differs by compileSdk.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        capture(intent)
    }

    private fun capture(incoming: Intent?) {
        if (incoming == null) return
        if (incoming.action != Intent.ACTION_SEND) return
        if (incoming.type?.startsWith("text/") != true) return

        val text = incoming.getStringExtra(Intent.EXTRA_TEXT)
        if (!text.isNullOrBlank()) {
            pendingSharedText = text
        }
    }
}

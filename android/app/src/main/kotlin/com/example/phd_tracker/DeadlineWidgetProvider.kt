package com.example.phd_tracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Home screen widget listing the next few application deadlines.
 *
 * Fixed rows rather than a collection view: a ListView inside a widget needs a
 * RemoteViewsService and a factory, and for five rows that is a lot of moving
 * parts to maintain for no visible gain. If you ever want it scrollable, that
 * is the upgrade.
 *
 * Data comes from a JSON snapshot the app writes through MainActivity. The
 * widget never touches the network or Firestore — it cannot — so it renders
 * whatever the app last pushed and labels it with the sync time.
 */
class DeadlineWidgetProvider : AppWidgetProvider() {

    companion object {
        /** Broadcast the refresh button sends to this provider. */
        const val ACTION_REFRESH = "com.example.phd_tracker.WIDGET_REFRESH"

        private const val PREFS = "phd_tracker_widget"
        private const val KEY_SNAPSHOT = "snapshot"

        /** Row ids in order; the layout defines exactly this many. */
        private val ROW_IDS = intArrayOf(
            R.id.row0, R.id.row1, R.id.row2, R.id.row3, R.id.row4
        )
        private val TITLE_IDS = intArrayOf(
            R.id.row0_title, R.id.row1_title, R.id.row2_title,
            R.id.row3_title, R.id.row4_title
        )
        private val META_IDS = intArrayOf(
            R.id.row0_meta, R.id.row1_meta, R.id.row2_meta,
            R.id.row3_meta, R.id.row4_meta
        )
        private val DAYS_IDS = intArrayOf(
            R.id.row0_days, R.id.row1_days, R.id.row2_days,
            R.id.row3_days, R.id.row4_days
        )

        fun saveSnapshot(context: Context, json: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_SNAPSHOT, json)
                .apply()
        }

        fun redrawAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, DeadlineWidgetProvider::class.java)
            )
            if (ids.isEmpty()) return
            for (id in ids) render(context, manager, id)
        }

        private fun render(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_deadlines)

            // Tapping anywhere opens the app.
            val launch = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP }
            if (launch != null) {
                val pending = PendingIntent.getActivity(
                    context,
                    0,
                    launch,
                    // FLAG_IMMUTABLE is mandatory from Android 12 onward.
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pending)
            }

            // Refresh button. This redraws from the stored snapshot and
            // recomputes every "days left" against today's date — which is
            // the part that actually goes stale, since the deadlines
            // themselves rarely move. Pulling NEW positions needs the app,
            // because a widget runs in the launcher's process with no Dart
            // VM and no Firestore.
            val refresh = Intent(context, DeadlineWidgetProvider::class.java)
                .setAction(ACTION_REFRESH)
            views.setOnClickPendingIntent(
                R.id.widget_refresh,
                PendingIntent.getBroadcast(
                    context,
                    widgetId,
                    refresh,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )

            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_SNAPSHOT, null)

            if (raw == null) {
                showEmpty(views, "Open the app to sync your deadlines")
                manager.updateAppWidget(widgetId, views)
                return
            }

            try {
                val root = JSONObject(raw)
                val items = root.optJSONArray("items")
                val total = root.optInt("total", 0)

                if (items == null || items.length() == 0) {
                    showEmpty(views, "No deadlines coming up")
                } else {
                    views.setViewVisibility(R.id.widget_empty, View.GONE)

                    for (i in ROW_IDS.indices) {
                        if (i < items.length()) {
                            val item = items.getJSONObject(i)
                            val days = daysUntil(item.optString("deadline"))
                                ?: item.optInt("daysLeft", -1)

                            views.setViewVisibility(ROW_IDS[i], View.VISIBLE)
                            views.setTextViewText(TITLE_IDS[i], item.optString("title"))
                            views.setTextViewText(META_IDS[i], item.optString("subtitle"))
                            views.setTextViewText(DAYS_IDS[i], formatDays(days))
                            views.setTextColor(DAYS_IDS[i], colorForDays(days))
                        } else {
                            views.setViewVisibility(ROW_IDS[i], View.GONE)
                        }
                    }

                    val hidden = total - items.length()
                    if (hidden > 0) {
                        views.setViewVisibility(R.id.widget_more, View.VISIBLE)
                        views.setTextViewText(R.id.widget_more, "+$hidden more")
                    } else {
                        views.setViewVisibility(R.id.widget_more, View.GONE)
                    }
                }

                views.setTextViewText(R.id.widget_synced, syncedLabel(root))
            } catch (e: Exception) {
                showEmpty(views, "Could not read saved deadlines")
            }

            manager.updateAppWidget(widgetId, views)
        }

        private fun showEmpty(views: RemoteViews, message: String) {
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            views.setTextViewText(R.id.widget_empty, message)
            views.setViewVisibility(R.id.widget_more, View.GONE)
            for (id in ROW_IDS) views.setViewVisibility(id, View.GONE)
        }

        private fun formatDays(days: Int): String = when {
            days < 0 -> "—"
            days == 0 -> "today"
            days == 1 -> "1 day"
            else -> "$days days"
        }

        private fun colorForDays(days: Int): Int = when {
            days <= 3 -> 0xFFFF6B6B.toInt()   // closing now
            days <= 7 -> 0xFFFFB86B.toInt()   // this week
            else -> 0xFFB9C1FF.toInt()        // comfortable
        }

        /**
         * Whole days from today to an ISO yyyy-MM-dd deadline.
         *
         * Recomputed on every draw so the counts stay right without the app:
         * a snapshot taken on Monday would otherwise still claim "3 days" on
         * Thursday.
         */
        private fun daysUntil(iso: String?): Int? {
            if (iso.isNullOrBlank() || iso.length < 10) return null
            return try {
                val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
                val target = fmt.parse(iso.substring(0, 10)) ?: return null
                val today = fmt.parse(fmt.format(Date())) ?: return null
                val diff = target.time - today.time
                Math.round(diff / 86_400_000.0).toInt()
            } catch (e: Exception) {
                null
            }
        }

        private fun syncedLabel(root: JSONObject): String {
            val iso = root.optString("syncedAt", "")
            return try {
                val parser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
                val parsed = parser.parse(iso.substring(0, 19)) ?: return "Synced"
                "Synced " + SimpleDateFormat("d MMM HH:mm", Locale.US).format(parsed)
            } catch (e: Exception) {
                "Synced"
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) redrawAll(context)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) render(context, appWidgetManager, id)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle
    ) {
        render(context, appWidgetManager, appWidgetId)
    }
}

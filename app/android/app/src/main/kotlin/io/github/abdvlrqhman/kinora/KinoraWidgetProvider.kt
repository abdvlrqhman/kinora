package io.github.abdvlrqhman.kinora

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/**
 * Continue watching on the home screen: up to three titles Kinora wrote
 * as JSON ("items": title, sub, progress 0..1, open path, poster file).
 * A row opens its title; the rest of the card opens Kinora.
 */
class KinoraWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val items = try {
            JSONArray(widgetData.getString("items", "[]"))
        } catch (e: Exception) {
            JSONArray()
        }
        val rows = listOf(
            Row(R.id.row0, R.id.poster0, R.id.title0, R.id.sub0, R.id.progress0),
            Row(R.id.row1, R.id.poster1, R.id.title1, R.id.sub1, R.id.progress1),
            Row(R.id.row2, R.id.poster2, R.id.title2, R.id.sub2, R.id.progress2),
        )
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.kinora_widget)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("kinora://home")),
            )
            views.setViewVisibility(R.id.empty, if (items.length() == 0) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.rows, if (items.length() == 0) View.GONE else View.VISIBLE)
            rows.forEachIndexed { i, row ->
                if (i >= items.length()) {
                    views.setViewVisibility(row.root, View.GONE)
                    return@forEachIndexed
                }
                val item = items.getJSONObject(i)
                views.setViewVisibility(row.root, View.VISIBLE)
                views.setTextViewText(row.title, item.optString("title"))
                views.setTextViewText(row.sub, item.optString("sub"))
                val progress = (item.optDouble("progress", 0.0) * 100).toInt().coerceIn(0, 100)
                views.setProgressBar(row.progress, 100, progress, false)
                views.setViewVisibility(row.progress, if (progress > 0) View.VISIBLE else View.INVISIBLE)
                val poster = item.optString("poster")
                val bitmap = if (poster.isEmpty()) null else BitmapFactory.decodeFile(poster)
                if (bitmap != null) views.setImageViewBitmap(row.poster, bitmap)
                else views.setImageViewResource(row.poster, android.R.color.transparent)
                views.setOnClickPendingIntent(
                    row.root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("kinora:/" + item.optString("open")),
                    ),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private data class Row(val root: Int, val poster: Int, val title: Int, val sub: Int, val progress: Int)
}

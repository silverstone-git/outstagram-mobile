package com.cyto.outstagram

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Home-screen streak widget. The app writes the streak (lib/features/streak/streak_widget.dart):
 * streak_days, streak_last_day (YYYY-MM-DD in the user's zone), streak_freezes, streak_tz, signed_in.
 * The widget works out "done today / at risk / ended" itself, so it stays right after midnight even
 * if the app isn't opened (Android refreshes it every 30 minutes). Tapping it opens /streak.
 */
class StreakWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, data: SharedPreferences) {
        val signedIn = data.getBoolean("signed_in", false)
        val days = data.getInt("streak_days", 0)
        val freezes = data.getInt("streak_freezes", 0)
        val lastDay = data.getString("streak_last_day", null)
        val zone = runCatching { ZoneId.of(data.getString("streak_tz", null) ?: "") }.getOrDefault(ZoneId.systemDefault())
        val today = LocalDate.now(zone)
        val gap = lastDay?.let { runCatching { ChronoUnit.DAYS.between(LocalDate.parse(it), today) }.getOrNull() }

        // gap 0: done today; 1: alive, today's quiz pending; 2..freezes+1: a freeze will cover it; else ended
        val alive = gap != null && days > 0 && gap <= 1 + freezes
        val shown = if (alive) days else 0
        val status = when {
            !signedIn -> "Sign in to start"
            gap == 0L && days > 0 -> "Done today ✓"
            alive && gap == 1L -> "Quiz pending today"
            alive -> "A freeze covers you ❄"
            else -> "Start a streak today"
        }

        val tap = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW).setData(Uri.parse("outstagram://app/streak")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.streak_widget).apply {
                setTextViewText(R.id.streak_days, shown.toString())
                setTextViewText(R.id.streak_label, "day streak")
                setTextViewText(R.id.streak_status, status)
                setInt(R.id.streak_flame, "setImageAlpha", if (shown > 0) 255 else 110)
                setOnClickPendingIntent(R.id.streak_root, tap)
            }
            manager.updateAppWidget(id, views)
        }
    }
}

package app.encoresheets.encoresheets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

class RehearsalWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        manager.updateAppWidget(ids, buildViews(context))
    }

    companion object {
        private const val STORE = "practice_widget"

        fun publish(context: Context, reached: Int, total: Int) {
            context.getSharedPreferences(STORE, Context.MODE_PRIVATE).edit()
                .putInt("reached", reached).putInt("total", total).apply()
            AppWidgetManager.getInstance(context).updateAppWidget(
                ComponentName(context, RehearsalWidget::class.java), buildViews(context)
            )
        }

        private fun buildViews(context: Context): RemoteViews {
            val values = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
            val total = values.getInt("total", 0)
            val text = if (total == 0) context.getString(R.string.widget_empty)
            else context.getString(R.string.widget_progress, values.getInt("reached", 0), total)
            return RemoteViews(context.packageName, R.layout.rehearsal_widget).apply {
                setTextViewText(R.id.widget_progress, text)
                setOnClickPendingIntent(R.id.widget_library, open(context, "library"))
                setOnClickPendingIntent(R.id.widget_practice, open(context, "practice"))
            }
        }

        private fun open(context: Context, screen: String): PendingIntent {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("encoresheets://$screen"), context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)
        }
    }
}

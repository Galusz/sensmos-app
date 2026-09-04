package com.zkv.sensmos

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

/**
 * Widgety na pulpit — same skróty do apki, bez danych i bez sekretów.
 *
 * Trzy warianty, bo nie każdy chce oba przyciski: [SensmosWidgetProvider] (HA + Terminal),
 * [SensmosHaWidgetProvider] i [SensmosTermWidgetProvider]. Cała autoryzacja zostaje w apce
 * (token ownera + klucz parowania), więc dodanie widgetu niczego nie otwiera samo z siebie.
 */
object WidgetLink {
    const val EXTRA_KIND = "sensmos_kind"

    /**
     * Ten sam intent, którym apkę uruchamia launcher (ACTION_MAIN/CATEGORY_LAUNCHER) — dzięki
     * temu stuknięcie w widget WZNAWIA żywą instancję zamiast tworzyć drugą.
     *
     * Własny Intent(ACTION_VIEW) z FLAG_ACTIVITY_NEW_TASK tego nie daje: MainActivity ma
     * `android:taskAffinity=""`, a aktywność z pustą afinicją dostaje przy NEW_TASK świeże
     * zadanie za każdym razem — czyli kilka kopii apki, każda z własnym stanem sieci.
     * Cel skrótu jedzie więc w extrasie, nie w adresie.
     */
    fun open(context: Context, kind: String, req: Int): PendingIntent {
        val i = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        i.putExtra(EXTRA_KIND, kind)
        i.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context, req, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}

/**
 * Wariant 2×1: pasek marki u góry, pod nim skróty. Które skróty się pojawią, wybiera user
 * przy dodawaniu widgetu (WidgetConfigActivity) — dlatego RemoteViews budujemy per widget,
 * a nie raz dla wszystkich.
 */
class SensmosWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val ha = WidgetConfigActivity.showHa(context, id)
            val term = WidgetConfigActivity.showTerm(context, id)
            val v = RemoteViews(context.packageName, R.layout.sensmos_widget)
            v.setViewVisibility(R.id.widget_ha_tile, if (ha) View.VISIBLE else View.GONE)
            v.setViewVisibility(R.id.widget_term_tile, if (term) View.VISIBLE else View.GONE)
            v.setViewVisibility(R.id.widget_brand,
                if (WidgetConfigActivity.showLabel(context, id)) View.VISIBLE else View.GONE)
            if (ha) v.setOnClickPendingIntent(R.id.widget_ha, WidgetLink.open(context, "ha", 1))
            if (term) v.setOnClickPendingIntent(R.id.widget_term, WidgetLink.open(context, "term", 2))
            mgr.updateAppWidget(id, v)
        }
    }

    /** Usunięty widget zabiera ze sobą swoje ustawienia — inaczej rosłyby w nieskończoność. */
    override fun onDeleted(context: Context, ids: IntArray) {
        for (id in ids) WidgetConfigActivity.forget(context, id)
    }
}

/** Wariant jednoprzyciskowy — wspólna baza dla „tylko HA" i „tylko Terminal". */
abstract class SingleShortcutWidget : AppWidgetProvider() {
    protected abstract val kind: String
    protected abstract val icon: Int
    protected abstract val req: Int

    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        val v = RemoteViews(context.packageName, R.layout.sensmos_widget_one)
        v.setImageViewResource(R.id.widget_one_btn, icon)
        val pi = WidgetLink.open(context, kind, req)
        v.setOnClickPendingIntent(R.id.widget_one_btn, pi)
        v.setOnClickPendingIntent(R.id.widget_one_root, pi)
        for (id in ids) mgr.updateAppWidget(id, v)
    }
}

class SensmosHaWidgetProvider : SingleShortcutWidget() {
    override val kind = "ha"
    override val icon = R.drawable.ic_ha_house
    override val req = 11
}

class SensmosTermWidgetProvider : SingleShortcutWidget() {
    override val kind = "term"
    override val icon = R.drawable.ic_term_prompt
    override val req = 12
}

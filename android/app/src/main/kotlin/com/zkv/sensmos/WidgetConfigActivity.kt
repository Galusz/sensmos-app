package com.zkv.sensmos

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Ekran konfiguracji widgetu — pokazywany przez launcher przy jego dodawaniu.
 *
 * Na razie są dwa skróty (terminal i panel HA), więc konfiguracja to wybór, które mają być
 * na kaflu i czy podpisywać go nazwą. Ustawienia trzymamy per `appWidgetId`, bo ten sam
 * widget można dodać kilka razy w różnych wariantach.
 *
 * Zwykłe widoki Androida, bez Fluttera: konfiguracja musi wstać natychmiast, także wtedy,
 * gdy apka nie działa.
 */
class WidgetConfigActivity : Activity() {

    companion object {
        private const val PREFS = "sensmos_widgets"
        fun showHa(c: Context, id: Int) = c.getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("ha_$id", true)
        fun showTerm(c: Context, id: Int) = c.getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("term_$id", true)
        fun showLabel(c: Context, id: Int) = c.getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("label_$id", false)
        fun forget(c: Context, id: Int) = c.getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .remove("ha_$id").remove("term_$id").remove("label_$id").apply()
    }

    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Anulowanie (BACK) musi zostawić launcher bez widgetu — stąd RESULT_CANCELED z góry.
        setResult(RESULT_CANCELED, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) { finish(); return }

        val pad = (16 * resources.displayMetrics.density).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#0A0D12"))
            setPadding(pad, pad, pad, pad)
        }

        root.addView(TextView(this).apply {
            text = "Sensmos"
            setTextColor(Color.parseColor("#C8D0E8"))
            textSize = 20f
        })
        root.addView(TextView(this).apply {
            text = getString(R.string.widget_cfg_hint)
            setTextColor(Color.parseColor("#5A6380"))
            textSize = 13f
            setPadding(0, pad / 3, 0, pad / 2)
        })

        val ha = check(getString(R.string.widget_cfg_ha), showHa(this, widgetId))
        val term = check(getString(R.string.widget_cfg_term), showTerm(this, widgetId))
        val label = check(getString(R.string.widget_cfg_label), showLabel(this, widgetId))
        root.addView(ha); root.addView(term); root.addView(label)

        root.addView(Button(this).apply {
            text = getString(R.string.widget_cfg_save)
            setBackgroundColor(Color.parseColor("#00E5B0"))
            setTextColor(Color.parseColor("#0A0D12"))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = pad }
            gravity = Gravity.CENTER
            setOnClickListener {
                // Odznaczenie obu skrótów zostawiłoby pusty kafel — wtedy trzymamy oba.
                val h = ha.isChecked || !term.isChecked
                val t = term.isChecked || !ha.isChecked
                getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                    .putBoolean("ha_$widgetId", h)
                    .putBoolean("term_$widgetId", t)
                    .putBoolean("label_$widgetId", label.isChecked)
                    .apply()
                val mgr = AppWidgetManager.getInstance(this@WidgetConfigActivity)
                SensmosWidgetProvider().onUpdate(this@WidgetConfigActivity, mgr, intArrayOf(widgetId))
                setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
                finish()
            }
        })

        setContentView(root)
    }

    private fun check(label: String, on: Boolean) = CheckBox(this).apply {
        text = label
        isChecked = on
        setTextColor(Color.parseColor("#C8D0E8"))
    }
}

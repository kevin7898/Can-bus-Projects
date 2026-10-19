package ca.jettatelemetry.app

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Platform-only launcher used to isolate failures before Compose starts.
 * It deliberately has no AndroidX or Compose references.
 */
class BootstrapActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installCrashRecorder()
        super.onCreate(savedInstanceState)

        val report = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(LAST_CRASH, null)
        if (report != null) showCrashReport(report) else showLauncher()
    }

    private fun showLauncher() {
        val column = baseColumn()
        column.addView(title("JETTA RECORDER"))
        column.addView(body("Startup diagnostic 0.3.2\n\nThe platform launcher is running. Tap below to start the dashboard."))
        column.addView(Button(this).apply {
            text = "Launch dashboard"
            setOnClickListener {
                startActivity(Intent(this@BootstrapActivity, MainActivity::class.java))
            }
        }, matchWrap())
        setContentView(ScrollView(this).apply { addView(column) })
    }

    private fun showCrashReport(report: String) {
        val column = baseColumn()
        column.addView(title("JETTA RECORDER — CRASH CAPTURED"))
        column.addView(body("The dashboard failed after the bootstrap launcher. Copy this report and send it back."))
        column.addView(Button(this).apply {
            text = "Copy crash report"
            setOnClickListener {
                getSystemService(ClipboardManager::class.java)
                    .setPrimaryClip(ClipData.newPlainText("Jetta Recorder crash", report))
            }
        }, matchWrap())
        column.addView(Button(this).apply {
            text = "Clear report and retry"
            setOnClickListener {
                getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(LAST_CRASH).commit()
                recreate()
            }
        }, matchWrap())
        column.addView(TextView(this).apply {
            text = report
            setTextColor(Color.WHITE)
            textSize = 10f
            setTextIsSelectable(true)
            setPadding(0, padding(), 0, 0)
        })
        setContentView(ScrollView(this).apply { addView(column) })
    }

    private fun installCrashRecorder() {
        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, failure ->
            runCatching {
                getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putString(LAST_CRASH, failure.stackTraceToString())
                    .commit()
            }
            if (previousHandler != null) previousHandler.uncaughtException(thread, failure)
            else Runtime.getRuntime().exit(10)
        }
    }

    private fun baseColumn() = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(padding(), padding(), padding(), padding())
        setBackgroundColor(Color.rgb(5, 6, 8))
    }

    private fun title(value: String) = TextView(this).apply {
        text = value
        setTextColor(Color.rgb(185, 227, 255))
        textSize = 20f
    }

    private fun body(value: String) = TextView(this).apply {
        text = value
        setTextColor(Color.LTGRAY)
        textSize = 15f
        setPadding(0, padding() / 2, 0, padding())
    }

    private fun padding() = (18 * resources.displayMetrics.density).toInt()

    private fun matchWrap() = ViewGroup.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    )

    private companion object {
        const val PREFS = "startup_diagnostics"
        const val LAST_CRASH = "last_crash"
    }
}

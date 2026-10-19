package ca.jettatelemetry.app

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.graphics.Color
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModelProvider
import ca.jettatelemetry.app.ui.JettaRecorderApp
import ca.jettatelemetry.app.ui.MainViewModel

class MainActivity : ComponentActivity() {
    private lateinit var viewModel: MainViewModel

    private val bluetoothPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) viewModel.refreshDevices()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        installCrashRecorder()
        super.onCreate(savedInstanceState)

        val previousCrash = getPreferences(Context.MODE_PRIVATE).getString(LAST_CRASH, null)
        if (previousCrash != null) {
            showCrashReport(previousCrash)
            return
        }

        // Construct the ViewModel only after the Activity is attached. This
        // avoids touching applicationContext from a property delegate during
        // framework startup on older OxygenOS builds.
        viewModel = ViewModelProvider(
            this,
            MainViewModel.Factory(applicationContext)
        )[MainViewModel::class.java]
        setContent { JettaRecorderApp(viewModel) }

        // Post permission work until the first frame has been attached. Some
        // older vendor Android builds are unhappy when a launcher is invoked
        // in the same startup stack as setContent.
        window.decorView.post {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
            ) {
                bluetoothPermission.launch(Manifest.permission.BLUETOOTH_CONNECT)
            } else {
                viewModel.refreshDevices()
            }
        }
    }

    private fun installCrashRecorder() {
        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, failure ->
            runCatching {
                getPreferences(Context.MODE_PRIVATE)
                    .edit()
                    .putString(LAST_CRASH, failure.stackTraceToString())
                    .commit()
            }
            previousHandler?.uncaughtException(thread, failure)
        }
    }

    private fun showCrashReport(report: String) {
        val padding = (18 * resources.displayMetrics.density).toInt()
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
            setBackgroundColor(Color.rgb(5, 6, 8))
        }
        column.addView(TextView(this).apply {
            text = "JETTA RECORDER — STARTUP REPORT"
            setTextColor(Color.rgb(185, 227, 255))
            textSize = 18f
        })
        column.addView(TextView(this).apply {
            text = "The previous launch failed. Copy this report or take screenshots, then tap Try app again."
            setTextColor(Color.LTGRAY)
            textSize = 14f
            setPadding(0, padding / 2, 0, padding / 2)
        })
        column.addView(Button(this).apply {
            text = "Copy crash report"
            setOnClickListener {
                getSystemService(ClipboardManager::class.java)
                    .setPrimaryClip(ClipData.newPlainText("Jetta Recorder crash", report))
            }
        }, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        column.addView(Button(this).apply {
            text = "Try app again"
            setOnClickListener {
                getPreferences(Context.MODE_PRIVATE).edit().remove(LAST_CRASH).commit()
                recreate()
            }
        }, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        column.addView(TextView(this).apply {
            text = report
            setTextColor(Color.WHITE)
            textSize = 10f
            setTextIsSelectable(true)
            setPadding(0, padding, 0, 0)
        })
        setContentView(ScrollView(this).apply { addView(column) })
    }

    private companion object {
        const val LAST_CRASH = "last_startup_crash"
    }
}


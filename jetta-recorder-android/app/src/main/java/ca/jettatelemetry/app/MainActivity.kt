package ca.jettatelemetry.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
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
        super.onCreate(savedInstanceState)

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

}


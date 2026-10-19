package ca.jettatelemetry.app

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import ca.jettatelemetry.app.ui.JettaRecorderApp
import ca.jettatelemetry.app.ui.MainViewModel

class MainActivity : ComponentActivity() {
    private val viewModel: MainViewModel by viewModels { MainViewModel.Factory(applicationContext) }

    private val bluetoothPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) viewModel.refreshDevices()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { JettaRecorderApp(viewModel) }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            bluetoothPermission.launch(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            viewModel.refreshDevices()
        }
    }
}


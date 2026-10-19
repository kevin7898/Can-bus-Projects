package ca.jettatelemetry.app.ui

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import ca.jettatelemetry.app.data.ObdRepository
import ca.jettatelemetry.app.model.MainUiState
import kotlinx.coroutines.flow.StateFlow

class MainViewModel(private val repository: ObdRepository) : ViewModel() {
    val state: StateFlow<MainUiState> = repository.state

    fun refreshDevices() = repository.refreshBondedDevices()
    fun selectDevice(address: String) = repository.selectDevice(address)
    fun connect() = repository.connect()
    fun disconnect() = repository.disconnect()
    fun sendCommand(command: String) = repository.sendConsoleCommand(command)
    fun clearConsole() = repository.clearConsole()
    fun startRawCanProbe() = repository.startRawCanProbe()
    fun stopRawCanProbe() = repository.stopRawCanProbe()
    fun exportRawCanProbe(destination: Uri) = repository.exportRawCanProbe(destination)

    override fun onCleared() {
        repository.close()
        super.onCleared()
    }

    class Factory(private val context: Context) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            MainViewModel(ObdRepository(context.applicationContext)) as T
    }
}


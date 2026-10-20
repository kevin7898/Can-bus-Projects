package ca.jettatelemetry.app.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performClick
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.LocalClipboardManager
import ca.jettatelemetry.app.model.ConnectionPhase
import ca.jettatelemetry.app.model.ConsoleEntry
import ca.jettatelemetry.app.model.MainUiState
import ca.jettatelemetry.app.model.DiagnosticDiscoveryState
import ca.jettatelemetry.app.model.DiagnosticProbeResult
import ca.jettatelemetry.app.model.DiagnosticProbeStatus
import ca.jettatelemetry.app.obd.JettaDiagnosticDiscovery
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.assertTrue

class ConnectionLogTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun standardSnapshotRemainsVisibleAfterProprietaryNoDataResults() {
        val standard = DiagnosticProbeResult(
            "obd_dpf_pressure", "Standard DPF pressures", "7A", "DPF",
            service = "01", status = DiagnosticProbeStatus.SUPPORTED,
            note = "Differential: -1.00 kPa; Inlet: 100.00 kPa; Outlet: 99.00 kPa"
        )
        val candidates = JettaDiagnosticDiscovery.probes.map {
            DiagnosticProbeResult(it.id, it.name, it.did, it.category, status = DiagnosticProbeStatus.NO_DATA)
        }
        compose.setContent {
            JettaRecorderScreen(
                state = MainUiState(
                    connectionPhase = ConnectionPhase.LIVE,
                    diagnosticDiscovery = DiagnosticDiscoveryState(
                        completedCount = 21, totalCount = 21, results = listOf(standard) + candidates
                    )
                ),
                onRefresh = {}, onSelectDevice = {}, onConnect = {}, onDisconnect = {},
                onSendCommand = {}, onClearConsole = {}, onStartRawCan = {}, onStopRawCan = {},
                onExportRawCan = {}, onStartDiscovery = {}, onStopDiscovery = {}, onExportDiscovery = {}
            )
        }
        compose.onNodeWithText("Standard DPF pressures").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("017A • DPF").assertIsDisplayed()
        compose.onNodeWithText("Differential: -1.00 kPa; Inlet: 100.00 kPa; Outlet: 99.00 kPa")
            .performScrollTo().assertIsDisplayed()
    }

    @Test
    fun failedConnectionKeepsTheReportAccessible() {
        var clipboard: ClipboardManager? = null
        compose.setContent {
            clipboard = LocalClipboardManager.current
            JettaRecorderScreen(
                state = MainUiState(
                    connectionPhase = ConnectionPhase.FAILED,
                    errorMessage = "Live polling stopped: Command 010C timed out",
                    console = listOf(ConsoleEntry(1, 0, ConsoleEntry.Direction.SYSTEM, "SEARCHING..."))
                ),
                onRefresh = {}, onSelectDevice = {}, onConnect = {}, onDisconnect = {},
                onSendCommand = {}, onClearConsole = {}, onStartRawCan = {}, onStopRawCan = {},
                onExportRawCan = {}, onStartDiscovery = {}, onStopDiscovery = {}, onExportDiscovery = {}
            )
        }
        compose.onNodeWithText("FAULT").assertIsDisplayed()
        compose.onNodeWithText("Connection log").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Copy report").assertIsDisplayed()
        compose.onNodeWithText("SEARCHING...", substring = true).assertIsDisplayed()
        compose.onNodeWithText("Copy report").performClick()
        compose.runOnIdle {
            val copied = requireNotNull(clipboard?.getText()).text
            assertTrue(copied.contains("Command 010C timed out"))
            assertTrue(copied.contains("SEARCHING..."))
        }
    }
}

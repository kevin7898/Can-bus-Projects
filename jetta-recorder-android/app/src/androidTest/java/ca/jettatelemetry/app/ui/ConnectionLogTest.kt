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
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.assertTrue

class ConnectionLogTest {
    @get:Rule
    val compose = createComposeRule()

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

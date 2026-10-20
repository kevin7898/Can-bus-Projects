package ca.jettatelemetry.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ca.jettatelemetry.app.model.ConnectionPhase
import ca.jettatelemetry.app.model.ConsoleEntry
import ca.jettatelemetry.app.model.DiagnosticDiscoveryState
import ca.jettatelemetry.app.model.DiagnosticProbeResult
import ca.jettatelemetry.app.model.DiagnosticProbeStatus
import ca.jettatelemetry.app.model.DerivedSignals
import ca.jettatelemetry.app.model.LiveVehicleData
import ca.jettatelemetry.app.model.MainUiState
import ca.jettatelemetry.app.model.PairedObdDevice
import ca.jettatelemetry.app.model.RawCanProbeState
import ca.jettatelemetry.app.BuildConfig
import java.text.DateFormat
import java.util.Date

private val Night = Color(0xFF050608)
private val Panel = Color(0xFF11151B)
private val PanelRaised = Color(0xFF171D25)
private val VwBlue = Color(0xFF35A7FF)
private val IceBlue = Color(0xFFB9E3FF)
private val Muted = Color(0xFF8793A2)
private val Good = Color(0xFF5BDB9B)
private val Warning = Color(0xFFFFC857)
private val Red = Color(0xFFFF6B6B)

@Composable
fun JettaRecorderApp(viewModel: MainViewModel) {
    val state by viewModel.state.collectAsState()
    val csvExporter = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("text/csv")
    ) { uri -> uri?.let(viewModel::exportRawCanProbe) }
    val discoveryExporter = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("text/csv")
    ) { uri -> uri?.let(viewModel::exportDiagnosticDiscovery) }
    JettaTheme {
        JettaRecorderScreen(
            state = state,
            onRefresh = viewModel::refreshDevices,
            onSelectDevice = viewModel::selectDevice,
            onConnect = viewModel::connect,
            onDisconnect = viewModel::disconnect,
            onSendCommand = viewModel::sendCommand,
            onClearConsole = viewModel::clearConsole,
            onStartRawCan = viewModel::startRawCanProbe,
            onStopRawCan = viewModel::stopRawCanProbe,
            onExportRawCan = {
                csvExporter.launch("jetta-raw-can-${System.currentTimeMillis()}.csv")
            },
            onStartDiscovery = viewModel::startDiagnosticDiscovery,
            onStopDiscovery = viewModel::stopDiagnosticDiscovery,
            onExportDiscovery = {
                discoveryExporter.launch("jetta-diagnostic-discovery-${System.currentTimeMillis()}.csv")
            }
        )
    }
}

@Composable
private fun JettaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = androidx.compose.material3.darkColorScheme(
            primary = VwBlue,
            secondary = IceBlue,
            background = Night,
            surface = Panel,
            surfaceVariant = PanelRaised,
            onBackground = Color.White,
            onSurface = Color.White
        ),
        content = content
    )
}

@Composable
fun JettaRecorderScreen(
    state: MainUiState,
    onRefresh: () -> Unit,
    onSelectDevice: (String) -> Unit,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
    onSendCommand: (String) -> Unit,
    onClearConsole: () -> Unit,
    onStartRawCan: () -> Unit,
    onStopRawCan: () -> Unit,
    onExportRawCan: () -> Unit,
    onStartDiscovery: () -> Unit,
    onStopDiscovery: () -> Unit,
    onExportDiscovery: () -> Unit
) {
    Surface(modifier = Modifier.fillMaxSize(), color = Night) {
        Column(modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 12.dp)) {
            Header(state)
            Spacer(Modifier.height(12.dp))
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val landscape = maxWidth > maxHeight
                if (state.connectionPhase == ConnectionPhase.LIVE) {
                    LiveContent(
                        state = state,
                        landscape = landscape,
                        onDisconnect = onDisconnect,
                        onSendCommand = onSendCommand,
                        onClearConsole = onClearConsole,
                        onStartRawCan = onStartRawCan,
                        onStopRawCan = onStopRawCan,
                        onExportRawCan = onExportRawCan,
                        onStartDiscovery = onStartDiscovery,
                        onStopDiscovery = onStopDiscovery,
                        onExportDiscovery = onExportDiscovery
                    )
                } else {
                    ConnectionContent(
                        state = state,
                        landscape = landscape,
                        onRefresh = onRefresh,
                        onSelectDevice = onSelectDevice,
                        onConnect = onConnect
                    )
                }
            }
        }
    }
}

@Composable
private fun Header(state: MainUiState) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("JETTA RECORDER", color = IceBlue, fontWeight = FontWeight.Black, letterSpacing = 1.8.sp)
            Text("HARDWARE PROOF 01", color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
        }
        val (label, color) = when (state.connectionPhase) {
            ConnectionPhase.DISCONNECTED -> "OFFLINE" to Muted
            ConnectionPhase.CONNECTING -> "CONNECTING" to Warning
            ConnectionPhase.INITIALIZING -> "INITIALIZING" to Warning
            ConnectionPhase.LIVE -> "LIVE" to Good
            ConnectionPhase.FAILED -> "FAULT" to Red
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).background(color, RoundedCornerShape(50)))
            Spacer(Modifier.width(7.dp))
            Text(label, color = color, fontWeight = FontWeight.Bold, fontSize = 12.sp)
        }
    }
}

@Composable
private fun ConnectionContent(
    state: MainUiState,
    landscape: Boolean,
    onRefresh: () -> Unit,
    onSelectDevice: (String) -> Unit,
    onConnect: () -> Unit
) {
    val content: @Composable (Modifier) -> Unit = { modifier ->
        Column(modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            state.errorMessage?.let { message ->
                Card(
                    colors = CardDefaults.cardColors(containerColor = Color(0xFF35191C)),
                    shape = RoundedCornerShape(14.dp)
                ) {
                    Text(message, color = Color(0xFFFFB4B4), modifier = Modifier.padding(14.dp))
                }
            }
            SectionCard {
                Text("Paired adapters", fontWeight = FontWeight.Bold, fontSize = 18.sp)
                Spacer(Modifier.height(5.dp))
                Text(
                    "Pair the OBDLink MX+ in Android settings once. This app connects to the bonded device over classic Bluetooth.",
                    color = Muted,
                    fontSize = 13.sp
                )
                Spacer(Modifier.height(12.dp))
                if (state.devices.isEmpty()) {
                    Text("No paired Bluetooth devices visible.", color = Warning)
                } else {
                    state.devices.forEach { device ->
                        DeviceRow(device, device.address == state.selectedAddress, onSelectDevice)
                    }
                }
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = onRefresh) { Text("Refresh") }
                    Button(
                        onClick = onConnect,
                        enabled = state.selectedAddress != null && state.connectionPhase != ConnectionPhase.CONNECTING,
                        colors = ButtonDefaults.buttonColors(containerColor = VwBlue)
                    ) { Text("Connect") }
                }
            }
        }
    }

    if (landscape) {
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                content(Modifier.fillMaxWidth())
            }
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                if (state.console.isNotEmpty()) ConnectionLog(state)
                else ProofChecklist(Modifier.fillMaxWidth())
            }
        }
    } else {
        LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { content(Modifier.fillMaxWidth()) }
            if (state.console.isNotEmpty()) item { ConnectionLog(state) }
            item { ProofChecklist(Modifier.fillMaxWidth()) }
        }
    }

}

@Composable
private fun ConnectionLog(state: MainUiState) {
    val clipboard = LocalClipboardManager.current
    val report = remember(state.console, state.errorMessage) {
        buildString {
            appendLine("Jetta Recorder ${BuildConfig.VERSION_NAME}")
            state.errorMessage?.let { appendLine(it) }
            appendLine()
            state.console.forEach { entry ->
                appendLine("${java.time.Instant.ofEpochMilli(entry.timestampMillis)} ${entry.direction}: ${entry.text}")
            }
        }
    }
    SectionCard(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Connection log", fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            TextButton(onClick = { clipboard.setText(AnnotatedString(report)) }) { Text("Copy report") }
        }
        Text("Kept after a connection or polling failure.", color = Muted, fontSize = 12.sp)
        SelectionContainer {
            Text(
                report,
                color = IceBlue,
                fontFamily = FontFamily.Monospace,
                fontSize = 10.sp,
                modifier = Modifier.fillMaxWidth().height(230.dp).verticalScroll(rememberScrollState())
            )
        }
    }
}

@Composable
private fun DeviceRow(device: PairedObdDevice, selected: Boolean, onSelectDevice: (String) -> Unit) {
    val borderColor = if (selected) VwBlue else Color.Transparent
    TextButton(
        onClick = { onSelectDevice(device.address) },
        modifier = Modifier.fillMaxWidth().border(1.dp, borderColor, RoundedCornerShape(12.dp))
    ) {
        Column(Modifier.fillMaxWidth()) {
            Text(device.name, color = if (selected) IceBlue else Color.White, fontWeight = FontWeight.SemiBold)
            Text(device.address, color = Muted, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
        }
    }
}

@Composable
private fun ProofChecklist(modifier: Modifier) {
    SectionCard(modifier) {
        Text("First-drive gate", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Spacer(Modifier.height(10.dp))
        listOf(
            "Stable MX+ RFCOMM connection",
            "ELM/STN initialization and protocol detection",
            "Live RPM, speed, coolant and manifold pressure",
            "Barometric correction for true gauge boost",
            "Measured successful samples per second"
        ).forEach { item ->
            Row(Modifier.padding(vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("○", color = VwBlue, fontSize = 18.sp)
                Spacer(Modifier.width(9.dp))
                Text(item, color = IceBlue, fontSize = 14.sp)
            }
        }
    }
}

@Composable
private fun LiveContent(
    state: MainUiState,
    landscape: Boolean,
    onDisconnect: () -> Unit,
    onSendCommand: (String) -> Unit,
    onClearConsole: () -> Unit,
    onStartRawCan: () -> Unit,
    onStopRawCan: () -> Unit,
    onExportRawCan: () -> Unit,
    onStartDiscovery: () -> Unit,
    onStopDiscovery: () -> Unit,
    onExportDiscovery: () -> Unit
) {
    var showConsole by remember { mutableStateOf(false) }
    val dashboard: @Composable (Modifier) -> Unit = { modifier ->
        LazyColumn(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { DualDial(state.vehicleData) }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    MetricTile("COOLANT", state.vehicleData.coolantC?.let { "%.0f°".format(it) } ?: "—", "C", Modifier.weight(1f))
                    MetricTile("BOOST", DerivedSignals.kpaToPsi(state.vehicleData.boostGaugeKpa)?.let { "%+.1f".format(it) } ?: "—", "PSI", Modifier.weight(1f))
                    MetricTile("SAMPLE RATE", "%.1f".format(state.vehicleData.samplesPerSecond), "Hz", Modifier.weight(1f))
                }
            }
            item {
                DiagnosticDiscoveryPanel(
                    discovery = state.diagnosticDiscovery,
                    enabled = !state.rawCanProbe.isCapturing,
                    onStart = onStartDiscovery,
                    onStop = onStopDiscovery,
                    onExport = onExportDiscovery
                )
            }
            item {
                RawCanProbePanel(
                    probe = state.rawCanProbe,
                    enabled = !state.diagnosticDiscovery.isRunning,
                    onStart = onStartRawCan,
                    onStop = onStopRawCan,
                    onExport = onExportRawCan
                )
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    MetricTile("MAP ABS", state.vehicleData.mapAbsoluteKpa?.let { "%.0f".format(it) } ?: "—", "kPa", Modifier.weight(1f))
                    MetricTile("BARO ABS", state.vehicleData.barometricAbsoluteKpa?.let { "%.0f".format(it) } ?: "—", "kPa", Modifier.weight(1f))
                }
            }
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    TextButton(onClick = { showConsole = !showConsole }) {
                        Text(if (showConsole) "Hide console" else "Open console")
                    }
                    OutlinedButton(onClick = onDisconnect) { Text("Disconnect", color = Red) }
                }
            }
            item {
                AnimatedVisibility(showConsole && !landscape) {
                    ConsolePanel(state.console, onSendCommand, onClearConsole, Modifier.fillMaxWidth())
                }
            }
        }
    }

    if (landscape) {
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            dashboard(Modifier.weight(1.25f).fillMaxHeight())
            ConsolePanel(state.console, onSendCommand, onClearConsole, Modifier.weight(0.75f).fillMaxHeight())
        }
    } else {
        dashboard(Modifier.fillMaxSize())
    }
}

@Composable
private fun RawCanProbePanel(
    probe: RawCanProbeState,
    enabled: Boolean,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onExport: () -> Unit
) {
    SectionCard(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("RAW CAN PROBE", color = IceBlue, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp)
                Text(
                    if (probe.isCapturing) "SILENT • 11-BIT • 500 KBIT/S" else "MX+ PASSIVE CAPTURE",
                    color = if (probe.isCapturing) Good else Muted,
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
            Box(Modifier.size(9.dp).background(if (probe.isCapturing) Good else Muted, RoundedCornerShape(50)))
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ProbeStat("FRAMES", probe.frameCount.toString(), Modifier.weight(1f))
            ProbeStat("UNIQUE IDs", probe.uniqueIdCount.toString(), Modifier.weight(1f))
            ProbeStat("BUS RATE", "%.0f/s".format(probe.framesPerSecond), Modifier.weight(1f))
        }
        Spacer(Modifier.height(10.dp))
        if (probe.recentFrames.isEmpty()) {
            Text(
                "This test tells us whether the Jetta gateway exposes useful broadcast traffic on OBD pins 6/14.",
                color = Muted,
                fontSize = 12.sp
            )
        } else {
            probe.recentFrames.take(5).forEach { frame ->
                Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
                    Text(frame.displayId, color = VwBlue, fontFamily = FontFamily.Monospace, fontSize = 11.sp, modifier = Modifier.width(66.dp))
                    Text(frame.displayData, color = IceBlue, fontFamily = FontFamily.Monospace, fontSize = 11.sp)
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (probe.isCapturing) {
                Button(onClick = onStop, colors = ButtonDefaults.buttonColors(containerColor = Red)) {
                    Text("Stop capture")
                }
            } else {
                Button(onClick = onStart, enabled = enabled, colors = ButtonDefaults.buttonColors(containerColor = VwBlue)) {
                    Text("Start probe")
                }
            }
            OutlinedButton(
                onClick = onExport,
                enabled = probe.captureFileAvailable && !probe.isCapturing
            ) { Text("Export webCAN CSV") }
        }
        if (probe.rejectedLineCount > 0) {
            Text(
                "${probe.rejectedLineCount} adapter/status lines ignored",
                color = Muted,
                fontSize = 10.sp,
                modifier = Modifier.padding(top = 7.dp)
            )
        }
    }
}

@Composable
private fun DiagnosticDiscoveryPanel(
    discovery: DiagnosticDiscoveryState,
    enabled: Boolean,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onExport: () -> Unit
) {
    val supported = discovery.results.count { it.status == DiagnosticProbeStatus.SUPPORTED }
    val rejected = discovery.results.count { it.status == DiagnosticProbeStatus.NEGATIVE_RESPONSE || it.status == DiagnosticProbeStatus.NO_DATA }
    SectionCard(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("JETTA SENSOR DISCOVERY", color = IceBlue, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp)
                Text(
                    if (discovery.isRunning) "READ-ONLY UDS 0x22 • ENGINE ECU" else "CURATED 2014 TDI CANDIDATES",
                    color = if (discovery.isRunning) Good else Muted,
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
            Box(Modifier.size(9.dp).background(if (discovery.isRunning) Good else Muted, RoundedCornerShape(50)))
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ProbeStat("PROGRESS", "${discovery.completedCount}/${discovery.totalCount}", Modifier.weight(1f))
            ProbeStat("SUPPORTED", supported.toString(), Modifier.weight(1f))
            ProbeStat("NO MATCH", rejected.toString(), Modifier.weight(1f))
        }
        Spacer(Modifier.height(10.dp))
        Text(
            "Safely checks boost, oil temperature, fuel-flow and DPF identifiers. Candidate scaling stays unverified until the values make sense on your car.",
            color = Muted,
            fontSize = 12.sp
        )
        discovery.runError?.let { message ->
            Text("Discovery stopped: $message", color = Red, fontSize = 12.sp)
        }
        val visibleResults = discovery.results.filter {
            it.status != DiagnosticProbeStatus.PENDING && it.status != DiagnosticProbeStatus.CANCELLED
        }.takeLast(6).reversed()
        if (visibleResults.isNotEmpty()) {
            Spacer(Modifier.height(9.dp))
            visibleResults.forEach { result -> DiscoveryResultRow(result) }
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (discovery.isRunning) {
                Button(onClick = onStop, colors = ButtonDefaults.buttonColors(containerColor = Red)) {
                    Text("Stop discovery")
                }
            } else {
                Button(onClick = onStart, enabled = enabled, colors = ButtonDefaults.buttonColors(containerColor = VwBlue)) {
                    Text("Run discovery")
                }
            }
            OutlinedButton(
                onClick = onExport,
                enabled = discovery.captureFileAvailable && !discovery.isRunning
            ) { Text("Export results") }
        }
    }
}

@Composable
private fun DiscoveryResultRow(result: DiagnosticProbeResult) {
    val (status, color) = when (result.status) {
        DiagnosticProbeStatus.SUPPORTED -> "FOUND" to Good
        DiagnosticProbeStatus.RUNNING -> "READING" to Warning
        DiagnosticProbeStatus.NEGATIVE_RESPONSE -> "REJECTED" to Muted
        DiagnosticProbeStatus.NO_DATA -> "NO DATA" to Muted
        DiagnosticProbeStatus.ERROR -> "ERROR" to Red
        DiagnosticProbeStatus.CANCELLED -> "SKIPPED" to Muted
        DiagnosticProbeStatus.PENDING -> "WAITING" to Muted
    }
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(result.name, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Text("22${result.did} • ${result.category}", color = Muted, fontSize = 9.sp, fontFamily = FontFamily.Monospace)
        }
        val value = result.decodedValue?.let { decoded ->
            val digits = if (kotlin.math.abs(decoded) >= 100) 1 else 2
            ", %.${digits}f %s".format(decoded, result.unit.orEmpty())
        }.orEmpty()
        Text("$status$value", color = color, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
    }
}

@Composable
private fun ProbeStat(label: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier.background(PanelRaised, RoundedCornerShape(12.dp)).padding(10.dp)) {
        Text(label, color = Muted, fontSize = 8.sp, letterSpacing = 0.8.sp)
        Text(value, color = Color.White, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
    }
}

@Composable
private fun DualDial(data: LiveVehicleData) {
    SectionCard(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(235.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val stroke = 13.dp.toPx()
                val dialSize = size.minDimension * 0.66f
                val top = (size.height - dialSize) / 2f
                val leftDial = Offset(size.width * 0.29f - dialSize / 2f, top)
                val rightDial = Offset(size.width * 0.71f - dialSize / 2f, top)
                fun dial(topLeft: Offset, fraction: Float) {
                    drawArc(
                        color = Color(0xFF26303A),
                        startAngle = 140f,
                        sweepAngle = 260f,
                        useCenter = false,
                        topLeft = topLeft,
                        size = androidx.compose.ui.geometry.Size(dialSize, dialSize),
                        style = Stroke(stroke, cap = StrokeCap.Round)
                    )
                    drawArc(
                        color = VwBlue,
                        startAngle = 140f,
                        sweepAngle = 260f * fraction.coerceIn(0f, 1f),
                        useCenter = false,
                        topLeft = topLeft,
                        size = androidx.compose.ui.geometry.Size(dialSize, dialSize),
                        style = Stroke(stroke, cap = StrokeCap.Round)
                    )
                }
                dial(leftDial, ((data.speedKmh ?: 0.0) / 220.0).toFloat())
                dial(rightDial, ((data.rpm ?: 0.0) / 6_000.0).toFloat())
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround) {
                DialValue(data.speedKmh?.let { "%.0f".format(it) } ?: "—", "KM/H", "SPEED")
                DialValue(data.rpm?.let { "%.0f".format(it) } ?: "—", "RPM", "ENGINE")
            }
        }
    }
}

@Composable
private fun DialValue(value: String, unit: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(145.dp)) {
        Text(label, color = Muted, fontSize = 10.sp, letterSpacing = 1.5.sp)
        Text(value, color = Color.White, fontSize = 36.sp, fontWeight = FontWeight.Black)
        Text(unit, color = VwBlue, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun MetricTile(label: String, value: String, unit: String, modifier: Modifier = Modifier) {
    Card(modifier, colors = CardDefaults.cardColors(containerColor = PanelRaised), shape = RoundedCornerShape(16.dp)) {
        Column(Modifier.padding(13.dp)) {
            Text(label, color = Muted, fontSize = 9.sp, letterSpacing = 1.sp)
            Row(verticalAlignment = Alignment.Bottom) {
                Text(value, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(4.dp))
                Text(unit, color = VwBlue, fontSize = 10.sp, modifier = Modifier.padding(bottom = 3.dp))
            }
        }
    }
}

@Composable
private fun ConsolePanel(
    entries: List<ConsoleEntry>,
    onSendCommand: (String) -> Unit,
    onClear: () -> Unit,
    modifier: Modifier = Modifier
) {
    var command by remember { mutableStateOf("") }
    val focusManager = LocalFocusManager.current
    SectionCard(modifier) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Adapter console", fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            TextButton(onClick = onClear) { Text("Clear") }
        }
        HorizontalDivider(color = Color(0xFF28313B))
        LazyColumn(Modifier.weight(1f, fill = false).height(230.dp).padding(vertical = 8.dp)) {
            items(entries, key = { it.id }) { entry -> ConsoleLine(entry) }
        }
        OutlinedTextField(
            value = command,
            onValueChange = { command = it.uppercase() },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("AT or OBD command") },
            placeholder = { Text("010C") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = {
                onSendCommand(command)
                command = ""
                focusManager.clearFocus()
            }),
            trailingIcon = {
                TextButton(onClick = {
                    onSendCommand(command)
                    command = ""
                }) { Text("SEND") }
            }
        )
    }
}

@Composable
private fun ConsoleLine(entry: ConsoleEntry) {
    val prefix = when (entry.direction) {
        ConsoleEntry.Direction.SENT -> ">"
        ConsoleEntry.Direction.RECEIVED -> "<"
        ConsoleEntry.Direction.SYSTEM -> "•"
    }
    val color = when (entry.direction) {
        ConsoleEntry.Direction.SENT -> VwBlue
        ConsoleEntry.Direction.RECEIVED -> IceBlue
        ConsoleEntry.Direction.SYSTEM -> Muted
    }
    val time = DateFormat.getTimeInstance(DateFormat.MEDIUM).format(Date(entry.timestampMillis))
    Text(
        "$time  $prefix ${entry.text}",
        color = color,
        fontFamily = FontFamily.Monospace,
        fontSize = 10.sp,
        modifier = Modifier.padding(vertical = 2.dp)
    )
}

@Composable
private fun SectionCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(modifier, colors = CardDefaults.cardColors(containerColor = Panel), shape = RoundedCornerShape(20.dp)) {
        Column(Modifier.fillMaxWidth().padding(16.dp), content = content)
    }
}


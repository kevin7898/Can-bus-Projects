import SwiftUI

struct OverviewView: View {
    @UnitPreferences private var units
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var page: Int
    @State private var selectedTrip: Trip?
    @State private var addingFill = false
    @State private var fuelLogbook = false

    private var presentation: PhoneTodayPresentation {
        .make(state:store.state, now:store.now, gpsStatus:store.gps.status,
              scannerStatus:store.scanner.status, scannerConnected:store.scanner.connected,
              scannerConnecting:store.scanner.connecting)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    dateHeader
                    readinessCard
                    quickActions
                    todayTotals
                    latestDrive
                    latestFill
                }.padding(.horizontal,1).padding(.bottom,8)
                    .frame(maxWidth:.infinity,minHeight:geometry.size.height,alignment:.top)
            }.scrollBounceBehavior(.basedOnSize)
        }.sheet(item:$selectedTrip) { TripDetailView(trip:$0) }
            .sheet(isPresented:$addingFill) { FuelForm() }
            .sheet(isPresented:$fuelLogbook) { FuelLedgerView() }
            .accessibilityIdentifier("today.content")
    }

    private var dateHeader: some View {
        VStack(alignment:.leading,spacing:3) {
            Text(presentation.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.title2.weight(.semibold)).minimumScaleFactor(0.8)
            Text(presentation.vehicleTitle ?? "No vehicle selected").font(.subheadline).foregroundStyle(Palette.secondaryText)
        }.accessibilityElement(children:.combine)
    }

    private var readinessCard: some View {
        SectionCard(title:readinessTitle,icon:readinessIcon) {
            VStack(alignment:.leading,spacing:10) {
                Text(readinessMessage).font(.subheadline).foregroundStyle(Palette.secondaryText)
                HStack(spacing:8) {
                    StatusPill(state:gpsState,text:"GPS")
                    StatusPill(state:scannerState,text:scannerLabel)
                    StatusPill(state:.ready,text:"Local")
                }.accessibilityElement(children:.contain)
                if presentation.queuedTransfers > 0 { StatusPill(state:.queued,text:"\(presentation.queuedTransfers) queued") }
            }
        }
    }

    @ViewBuilder private var quickActions:some View {
        let actions=Group {
            AppButton(title:"Add fill-up",icon:"fuelpump.fill") { addingFill=true }
                .disabled(!canLogFill).accessibilityIdentifier("today.add-fill")
            AppButton(title:store.isFinishing ? "Saving…":(store.pendingGPS ? "Cancel GPS request":(store.recording ? "Finish & save":(store.scanner.connecting ? "Connecting scanner…":"Start recording"))),
                      icon:store.recording ? "stop.fill":"record.circle",secondary:true) {
                if store.pendingGPS { store.cancelGPS() }
                else if store.recording { store.finishRecording() }
                else { store.startRecordingFromToday() }
            }.disabled(store.isFinishing || (!store.recording && store.scanner.connecting))
                .accessibilityIdentifier("today.start-recording")
        }
        if dynamicTypeSize.isAccessibilitySize { VStack(spacing:10) { actions } }
        else { HStack(spacing:10) { actions } }
        Button(store.recording ? "View current recording":"Recording options",systemImage:"waveform.path.ecg") { store.selectedTab = .record }
            .accessibilityIdentifier("today.recording-details")
        if !canLogFill {
            Text(store.activeVehicle == nil ? "Choose a vehicle before logging fuel.":"Select a real vehicle before logging fuel.")
                .font(.caption).foregroundStyle(Palette.secondaryText)
        }
    }

    private var todayTotals: some View {
        SectionCard(title:"Today",icon:"road.lanes") {
            if presentation.todayDriveCount == 0 {
                HStack(spacing:12) {
                    Image(systemName:"road.lanes").foregroundStyle(Palette.unavailable)
                    VStack(alignment:.leading,spacing:3) {
                        Text("No real drives recorded today").font(.subheadline.weight(.semibold))
                        Text("Sample drives never contribute to these totals.").font(.caption).foregroundStyle(Palette.secondaryText)
                    }
                }
            } else {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                    MetricTile(title:"Distance",value:units.number(presentation.todayDistanceKM,"km",digits:1),unit:units.label("km"),source:"Recorded",showsFreshness:false)
                    MetricTile(title:"Duration",value:duration(presentation.todayDuration),source:"Recorded",showsFreshness:false)
                    MetricTile(title:"Drives",value:String(presentation.todayDriveCount),source:"Saved locally",showsFreshness:false)
                    MetricTile(title:"Trip fuel",value:units.number(presentation.todayFuelLitres,"L",digits:2),unit:units.label("L"),
                               state:presentation.todayFuelLitres == nil ? .unavailable:.ready,source:"Measured",showsFreshness:false)
                }
                if presentation.todayFuelDriveCount < presentation.todayDriveCount {
                    Text("Trip fuel is shown only for \(presentation.todayFuelDriveCount) of \(presentation.todayDriveCount) drives with measured fuel coverage.")
                        .font(.caption).foregroundStyle(Palette.secondaryText)
                }
            }
        }
    }

    @ViewBuilder private var latestDrive: some View {
        if let trip = presentation.latestTrip {
            SectionCard(title:"Most recent drive",icon:"clock.arrow.circlepath") {
                Button { selectedTrip=trip } label: {
                    VStack(alignment:.leading,spacing:9) {
                        HStack { Text(trip.name).font(.headline);Spacer();Image(systemName:"chevron.right") }
                        Text(trip.startedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(Palette.secondaryText)
                        if !trip.route.isEmpty { NativeRouteMap(route:trip.route).frame(height:150).clipShape(RoundedRectangle(cornerRadius:Palette.Radius.medium)) }
                        HStack { Text("\(units.text(trip.distanceKM,"km",digits:1))");Spacer();Text(duration(trip.duration)) }.font(.subheadline).monospacedDigit()
                        SourceBadge(source:trip.source.title,verified:true)
                    }.foregroundStyle(Palette.primaryText).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("today.latest-drive")
            }
        } else {
            EmptyStateCard(icon:"road.lanes",title:"Your next drive starts here",
                           message:"Record with iPhone GPS or a configured scanner. Missing signals will remain unavailable.",
                           actionTitle:"Open Record") { store.selectedTab = .record }
        }
    }

    @ViewBuilder private var latestFill: some View {
        if let fill = presentation.latestFill {
            SectionCard(title:"Latest fill",icon:"fuelpump.fill") {
                HStack(alignment:.firstTextBaseline) {
                    VStack(alignment:.leading,spacing:4) {
                        Text(fill.stationName ?? "Fuel fill").font(.subheadline.weight(.semibold))
                        Text(fill.date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(Palette.secondaryText)
                    }
                    Spacer();Text("\(units.text(fill.litres,"L",digits:1))").font(.headline).monospacedDigit()
                }
                Text("Purchased fill quantity; it is never counted as trip fuel consumed.").font(.caption).foregroundStyle(Palette.secondaryText)
                Button("Open fuel logbook") { fuelLogbook=true }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("today.fuel-logbook")
            }
        } else {
            SectionCard(title:"Latest fill",icon:"fuelpump") {
                Text("No real fuel entries for this vehicle.").font(.subheadline).foregroundStyle(Palette.secondaryText)
                Button("Open fuel logbook") { fuelLogbook=true }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("today.fuel-logbook")
            }
        }
    }

    private var canLogFill:Bool { store.activeVehicle != nil && store.activeVehicle?.isSample != true && !store.libraryReadOnly }

    private var readinessTitle:String {
        if store.isFinishing { return "Saving recording" }
        if store.recording { return "Recording · \(store.timerText)" }
        if store.pendingGPS { return "Starting GPS recording" }
        if store.scanner.connecting { return "Connecting scanner" }
        if store.activeVehicle?.scannerConnection != nil { return store.automaticScannerRecordingEnabled ? "Automatic recording ready":"Recording paused" }
        switch presentation.readiness { case .ready:return "Ready to record";case .needsVehicle:return "Choose a vehicle";case .sampleVehicle:return "Sample vehicle selected" }
    }
    private var readinessMessage:String {
        if store.recording { return "Your drive is recording locally. You can lock your phone; Finish saves the drive." }
        if store.activeVehicle?.scannerConnection != nil {
            if !store.automaticScannerRecordingEnabled { return "This drive has finished. Start recording begins another drive; automatic recording resumes when the scanner reconnects." }
            return "With your configured MX+ connected, recording starts when the selected vehicle returns valid vehicle data. Open DriveLine before driving; Start recording also connects your saved scanner."
        }
        switch presentation.readiness {
        case .ready:return "Recordings save locally first. Scanner telemetry is optional."
        case .needsVehicle:return "Add or select a real vehicle before recording."
        case .sampleVehicle:return "Sample data is isolated and never contributes to real totals."
        }
    }
    private var readinessIcon:String { presentation.readiness == .ready ? "checkmark.circle.fill":"exclamationmark.circle" }
    private var gpsState:DriveLineSemanticState { store.gps.lastFix == nil ? .stale:.ready }
    private var scannerState:DriveLineSemanticState { presentation.scannerConnected ? .ready:(presentation.scannerConnecting ? .stale:.unavailable) }
    private var scannerLabel:String { presentation.scannerConnected ? "Scanner":(presentation.scannerConnecting ? "Connecting":"No scanner") }
    private func duration(_ seconds:TimeInterval)->String {
        let minutes=max(0,Int(seconds)/60);return minutes>=60 ? "\(minutes/60) h \(minutes%60) m":"\(minutes) min"
    }
}

#if DEBUG
#Preview("Today · Light") { DriveLineCanvas(tab:.today,scheme:.light) }
#Preview("Today · Dark") { DriveLineCanvas(tab:.today,scheme:.dark) }
#endif
